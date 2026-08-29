#!/usr/bin/env bash

# ---------------------------------------------------------
# Guardamos la configuración actual de la terminal para
# poder restaurarla exactamente como estaba al salir.
# Si no hay una tty real (ej. se ejecuta en background o con
# la salida redirigida), simplemente lo omitimos.
# ---------------------------------------------------------
have_tty=true
old_stty=$(stty -g 2>/dev/null) || have_tty=false

cleanup() {
    if [ "$have_tty" = true ]; then
        stty "$old_stty" 2>/dev/null   # restaurar teclado (echo, modo canónico, etc.)
    fi
    tput cnorm         # mostrar cursor de nuevo
    tput rmcup         # volver a la pantalla original de la terminal
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# ---------------------------------------------------------
# Bloquear el teclado mientras corre el monitor:
# -echo    -> no repetir en pantalla lo que se pulsa
# -icanon  -> no esperar Enter / no hacer buffering de línea
# min 0 time 0 -> lecturas no bloqueantes (no lo usamos, pero
#                 evita que se acumulen pulsaciones en el buffer)
# Así, si el usuario scrollea o pulsa flechas, las secuencias
# de escape (^[[B, ^[[A, etc.) NUNCA llegan a imprimirse.
# ---------------------------------------------------------
if [ "$have_tty" = true ]; then
    stty -echo -icanon min 0 time 0
fi

tput smcup   # entrar a la pantalla alternativa (como vim/less/htop)
tput civis   # ocultar el cursor
clear

# ---------------------------------------------------------
# Cálculo de anchos (una sola vez; si redimensionas la
# terminal, reinicia el script)
# ---------------------------------------------------------
terminal_width=$(tput cols)
terminal_lines=$(tput lines)

pid_width=8
state_width=18
cpu_width=6
percent_width=6
spaces=4

process_width=$((terminal_width - pid_width - state_width - cpu_width - percent_width - spaces))
if [ "$process_width" -lt 20 ]; then
    process_width=20
fi

inner_width=$((pid_width + process_width + state_width + cpu_width + percent_width + spaces))

draw_border() {
    printf '═%.0s' $(seq 1 "$inner_width")
    printf "\n"
}

# Trunca y rellena el contenido EXACTO al ancho de la caja,
# para que nunca se desborde ni provoque wrap de línea.
draw_line() {
    local content="$1"
    printf "%-${inner_width}.${inner_width}s\n" "$content"
}

# Igual que draw_line pero para un solo campo (columna)
field() {
    local text="$1" width="$2"
    printf "%-${width}.${width}s" "$text"
}

# ---------------------------------------------------------
# Distribución vertical de la pantalla
# ---------------------------------------------------------
header_lines=5
footer_lines=3
footer_start_row=$((terminal_lines - footer_lines))

process_start_row=$header_lines
process_area_rows=$((footer_start_row - process_start_row))
if [ "$process_area_rows" -lt 1 ]; then
    process_area_rows=1
fi

# ---------------------------------------------------------
# Encabezado — se dibuja UNA sola vez
# ---------------------------------------------------------
tput cup 0 0
draw_border
draw_line "procmon — Linux Process Monitor"
draw_border
header=$(printf "%s %s %s %s %s" \
    "$(field "PID" "$pid_width")" \
    "$(field "PROCESS" "$process_width")" \
    "$(field "STATE" "$state_width")" \
    "$(field "CPU" "$cpu_width")" \
    "$(field "%CPU" "$percent_width")")
draw_line "$header"
draw_border

# ---------------------------------------------------------
# Pie — se dibuja UNA sola vez, anclado al final
# ---------------------------------------------------------
tput cup "$footer_start_row" 0
draw_border
draw_line "Refreshing every 1 second • Press Ctrl+C to exit"
draw_border

# ---------------------------------------------------------
# Guardamos el tiempo de CPU de la lectura anterior de cada
# PID, para calcular cuánto CPU consumió en el último segundo
# (delta), que es lo que se usa para ordenar y para el %CPU.
#
# clk_tck = "ticks" de CPU por segundo que usa el kernel para
# medir utime/stime en /proc/[pid]/stat (normalmente 100).
# %CPU real = (delta_ticks / (segundos_transcurridos * clk_tck)) * 100
#
# prev_now guarda el instante exacto (con decimales) de la
# lectura anterior, para no asumir que pasó "1 segundo" justo
# -el sleep + el tiempo de procesamiento nunca es exacto-.
# ---------------------------------------------------------
declare -A prev_time
clk_tck=$(getconf CLK_TCK 2>/dev/null)
[ -z "$clk_tck" ] && clk_tck=100
prev_now=""

while true; do

    # Descartar cualquier entrada pendiente (flechas, scroll, etc.)
    while read -r -t 0; do
        read -r -n 1 _ 2>/dev/null
    done

    now=$(date +%s.%N)
    if [ -n "$prev_now" ]; then
        elapsed=$(awk -v a="$now" -v b="$prev_now" 'BEGIN{d=a-b; if (d<=0) d=1; printf "%.6f", d}')
    else
        elapsed=1
    fi
    elapsed_ticks=$(awk -v e="$elapsed" -v c="$clk_tck" 'BEGIN{printf "%.6f", e*c}')
    prev_now=$now

    # -------------------------------------------------------
    # 1) Recolectar todos los procesos con su delta de CPU
    # -------------------------------------------------------
    rows=()
    for dir in /proc/[0-9]*/; do

        pid="${dir#/proc/}"
        pid="${pid%/}"

        name=$(grep '^Name:' "$dir/status" 2>/dev/null | cut -f2)
        state=$(grep '^State:' "$dir/status" 2>/dev/null | cut -f2-)

        [ -z "$name" ] && continue

        cpu=$(awk '{print $39}' "$dir/stat" 2>/dev/null)
        proc_time=$(awk '{print $14 + $15}' "$dir/stat" 2>/dev/null)
        [ -z "$proc_time" ] && continue

        last="${prev_time[$pid]:-$proc_time}"
        delta=$((proc_time - last))
        [ "$delta" -lt 0 ] && delta=0

        prev_time[$pid]=$proc_time

        # %CPU real: ticks consumidos / ticks disponibles en el intervalo
        percent=$(awk -v d="$delta" -v et="$elapsed_ticks" \
            'BEGIN{ if (et<=0) et=1; printf "%.1f", (d/et)*100 }')

        row=$(printf "%s %s %s %s %s" \
            "$(field "$pid" "$pid_width")" \
            "$(field "$name" "$process_width")" \
            "$(field "$state" "$state_width")" \
            "$(field "$cpu" "$cpu_width")" \
            "$(field "${percent}%" "$percent_width")")

        # delta al frente (separado con tab) solo para poder ordenar
        rows+=("$delta"$'\t'"$row")
    done

    # -------------------------------------------------------
    # 2) Limpiar del historial los PIDs que ya no existen
    #    (evita que el arreglo crezca sin límite)
    # -------------------------------------------------------
    for pid in "${!prev_time[@]}"; do
        [ -d "/proc/$pid" ] || unset 'prev_time[$pid]'
    done

    # -------------------------------------------------------
    # 3) Ordenar por delta de CPU descendente y quedarnos con
    #    los que caben en la pantalla
    # -------------------------------------------------------
    tput cup "$process_start_row" 0

    printed=0
    while IFS=$'\t' read -r _delta row; do
        [ "$printed" -ge "$process_area_rows" ] && break
        draw_line "$row"
        printed=$((printed + 1))
    done < <(printf '%s\n' "${rows[@]}" | sort -t$'\t' -k1,1 -rn)

    while [ "$printed" -lt "$process_area_rows" ]; do
        draw_line ""
        printed=$((printed + 1))
    done

    sleep 1
done