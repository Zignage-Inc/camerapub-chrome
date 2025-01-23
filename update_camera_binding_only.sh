#!/bin/bash
set -e

# Define configuration files globally at the start
modified_config="/home/zignage/.vidireports/config/modified_camera_config.txt"
config_file="/home/zignage/.vidireports/config/instance0.cfg"
config_file_etc="/etc/vidireports/instance0.cfg"

# First part of your script remains the same until the camera detection...
#[previous installation and setup code remains unchanged]

echo "part 1 starting soon"

# Stop VidiReports service and kill processes
sudo systemctl stop vidireports || true
cd /home/zignage && ./killvidi.sh

# Camera Detection and Configuration
echo "Detecting camera..."
temp_file=$(mktemp)
v4l2-ctl --list-devices > "$temp_file"

# Look for HD USB Camera (non-4K) and get its USB ID
camera_uid=$(grep -A1 "HD USB Camera" "$temp_file" | grep "usb" | tr -d '\t' | head -n1)

if [ -n "$camera_uid" ]; then
    # Write the camera_uid configuration
    echo "camera_uid = \"$camera_uid\"" > "$modified_config"
    echo "Found camera UID: $camera_uid"
else
    echo "No HD USB camera UID found"
    rm "$temp_file"
    exit 1
fi

# Clean up
rm "$temp_file"

# Update Configuration Files
echo "Updating configuration files..."

if [[ -f "$config_file" ]]; then
    # Create temp file for cleaned config
    temp_config=$(mktemp)

    # Remove unwanted camera lines
    sed '/camera.*loopback/d' "$config_file" | \
        sed '/camera.*video/d' > "$temp_config"

    # Append new camera configuration
    if [[ -f "$modified_config" ]]; then
        cat "$modified_config" >> "$temp_config"

        # Update main config file
        cp "$temp_config" "$config_file"

        # Update etc config if it exists
        if [[ -f "$config_file_etc" ]]; then
            cp "$temp_config" "$config_file_etc"
            echo "Updated both config files with new camera configuration"
        else
            echo "Warning: $config_file_etc not found"
        fi

        # Cleanup
        rm "$temp_config"
        rm "$modified_config"
    else
        echo "Error: Modified camera configuration not found"
        rm "$temp_config"
        exit 1
    fi
else
    echo "Error: Main configuration file not found"
    exit 1
fi

# Final Service Restart
echo "Restarting VidiReports service..."
sudo systemctl stop vidireports
cd /home/zignage && ./killvidi.sh
sleep 5s

# Reload and restart service
sudo systemctl daemon-reload
sudo systemctl start vidireports

echo "Service updated and restarted successfully"
echo "Configuration update complete"
