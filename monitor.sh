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

# El resto del espacio queda para PROCESS
process_width=$((terminal_width - pid_width - state_width - cpu_width - percent_width - spaces))

# Ancho mínimo para PROCESS
if [ "$process_width" -lt 20 ]; then
    process_width=20
fi

printf "%-${pid_width}s %-${process_width}s %-${state_width}s %-${cpu_width}s %-${percent_width}s\n" \
    "PID" "PROCESS" "STATE" "CPU" "%CPU"

for dir in /proc/[0-9]*/; do

    pid="${dir#/proc/}"
    pid="${pid%/}"

    name=$(grep '^Name:' "$dir/status" | cut -f2)
    state=$(grep '^State:' "$dir/status" | cut -f2-)

    # Obtener la CPU donde se ejecuta el proceso
    cpu=$(awk '{print $39}' "$dir/stat")

    # Obtener el tiempo de CPU usado por el proceso
    proc_time=$(awk '{print $14 + $15}' "$dir/stat")

    printf "%-${pid_width}s %-${process_width}s %-${state_width}s %-${cpu_width}s %-${percent_width}s\n" \
        "$pid" "$name" "$state" "$cpu" "$proc_time"

done