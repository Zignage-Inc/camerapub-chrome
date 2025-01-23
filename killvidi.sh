#!/bin/bash

#kill_vidi_processes() {
#    for pid in $(ps -eo pid,comm | awk '/vidi/ && $1 != '$$' && $1 != 1 {print $1}'); do
#        echo "Killing process with PID $pid"
#        kill -9 "$pid" 2>/dev/null || true
#    done
#}

echo "Testing kill_vidi_processes..."
#kill_vidi_processes
echo "Function completed."
