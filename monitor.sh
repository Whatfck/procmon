#!/usr/bin/env bash

printf "%-8s %-20s %s\n" "PID" "PROCESS" "STATE"

for dir in /proc/[0-9]*/; do
    pid="${dir#/proc/}"
    pid="${pid%/}"

    name=$(grep '^Name:' "$dir/status" | cut -f2)
    state=$(grep '^State:' "$dir/status" | cut -f2-)

    printf "%-8s %-20s %s\n" "$pid" "$name" "$state"
done