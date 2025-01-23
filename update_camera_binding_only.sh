#!/bin/bash
# Define the function to kill processes with 'vidi' or 'vidireports' in their names
kill_vidi_processes() {
    # Localize variables to avoid interfering with other parts of the script
    local pids pid
    # Capture the list of PIDs
    pids=$(ps aux | grep -E 'vidi|vidireports' | grep -v grep | awk '{print $2}')
    # Check if any PIDs were found
    if [ -n "$pids" ]; then
        for pid in $pids; do
            # Double-check that the PID is a number
            if [ "$pid" -eq "$pid" ] 2>/dev/null; then
                echo "Killing process with PID $pid"
                kill -9 $pid
            else
                echo "Skipping invalid PID: $pid"
            fi
        done
    else
        echo "No processes found with 'vidi' or 'vidireports' in the name."
    fi
    # Unset the variables to reset them (optional but ensures clean state)
    unset pids pid
}
# Exit on error
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

# Copy yaml file to camerapub directory
#cp /home/zignage/nomesh.yaml /home/zignage/camerapub/

# Change directory and run ansible playbook
cd /home/zignage/camerapub

# Return to home directory
cd /home/zignage
sleep 1s

sudo systemctl stop vidireports || true
kill_vidi_processes || true
sudo systemctl stop vidireports || true
cd /home/zignage/camerapub
sudo systemctl stop vidireports || true
ansible-playbook update_camera_binder.yaml -i invetory-players-version-2.ini
sudo systemctl stop vidireports || true
kill_vidi_processes || true

# Create a temporary file to store the output of v4l2-ctl --list-devices
temp_file=$(mktemp)
v4l2-ctl --list-devices > "$temp_file"

# Define the configuration file path
config_file="/home/zignage/.vidireports/config/instance0.cfg"

# Define a file to save the changes (this will be a non-temporary file)
modified_config="/home/zignage/.vidireports/config/modified_camera_config.txt"

# Use a counter to keep track of the camera instance (for multiple cameras)
camera_index=0

# Flag to track if we've found the desired camera
camera_found=0

# Loop through each camera block in the v4l2-ctl output
while read -r camera_name device_info; do
    echo "Processing camera: $camera_name"  # Debugging: Show camera name
    echo "Device info: $device_info"        # Debugging: Show device info

    # Check if the camera name contains "4K"
    if [[ "$camera_name" != *"4K"* ]]; then
        # Extract the string inside the parentheses using grep and sed
        usb_id=$(echo "$device_info" | grep -oP '\(([^)]+)\)' | sed 's/[()]//g')

        if [[ -n "$usb_id" ]]; then
            echo "Extracted USB ID: $usb_id"  # Debugging: Show extracted USB ID

            # Construct the new camera line with 1920x1080 resolution
            new_camera_line="camera = usb://$usb_id@1920x1080/MJPG"

            # Save the new camera configuration to a separate file
            echo "$new_camera_line" > "$modified_config"

            echo "Saved new camera configuration to $modified_config"

            # Set the flag to indicate the camera was found
            camera_found=1
        else
            echo "No USB ID found for camera: $camera_name"
        fi

        # We process only one camera that does not contain "4K", so break after finding it
        break
    fi

# Use awk to extract camera names and device info in pairs (assuming the format is consistent)
done < <(awk '/\)/{getline device; print $0, device}' "$temp_file")

# Clean up the temporary file
rm "$temp_file"

# Check if the desired camera was found
if [ $camera_found -eq 0 ]; then
    echo "Desired camera (non-4K) not found."
fi

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
echo "stopping"
kill_vidi_processes || true
sleep 15s
sudo systemctl stop vidireports
kill_vidi_processes || true
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
sudo tee /etc/systemd/system/vidireports.service > /dev/null <<'EOF'
[Unit]
Description=VidiReports Service
After=network.target
[Service]
Type=simple
ExecStart=/home/zignage/.vidireports/7.7.8.4/./vidireports -d -l /home/zignage/.vidireports/VidiReports.log -c /home/zignage/.vidireports/config/
Restart=on-failure
User=zignage
TimeoutStopSec=30
Group=video
[Install]
WantedBy=multi-user.target
EOF

# Reload systemd daemon and restart service
sudo systemctl daemon-reload
kill_vidi_processes || true
sudo systemctl stop vidireports
kill_vidi_processes || true
kill_vidi_processes || true
sudo systemctl start vidireports
echo "Service updated and restarted successfully"
echo "part 3 complete"
