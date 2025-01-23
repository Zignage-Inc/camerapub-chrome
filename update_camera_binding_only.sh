#!/bin/bash
set -e
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
set -x
cd /home/zignage && ./killvidi.sh
cd /home/zignage/camerapub
set -x
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
fi

# Clean up
rm "$temp_file"

# Remove unwanted camera lines while preserving the correct one
# Create a temporary file for the modified config
temp_config=$(mktemp)

# Remove camera lines with loopback devices but preserve other camera configurations
sed '/camera.*loopback/d' "/home/zignage/.vidireports/config/instance0.cfg" | \
    sed '/camera.*video/d' > "$temp_config"

# Replace original file with cleaned version
mv "$temp_config" "/home/zignage/.vidireports/config/instance0.cfg"

echo "Removed unwanted camera configurations while preserving the correct camera line"

sudo systemctl start vidireports || true

echo "waiting to modify config"
sleep 15s
echo "attempting to modifdy config"
# Define the main configuration file path
config_file="/home/zignage/.vidireports/config/instance0.cfg"

# Define the file containing the modified camera configuration
modified_config="/home/zignage/.vidireports/config/modified_camera_config.txt"

# Check if the modified configuration file exists
if [[ -f "$modified_config" ]]; then
    echo "Appending modified camera configuration to the main config file..."

    # Append the modified camera configuration to the main configuration file
    cat "$modified_config" >> "$config_file"

    echo "Appended contents of $modified_config to $config_file"

    # Optionally, remove the modified configuration file after appending
    # If you want to keep the file, comment or remove the next line
    rm "$modified_config"
    echo "Removed the temporary modified configuration file $modified_config"
else
    echo "Modified camera configuration file not found. Nothing to append."
fi
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
config_file_2="/home/zignage/.vidireports/config/instance0.cfg"
config_file_3="/etc/vidireports/instance0.cfg"
# Define the file containing the modified camera configuration
modified_config_2="/home/zignage/.vidireports/config/modified_camera_config.txt"

# Check if the modified configuration file exists
if [[ -f "$modified_config_2" ]]; then
    echo "Appending modified camera configuration to the main config file..."

    # Append the modified camera configuration to the main configuration file
    cat "$modified_config_2" >> "$config_file_2"
    cat "$modified_config_2" >> "$config_file_3"

    echo "Appended contents of $modified_config_2 to $config_file_2"
    echo "Appended contents of $modified_config_2 to $config_file_3"

    # Optionally, remove the modified configuration file after appending
    # If you want to keep the file, comment or remove the next line
    rm "$modified_config"
    echo "DONE - Removed the temporary modified configuration file $modified_config"
else
    echo "Modified camera configuration file not found. Nothing to append."
fi
sudo systemctl start vidireports
echo "part 2 successful"
echo "Completed"
echo "part 3 - load the new service file"
echo "starting"
# Create/overwrite the service file
VIDIREPORTS_PATH="/home/zignage/.vidireports/7.7.8.4/./vidireports"
LOG_PATH="/home/zignage/.vidireports/VidiReports.log"
CONFIG_PATH="/home/zignage/.vidireports/config/"

# Reload systemd daemon and restart service
sudo systemctl daemon-reload
sudo systemctl stop vidireports
sudo systemctl start vidireports
echo "Service updated and restarted successfully"
echo "part 3 complete"
