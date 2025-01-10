#!/bin/bash

# Update package lists
sudo chmod 666 /dev/video*

# Install required packages
sudo apt-get install -y sshpass ansible git

# Create a directory for the GitHub repo (optional)
mkdir -p ~/git_repo

# Clone the public GitHub repo (replace with your repo URL)
git clone https://github.com/chrismcfee/camerapub.git

# Create target directory if it doesn't exist
#mkdir -p ~/target_directory

# Copy 3 files from repo to target directory
cp ~/camerapub/camera-setup.sh camera_binder/
cp ~/camerapub/camera_binder.service camera_binder/
cp ~/camerapub/camera_binder.py camera_binder/

# Change directory to repo directory
cd ~/camerapub

# Run ansible playbook
ansible-playbook nomesh.yaml -i invetory-players-version-2.ini

# Go to home directory
cd ~

# Run script (replace with your script name)
chmod +x /home/zignage/wf_vidireports-7.7.8.4-bundle_x86_64_network_1440.sh

./wf_vidireports-7.7.8.4-bundle_x86_64_network_1440.sh

cat /home/zignage/.vidireports/VidiReports.log | grep box_id
