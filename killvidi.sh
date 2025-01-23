#!/bin/bash

kill_vidi_processes() {
    # Get current process ID
    local current_pid=$$

    # Use more efficient process finding
    ps -eo pid,comm,args | awk -v current="$current_pid" '
        ($2 ~ /vidi/ || $3 ~ /vidi/) && 
        $1 != current && 
        $1 != 1 {
            print $1
        }' | while read -r pid; do
        if [ -n "$pid" ]; then
            echo "Killing process with PID $pid"
            kill -9 "$pid" 2>/dev/null || true
        fi
    done
}

echo "Testing kill_vidi_processes..."
kill_vidi_processes
echo "Function completed."
