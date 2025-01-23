#!/bin/bash
# Define the function to kill processes with 'vidi' or 'vidireports' in their names
VIDIREPORTS_PATH="/home/zignage/.vidireports/7.7.8.4/./vidireports"
LOG_PATH="/home/zignage/.vidireports/VidiReports.log"
CONFIG_PATH="/home/zignage/.vidireports/config/"
rm /etc/systemd/system/vidireports.service || true
sudo bash -c 'cat > /etc/systemd/system/vidireports.service <<EOL
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
EOL'

# Reload systemd daemon and restart service
sudo systemctl stop vidireports
sudo systemctl daemon-reload
sudo systemctl start vidireports
