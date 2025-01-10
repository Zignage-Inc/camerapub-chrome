#!/bin/bash

sudo chown -R zignage:zignage /home/zignage
sudo chmod 666 /dev/video*

# Install required packages
sudo apt-get install -y sshpass ansible git

# Create necessary directories
mkdir -p /home/zignage/camera_binder
mkdir -p /home/zignage/camerapub

# Remove existing repo if it exists
rm -rf /home/zignage/camerapub

# Clone the public GitHub repo
git clone https://github.com/chrismcfee/camerapub.git

# Download the yaml file
#wget https://raw.githubusercontent.com/Zignage-Inc/camerapub2/refs/heads/main_branch/nomesh.yaml

# Copy files to camera_binder directory
cp /home/zignage/camerapub/camera-setup.sh /home/zignage/camera_binder/
cp /home/zignage/camerapub/camera_binder.service /home/zignage/camera_binder/
cp /home/zignage/camerapub/camera_binder.py /home/zignage/camera_binder/

# Copy yaml file to camerapub directory
#cp /home/zignage/nomesh.yaml /home/zignage/camerapub/

# Change directory and run ansible playbook
cd /home/zignage/camerapub
ansible-playbook nomesh.yaml -i invetory-players-version-2.ini

# Return to home directory
cd /home/zignage

# Check if the bundle file exists before trying to execute it
if [ -f "wf_vidireports-7.7.8.4-bundle_x86_64_network_1440.sh" ]; then
    chmod +x wf_vidireports-7.7.8.4-bundle_x86_64_network_1440.sh
    ./wf_vidireports-7.7.8.4-bundle_x86_64_network_1440.sh
else
    echo "Bundle file not found"
fi

# Check for VidiReports.log
if [ -f "/home/zignage/.vidireports/VidiReports.log" ]; then
    cat /home/zignage/.vidireports/VidiReports.log | grep box_id
else
    echo "VidiReports.log not found"
fi
