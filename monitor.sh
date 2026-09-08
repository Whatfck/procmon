#!/usr/bin/env bash

have_tty=false
old_stty=""
if [ -t 0 ] && [ -t 1 ]; then
    have_tty=true
    old_stty=$(stty -g 2>/dev/null) || have_tty=false
fi

cleanup() {
    if [ "$have_tty" = true ]; then
        stty "$old_stty" 2>/dev/null
        tput cnorm 2>/dev/null
        tput rmcup 2>/dev/null
    fi
    exit 0
}
trap cleanup EXIT INT TERM

if [ "$have_tty" = true ]; then
    stty -echo -icanon min 0 time 0
    tput smcup 2>/dev/null
    tput civis 2>/dev/null
fi

terminal_width=$(tput cols 2>/dev/null || printf '100')
terminal_lines=$(tput lines 2>/dev/null || printf '30')
[ -z "$terminal_width" ] && terminal_width=100
[ -z "$terminal_lines" ] && terminal_lines=30

pid_width=8
process_width=24
state_width=16
core_width=6
percent_width=7
memory_width=8
column_spaces=5
process_width=$((terminal_width - pid_width - state_width - core_width - percent_width - memory_width - column_spaces))
[ "$process_width" -lt 16 ] && process_width=16
inner_width=$((pid_width + process_width + state_width + core_width + percent_width + memory_width + column_spaces))

field() {
    local text="$1" width="$2"
    printf "%-${width}.${width}s" "$text"
}

draw_border() {
    printf '%*s\n' "$inner_width" '' | tr ' ' '='
}

draw_line() {
    printf "%-${inner_width}.${inner_width}s\n" "$1"
}

declare -A previous_process_ticks previous_core_total previous_core_idle
core_names=()

read_cpu_snapshot() {
    core_names=()
    while read -r cpu user nice system idle iowait irq softirq steal guest guest_nice _; do
        [[ "$cpu" =~ ^cpu[0-9]+$ ]] || continue
        core_names+=("$cpu")
        previous_core_total["$cpu"]=$((user + nice + system + idle + iowait + irq + softirq + steal + guest + guest_nice))
        previous_core_idle["$cpu"]=$((idle + iowait))
    done < /proc/stat
}

read_cpu_snapshot
core_count=${#core_names[@]}
core_rows=$(( (core_count + 1) / 2 ))
header_rows=$((core_rows + 6))
footer_rows=3
process_area_rows=$((terminal_lines - header_rows - footer_rows))
[ "$process_area_rows" -lt 1 ] && process_area_rows=1
footer_start_row=$((terminal_lines - footer_rows))

clk_tck=$(getconf CLK_TCK 2>/dev/null)
[ -z "$clk_tck" ] && clk_tck=100
previous_now=""

while true; do
    if [ "$have_tty" = true ]; then
        while read -r -t 0; do read -r -n 1 _ 2>/dev/null; done
    fi

    now=$(date +%s.%N)
    if [ -n "$previous_now" ]; then
        elapsed=$(awk -v a="$now" -v b="$previous_now" 'BEGIN{d=a-b; if(d<=0)d=1; printf "%.6f", d}')
    else
        elapsed=1
    fi
    previous_now=$now
    elapsed_ticks=$(awk -v e="$elapsed" -v c="$clk_tck" 'BEGIN{printf "%.6f", e*c}')

    core_usage=()
    while read -r cpu user nice system idle iowait irq softirq steal guest guest_nice _; do
        [[ "$cpu" =~ ^cpu[0-9]+$ ]] || continue
        total=$((user + nice + system + idle + iowait + irq + softirq + steal + guest + guest_nice))
        idle_all=$((idle + iowait))
        old_total=${previous_core_total["$cpu"]:-$total}
        old_idle=${previous_core_idle["$cpu"]:-$idle_all}
        delta_total=$((total - old_total))
        delta_idle=$((idle_all - old_idle))
        usage=$(awk -v t="$delta_total" -v i="$delta_idle" 'BEGIN{if(t<=0)t=1; u=(1-i/t)*100; if(u<0)u=0; if(u>100)u=100; printf "%.1f",u}')
        core_usage+=("$usage")
        previous_core_total["$cpu"]=$total
        previous_core_idle["$cpu"]=$idle_all
    done < /proc/stat

    rows=()
    for dir in /proc/[0-9]*/; do
        pid=${dir#/proc/}; pid=${pid%/}
        name=$(awk '/^Name:/{print $2; exit}' "$dir/status" 2>/dev/null)
        state=$(awk '/^State:/{sub(/^State:[[:space:]]*/, ""); print; exit}' "$dir/status" 2>/dev/null)
        memory=$(awk '/^VmRSS:/{print $2; exit}' "$dir/status" 2>/dev/null)
        [ -z "$name" ] && continue

        stat_line=$(cat "$dir/stat" 2>/dev/null) || continue
        stat_rest=${stat_line##*) }
        read -r -a stat_fields <<< "$stat_rest"
        [ "${#stat_fields[@]}" -lt 37 ] && continue
        proc_ticks=$((stat_fields[11] + stat_fields[12]))
        core=${stat_fields[36]}
        last=${previous_process_ticks[$pid]:-$proc_ticks}
        delta=$((proc_ticks - last))
        [ "$delta" -lt 0 ] && delta=0
        previous_process_ticks[$pid]=$proc_ticks
        percent=$(awk -v d="$delta" -v e="$elapsed_ticks" 'BEGIN{if(e<=0)e=1; printf "%.1f", (d/e)*100}')
        [ -z "$memory" ] && memory=0
        row=$(printf "%s %s %s %s %s %s" \
            "$(field "$pid" "$pid_width")" "$(field "$name" "$process_width")" \
            "$(field "$state" "$state_width")" "$(field "$core" "$core_width")" \
            "$(field "${percent}%" "$percent_width")" "$(field "${memory}K" "$memory_width")")
        rows+=("$delta"$'\t'"$row")
    done

    for pid in "${!previous_process_ticks[@]}"; do
        [ -d "/proc/$pid" ] || unset 'previous_process_ticks[$pid]'
    done

    if [ "$have_tty" = true ]; then
        tput cup 0 0 2>/dev/null
        draw_border
        draw_line "procmon - CPU por nucleo"
        draw_border
        core_index=0
        for ((row_index=0; row_index<core_rows; row_index++)); do
            left=""; right=""
            if [ "$core_index" -lt "$core_count" ]; then
                left=$(printf "%-8s [%6.1f%%]" "CPU$core_index" "${core_usage[$core_index]:-0}")
                core_index=$((core_index + 1))
            fi
            if [ "$core_index" -lt "$core_count" ]; then
                right=$(printf "%-8s [%6.1f%%]" "CPU$core_index" "${core_usage[$core_index]:-0}")
                core_index=$((core_index + 1))
            fi
            draw_line "$left    $right"
        done
        header=$(printf "%s %s %s %s %s %s" \
            "$(field PID "$pid_width")" "$(field PROCESS "$process_width")" \
            "$(field STATE "$state_width")" "$(field CORE "$core_width")" \
            "$(field CPU% "$percent_width")" "$(field RSS "$memory_width")")
        draw_border; draw_line "$header"; draw_border
        printed=0
        while IFS=$'\t' read -r _delta row; do
            [ "$printed" -ge "$process_area_rows" ] && break
            draw_line "$row"; printed=$((printed + 1))
        done < <(printf '%s\n' "${rows[@]}" | sort -t$'\t' -k1,1rn)
        while [ "$printed" -lt "$process_area_rows" ]; do draw_line ""; printed=$((printed + 1)); done
        tput cup "$footer_start_row" 0 2>/dev/null
        draw_border; draw_line "Actualizando cada 1 segundo - Ctrl+C para salir"; draw_border
    else
        printf 'procmon - CPU por nucleo\n'
        for ((core_index=0; core_index<core_count; core_index++)); do
            printf 'CPU%-4s %6.1f%%\n' "$core_index" "${core_usage[$core_index]:-0}"
        done
        printf '\nPID      PROCESS                  STATE            CORE   CPU%%    RSS\n'
        printf '%s\n' "${rows[@]}" | sort -t$'\t' -k1,1rn | cut -f2-
    fi
    sleep 1
done