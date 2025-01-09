#!/bin/bash
# /usr/local/bin/camera-setup.sh

# Ensure video devices have proper permissions
chmod 666 /dev/video* 2>/dev/null || true

# Ensure camera symlink directory exists with proper permissions
mkdir -p /dev
chmod 755 /dev
