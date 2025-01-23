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
Type=forking
ExecStart=/home/zignage/.vidireports/./vidireports -d -l /home/zignage/.vidireports/VidiReports.log -c /home/zignage/.vidireports/config/
ExecStop=/bin/kill -TERM $MAINPID
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=120
TimeoutStartSec=60
Restart=on-failure
RestartSec=30
User=zignage
Group=video

[Install]
WantedBy=multi-user.target
EOL'

# Reload systemd daemon and restart service
sudo systemctl stop vidireports
sudo systemctl daemon-reload
sudo systemctl start vidireports
