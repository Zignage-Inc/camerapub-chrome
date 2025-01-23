#!/bin/bash

kill_vidi_processes() {
    local pids pid
    pids=$(pgrep -f 'vidi|vidireports' | grep -v "$$")
    if [ -n "$pids" ]; then
        for pid in $pids; do
            if [ "$pid" -ne 1 ] && [ "$pid" -ne "$$" ]; then
                echo "Killing process with PID $pid"
                kill -9 "$pid" || true
            else
                echo "Skipping critical or self process: $pid"
            fi
        done
    else
        echo "No processes found with 'vidi' or 'vidireports' in the name."
    fi
}

echo "Testing kill_vidi_processes..."
kill_vidi_processes
echo "Function completed."
