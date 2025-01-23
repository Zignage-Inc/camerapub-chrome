#!/bin/bash
# Define the function to kill processes with 'vidi' or 'vidireports' in their names
VIDIREPORTS_PATH="/home/zignage/.vidireports/7.7.8.4/./vidireports"
LOG_PATH="/home/zignage/.vidireports/VidiReports.log"
CONFIG_PATH="/home/zignage/.vidireports/config/"
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
sudo systemctl daemon-reload
kill_vidi_processes || true
sudo systemctl stop vidireports
kill_vidi_processes || true
kill_vidi_processes || true
sudo systemctl start vidireports
echo "Service updated and restarted successfully"
echo "part 3 complete"
