#!/bin/bash
set -e
modified_config="/home/zignage/.vidireports/config/modified_camera_config.txt"
config_file="/home/zignage/.vidireports/config/instance0.cfg"
config_file_etc="/etc/vidireports/instance0.cfg"
# Install required packages
echo "Installing required packages..."
sudo apt-get install -y sshpass ansible git || {
    echo "Failed to install required packages"
    exit 1
}
# Create necessary directories
echo "Creating directories..."
for dir in "/home/zignage/camera_binder" "/home/zignage/camerapub"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || {
            echo "Failed to create directory: $dir"
            exit 1
        }
    fi
done
# Remove existing repo if it exists
echo "Removing existing repo if present..."
rm -rf /home/zignage/camerapub
# Clone the public GitHub repo
echo "Cloning repository..."
git clone https://github.com/chrismcfee/camerapub.git /home/zignage/camerapub || {
    echo "Failed to clone repository"
    exit 1
}
# Copy files to camera_binder directory
echo "Copying files..."
for file in "camera-setup.sh" "camera_binder.service" "camera_binder.py"; do
    cp "/home/zignage/camerapub/$file" "/home/zignage/camera_binder/" || {
        echo "Failed to copy $file"
        exit 1
    }
done
echo "Script completed successfully so far..."
sleep 1s 
echo "continuing..."
sleep 1s
cd /home/zignage/camerapub
# Return to home directory
cd /home/zignage
sleep 1s
sudo systemctl stop vidireports || true
cd /home/zignage && ./killvidi.sh
cd /home/zignage/camerapub
ansible-playbook update_camera_binder.yaml -i invetory-players-version-2.ini
echo "part 1 starting soon"

# Create a temporary file to store the output of v4l2-ctl --list-devices
# Create a temporary file to store the output of v4l2-ctl --list-devices
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
    exit 1
fi

# Clean up
rm "$temp_file"

# Remove unwanted camera lines and update configuration
if [[ -f "$modified_config" ]]; then
    # Create temp file for cleaned config
    temp_config=$(mktemp)

    # Remove unwanted camera lines
    sed '/camera.*loopback/d' "$config_file" | \
        sed '/camera.*video/d' > "$temp_config"

    # Append new camera configuration
    cat "$modified_config" >> "$temp_config"

    # Update both configuration files
    cp "$temp_config" "$config_file"
    if [[ -f "$config_file_etc" ]]; then
        cp "$temp_config" "$config_file_etc"
    fi

    # Cleanup
    rm "$temp_config"
    rm "$modified_config"

    echo "Configuration updated successfully"
else
    echo "No camera configuration found to apply"
    exit 1
fi

# Restart service
sudo systemctl stop vidireports
cd /home/zignage && ./killvidi.sh
sleep 5s
sudo systemctl start vidireports

# Final daemon reload and service restart
sudo systemctl daemon-reload
sudo systemctl restart vidireports

echo "Service updated and restarted successfully"
echo "config modified successfully"
echo "attempting to restart service yet again to load modified config"
sudo systemctl restart vidireports || true
echo "part 1 successful"
echo "trying to stop running processes"
cd /home/zignage && ./killvidi.sh
sleep 5s
sudo systemctl stop vidireports
cd /home/zignage && ./killvidi.sh
echo "part 2 of script"
# Define the main configuration file path


# Check if the modified configuration file exists

sudo systemctl start vidireports
echo "part 2 successful"
echo "Completed"
echo "part 3 - load the new service file"
echo "moved this part to other script which should execute automatically with this one"

# Reload systemd daemon and restart service
sudo systemctl daemon-reload
sudo systemctl stop vidireports
sudo systemctl start vidireports
echo "Service updated and restarted successfully"
echo "this script update camera binding is now complete"
