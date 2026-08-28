#!/usr/bin/env bash

# ---------------------------------------------------------
# Guardamos la configuración actual de la terminal para
# poder restaurarla exactamente como estaba al salir.
# ---------------------------------------------------------
old_stty=$(stty -g)

cleanup() {
    stty "$old_stty"   # restaurar teclado (echo, modo canónico, etc.)
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
stty -echo -icanon min 0 time 0

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
# Bucle principal: SOLO redibuja la zona de procesos.
# Cualquier tecla/escape que haya llegado se descarta antes
# de redibujar, para que no se cuele nada residual.
# ---------------------------------------------------------
while true; do

    # Descartar cualquier entrada pendiente (flechas, scroll, etc.)
    while read -r -t 0; do
        read -r -n 1 _ 2>/dev/null
    done

    tput cup "$process_start_row" 0

    printed=0
    for dir in /proc/[0-9]*/; do

        if [ "$printed" -ge "$process_area_rows" ]; then
            break
        fi

        pid="${dir#/proc/}"
        pid="${pid%/}"

        name=$(grep '^Name:' "$dir/status" 2>/dev/null | cut -f2)
        state=$(grep '^State:' "$dir/status" 2>/dev/null | cut -f2-)

        [ -z "$name" ] && continue

        cpu=$(awk '{print $39}' "$dir/stat" 2>/dev/null)
        proc_time=$(awk '{print $14 + $15}' "$dir/stat" 2>/dev/null)

        row=$(printf "%s %s %s %s %s" \
            "$(field "$pid" "$pid_width")" \
            "$(field "$name" "$process_width")" \
            "$(field "$state" "$state_width")" \
            "$(field "$cpu" "$cpu_width")" \
            "$(field "$proc_time" "$percent_width")")
        draw_line "$row"

        printed=$((printed + 1))
    done

    while [ "$printed" -lt "$process_area_rows" ]; do
        draw_line ""
        printed=$((printed + 1))
    done

    sleep 1
done