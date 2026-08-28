#!/usr/bin/env bash

# Ancho de la terminal
terminal_width=$(tput cols)

# Anchos de las columnas fijas
pid_width=8
state_width=18
cpu_width=6
percent_width=6

# Espacios entre columnas
spaces=4

# Ancho interno total de la caja (contenido entre los bordes ║ ║)
# Restamos 4: 2 caracteres de borde (║ ║) + 2 espacios de margen interno
inner_width=$((terminal_width - 4))

# El resto del espacio queda para PROCESS
process_width=$((terminal_width - pid_width - state_width - cpu_width - percent_width - spaces))

# Ancho mínimo para PROCESS
if [ "$process_width" -lt 20 ]; then
    process_width=20
fi

# Recalculamos inner_width en base al ancho real de la línea de datos,
# para que los bordes cuadren exactamente con el contenido
line_content_width=$((pid_width + process_width + state_width + cpu_width + percent_width + spaces))
inner_width=$line_content_width

# --- Funciones para dibujar bordes ---

draw_top() {
    printf '═%.0s' $(seq 1 "$inner_width")
    printf "\n"
}

draw_mid() {
    printf '═%.0s' $(seq 1 "$inner_width")
    printf "\n"
}

draw_bottom() {
    printf '═%.0s' $(seq 1 "$inner_width")
    printf "\n"
}

# Imprime una línea de contenido, rellenando con espacios (sin bordes laterales)
draw_line() {
    local content="$1"
    printf "%-${inner_width}s\n" "$content"
}

# --- Cabecera de la caja ---

draw_top
draw_line "procmon — Linux Process Monitor"
draw_mid

header=$(printf "%-${pid_width}s %-${process_width}s %-${state_width}s %-${cpu_width}s %-${percent_width}s" \
    "PID" "PROCESS" "STATE" "CPU" "%CPU")
draw_line "$header"
draw_mid

# --- Cuerpo: datos de procesos ---

for dir in /proc/[0-9]*/; do

    pid="${dir#/proc/}"
    pid="${pid%/}"

    name=$(grep '^Name:' "$dir/status" | cut -f2)
    state=$(grep '^State:' "$dir/status" | cut -f2-)

    # Obtener la CPU donde se ejecuta el proceso
    cpu=$(awk '{print $39}' "$dir/stat")

    # Obtener el tiempo de CPU usado por el proceso
    proc_time=$(awk '{print $14 + $15}' "$dir/stat")

    row=$(printf "%-${pid_width}s %-${process_width}s %-${state_width}s %-${cpu_width}s %-${percent_width}s" \
        "$pid" "$name" "$state" "$cpu" "$proc_time")
    draw_line "$row"

done

# --- Pie de la caja ---

draw_mid
draw_line "Refreshing every 1 second • Press Ctrl+C to exit"
draw_bottom