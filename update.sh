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

echo "Setting correct home permissions"
sudo chown -R zignage:zignage /home/zignage || {
    echo "Failed to set home permissions"
    exit 1
}

if ! sudo rm vidireports.sh; then
    echo "Script continuing"
fi

echo "Setting correct camera permissions"
sudo chmod 666 /dev/video* || true  # Don't fail if no cameras exist

# Check for required commands
command -v sudo >/dev/null 2>&1 || { echo "sudo is required but not installed. Aborting."; exit 1; }

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
ansible-playbook nomesh.yaml -i invetory-players-version-2.ini

# Return to home directory
cd /home/zignage
sleep 1s
echo "Removing any traces of older vidireports scripts, daemons, and configurations"
echo "BEGIN CLEANUP TASKS"
sleep 1s
if ! sudo systemctl stop vidireports; then
    echo "Unit vidireports stop failed, continuing anyway"
fi
sudo rm -rf /home/zignage/.vidireports
sudo rm -rf /etc/vidireports
sudo rm -rf /opt/vidireports
sudo rm -rf /var/cache/downloads
sudo rm -rf /var/cache/vidireports.lock
echo "FINISHED CLEANUP TASKS"

# Check if the bundle file exists before trying to execute it
if [ -f "wf_vidireports-7.7.8.4-bundle_x86_64_network_1440.sh" ]; then
    chmod +x wf_vidireports-7.7.8.4-bundle_x86_64_network_1440.sh
    ./wf_vidireports-7.7.8.4-bundle_x86_64_network_1440.sh
else
    echo "Bundle file not found"
fi

echo "Waiting a moment in case vidireports needs to resolve new BOX ID"
sleep 30s
echo "waited long enough"
# Check for VidiReports.log
if [ -f "/home/zignage/.vidireports/VidiReports.log" ]; then
    cat /home/zignage/.vidireports/VidiReports.log | grep box_id
else
    echo "VidiReports.log not found in home directory. Checking alternate location:"
    sleep 2s
fi

if [ -f "/etc/vidireports/instance0.cfg" ]; then
    cat /etc/vidireports/instance0.cfg | grep BoxID
else
    echo "VidiReports conf not found in etc directory. Checking alternate location:"
    sleep 2s
fi

sudo systemctl stop vidireports || true
kill_vidi_processes
sudo systemctl stop vidireports || true
cd /home/zignage/camerapub
sudo systemctl stop vidireports || true
ansible-playbook update_camera_binder.yaml -i invetory-players-version-2.ini
sudo systemctl stop vidireports || true
kill_vidi_processes
sudo systemctl start vidireports || true
