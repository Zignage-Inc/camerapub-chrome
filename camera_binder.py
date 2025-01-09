#!/usr/bin/env python3

import subprocess
import logging
import os
import sys
import hashlib
import glob
import re

# Configure logging
LOGFILE = '/var/log/camera_binding.log'
logging.basicConfig(filename=LOGFILE, level=logging.INFO,
                    format='%(asctime)s %(levelname)s: %(message)s')

EXPECTED_UUID_FILE = '/etc/camera_binding/expected_camera_uuid.txt'
CAMERA_USER = 'zignage'  # Replace with the actual user or service account
SYMLINK_PATH = '/dev/camera_locked'

# Add to the top of your script
def check_root():
    if os.geteuid() != 0:
        logging.error("This script must be run as root")
        sys.exit(1)

# Modify the get_camera_resolution function to handle potential v4l2-ctl issues:
def is_4k_camera(description):
    """Check if the camera is a 4K model based on description"""
    return '4K' in description.upper()

def get_camera_resolution(devnode):
    """
    Enhanced resolution detection with better debugging
    """
    try:
        if not os.path.exists(devnode):
            logging.error(f"Device {devnode} does not exist")
            return []

        # First, try to get detailed device information
        try:
            device_info = subprocess.check_output(['v4l2-ctl', '-d', devnode, '--all'], 
                                                stderr=subprocess.PIPE, text=True)
            logging.debug(f"Device {devnode} info:\n{device_info}")
        except subprocess.CalledProcessError as e:
            logging.warning(f"Could not get device info for {devnode}: {e}")

        # Try to get formats and resolutions
        try:
            format_output = subprocess.check_output([
                'v4l2-ctl', '-d', devnode, '--list-formats-ext'],
                stderr=subprocess.PIPE, text=True)
            logging.debug(f"Format output for {devnode}:\n{format_output}")
        except subprocess.CalledProcessError as e:
            logging.warning(f"Could not get formats for {devnode}: {e}")
            format_output = ""

        resolutions = []

        # Parse the format output for resolutions
        for line in format_output.split('\n'):
            # Look for size information
            size_matches = [
                re.search(r'Size: Discrete (\d+x\d+)', line),
                re.search(r'Size:\s*\w+\s+(\d+)x(\d+)', line),
                re.search(r'\[(\d+)x(\d+)\]', line)
            ]

            for match in size_matches:
                if match:
                    if 'x' in match.group(1):
                        resolution = match.group(1)
                    else:
                        resolution = f"{match.group(1)}x{match.group(2)}"
                    if resolution not in [r[1] for r in resolutions]:
                        resolutions.append(('MJPG', resolution))

        if not resolutions:
            # Fallback: try getting current format
            try:
                current_format = subprocess.check_output([
                    'v4l2-ctl', '-d', devnode, '--get-fmt-video'],
                    stderr=subprocess.PIPE, text=True)
                logging.debug(f"Current format for {devnode}:\n{current_format}")

                # Parse width and height
                width_match = re.search(r'Width/Height\s*:\s*(\d+)/(\d+)', current_format)
                if width_match:
                    resolution = f"{width_match.group(1)}x{width_match.group(2)}"
                    resolutions.append(('MJPG', resolution))
            except subprocess.CalledProcessError as e:
                logging.warning(f"Could not get current format for {devnode}: {e}")

        logging.info(f"Found resolutions for {devnode}: {resolutions}")
        return resolutions

    except Exception as e:
        logging.error(f"Unexpected error getting resolution for {devnode}: {e}")
        return []

def find_highest_resolution_device(camera_devices):
    """
    Find the best camera device, prioritizing 4K cameras
    """
    best_camera = None
    found_4k = False

    # First, look for 4K cameras
    for bus_num, device_num, description in camera_devices:
        if is_4k_camera(description):
            devnode = find_device_node(bus_num, device_num)
            if devnode:
                logging.info(f"Found 4K camera: {description} at {devnode}")
                best_camera = (devnode, bus_num, device_num)
                found_4k = True
                break

    # If no 4K camera found, fall back to other cameras
    if not found_4k and camera_devices:
        for bus_num, device_num, description in camera_devices:
            devnode = find_device_node(bus_num, device_num)
            if devnode:
                logging.info(f"Falling back to camera: {description} at {devnode}")
                best_camera = (devnode, bus_num, device_num)
                break

    if best_camera:
        devnode, bus_num, device_num = best_camera
        logging.info(f"Selected camera device: {devnode}")
        return best_camera

    logging.error("No suitable camera found")
    return None

def pick_highest_resolution(camera_resolutions):
    """
    Select the highest available resolution from a list of resolutions.
    """
    max_resolution = None
    max_width = max_height = 0

    for format, resolution in camera_resolutions:
        width, height = map(int, resolution.split('x'))
        if width * height > max_width * max_height:
            max_width, max_height = width, height
            max_resolution = resolution

    logging.info(f"Selected highest resolution: {max_resolution}")
    return max_resolution

def ensure_directory_exists(path):
    directory = os.path.dirname(path)
    if not os.path.exists(directory):
        os.makedirs(directory, exist_ok=True)

def get_usb_camera_devices():
    # Use 'lsusb' to list USB devices
    try:
        lsusb_output = subprocess.check_output(['lsusb'], text=True)
    except subprocess.CalledProcessError as e:
        logging.error(f"Error executing lsusb: {e}")
        sys.exit(1)

    camera_devices = []
    for line in lsusb_output.strip().split('\n'):
        # Customize the condition below to match your cameras' identification
        if 'Camera' in line or 'camera' in line:
            logging.debug(f"Found camera device: {line}")
            # Parse bus and device numbers
            parts = line.split()
            if len(parts) >= 6:
                bus_num = parts[1]
                device_num = parts[3].rstrip(':')
                camera_devices.append((bus_num, device_num, line))
    return camera_devices

def generate_device_uuid(bus_num, device_num):
    # Use udevadm to get device properties
    dev_path = f"/dev/bus/usb/{bus_num}/{device_num}"
    try:
        udevadm_output = subprocess.check_output(['udevadm', 'info', '--query=property', '--name', dev_path], text=True)
        properties = {}
        for line in udevadm_output.strip().split('\n'):
            if '=' in line:
                key, value = line.strip().split('=', 1)
                properties[key] = value
        # Use ID_SERIAL_SHORT or ID_SERIAL as the UUID source
        serial = properties.get('ID_SERIAL_SHORT') or properties.get('ID_SERIAL')
        if serial:
            uuid = hashlib.md5(serial.encode()).hexdigest()
            logging.debug(f"Generated UUID '{uuid}' for device with serial {serial}")
            return uuid, dev_path
        else:
            # Fallback to device path
            dev_path_info = subprocess.check_output(['udevadm', 'info', '--query=path', '--name', dev_path], text=True).strip()
            uuid = hashlib.md5(dev_path_info.encode()).hexdigest()
            logging.debug(f"Generated UUID '{uuid}' for device path {dev_path_info}")
            return uuid, dev_path_info
    except subprocess.CalledProcessError as e:
        logging.error(f"Error executing udevadm for device {dev_path}: {e}")
        return None, None

def load_expected_uuid():
    try:
        with open(EXPECTED_UUID_FILE, 'r') as f:
            expected_uuid = f.readline().strip()
        logging.info(f"Loaded expected UUID: {expected_uuid}")
        return expected_uuid
    except FileNotFoundError:
        logging.warning("Expected UUID file not found.")
        return None
    except Exception as e:
        logging.error(f"Error loading expected UUID: {e}")
        return None

def save_expected_uuid(uuid):
    try:
        ensure_directory_exists(EXPECTED_UUID_FILE)
        with open(EXPECTED_UUID_FILE, 'w') as f:
            f.write(uuid + '\n')
        logging.info(f"Saved expected UUID: {uuid}")
    except Exception as e:
        logging.error(f"Error saving expected UUID: {e}")
        sys.exit(1)

def find_device_node(bus_num, device_num):
    # The path to the USB device
    usb_dev_path = f"/dev/bus/usb/{bus_num}/{device_num}"
    # Get the sysfs path of the USB device
    try:
        usb_sysfs_path = subprocess.check_output(['udevadm', 'info', '-q', 'path', '-n', usb_dev_path], text=True).strip()
        logging.debug(f"USB device sysfs path: {usb_sysfs_path}")
    except subprocess.CalledProcessError as e:
        logging.error(f"Error getting sysfs path for USB device {usb_dev_path}: {e}")
        return None

    # Now, iterate over all /dev/video* devices and check if their parent matches
    for video_dev in glob.glob('/dev/video*'):
        try:
            # Get sysfs path of the video device
            video_sysfs_path = subprocess.check_output(['udevadm', 'info', '-q', 'path', '-n', video_dev], text=True).strip()
            logging.debug(f"Video device {video_dev} sysfs path: {video_sysfs_path}")
            # Log the comparison
            logging.debug(f"Checking if '{usb_sysfs_path}' is in '{video_sysfs_path}'")
            # Check if the video device sysfs path contains the USB device sysfs path
            if usb_sysfs_path in video_sysfs_path:
                logging.info(f"Found video device node: {video_dev}")
                return video_dev
        except subprocess.CalledProcessError as e:
            logging.error(f"Error getting sysfs path for video device {video_dev}: {e}")
            continue
    logging.warning(f"No /dev/video* device found associated with USB device {usb_dev_path}")
    return None

def adjust_permissions(devnode):
    try:
        os.chown(devnode, get_uid(CAMERA_USER), get_gid(CAMERA_USER))
        os.chmod(devnode, 0o600)
        logging.info(f"Set ownership and permissions for {devnode}")
    except Exception as e:
        logging.error(f"Error setting permissions for {devnode}: {e}")

def create_symlink(devnode):
    try:
        if os.path.islink(SYMLINK_PATH):
            os.remove(SYMLINK_PATH)
        os.symlink(devnode, SYMLINK_PATH)
        os.chown(SYMLINK_PATH, get_uid(CAMERA_USER), get_gid(CAMERA_USER))
        logging.info(f"Created symlink {SYMLINK_PATH} -> {devnode}")
    except Exception as e:
        logging.error(f"Error creating symlink {SYMLINK_PATH}: {e}")

def get_uid(username):
    import pwd
    return pwd.getpwnam(username).pw_uid

def get_gid(username):
    import pwd
    return pwd.getpwnam(username).pw_gid

# Add these to your existing camera_binder.py

# Add this near the top of your file, after the existing constants
# In your camera_binder.py, modify the PROCESS_CAMERA_MAPPING

PROCESS_CAMERA_MAPPING = {
    'livedooh-player': {
        'expected_uuid_file': '/etc/camera_binding/livedooh_camera_uuid.txt',
        'symlink_path': '/dev/camera_livedooh'
    }
}

# Make sure this symlink is created when the camera is bound
def bind_camera_to_process(process_name, devnode):
    if process_name in PROCESS_CAMERA_MAPPING:
        config = PROCESS_CAMERA_MAPPING[process_name]
        symlink_path = config['symlink_path']
        try:
            if os.path.exists(symlink_path) or os.path.islink(symlink_path):
                os.remove(symlink_path)
            os.symlink(devnode, symlink_path)
            os.chown(symlink_path, get_uid(CAMERA_USER), get_gid(CAMERA_USER))
            logging.info(f"Created process-specific symlink {symlink_path} -> {devnode}")
        except Exception as e:
            logging.error(f"Error creating process-specific symlink {symlink_path}: {e}")
# Modify your main() function to handle multiple processes



# Modify the main function to include root check and better error handling:
def main():
    check_root()  # Ensure running as root

    camera_devices = get_usb_camera_devices()
    if not camera_devices:
        logging.error("No camera devices found.")
        sys.exit(1)
# Log all found cameras
    logging.info("Found cameras:")
    for bus_num, device_num, description in camera_devices:
        logging.info(f"  {description} (Bus {bus_num}, Device {device_num})")

    # Select the best camera (preferring 4K)
    selected_device_info = find_highest_resolution_device(camera_devices)

    if not selected_device_info:
        logging.error("No suitable camera found")
        sys.exit(1)

    devnode, bus_num, device_num = selected_device_info
    logging.info(f"Selected camera device: {devnode}")

    # Process binding for each configured process
    for process_name, config in PROCESS_CAMERA_MAPPING.items():
        expected_uuid_file = config['expected_uuid_file']
        symlink_path = config['symlink_path']

        # Ensure directory exists for UUID file and symlink
        ensure_directory_exists(expected_uuid_file)
        ensure_directory_exists(symlink_path)

        # Generate or load UUID
        uuid, dev_path = generate_device_uuid(bus_num, device_num)
        if not uuid:
            logging.error(f"Failed to generate UUID for {process_name}")
            continue

        # Save UUID if it doesn't exist
        if not os.path.exists(expected_uuid_file):
            try:
                with open(expected_uuid_file, 'w') as f:
                    f.write(uuid + '\n')
                logging.info(f"Saved UUID for {process_name}: {uuid}")
            except Exception as e:
                logging.error(f"Failed to save UUID: {e}")
                continue

        # Create symlink with proper permissions
        try:
            if os.path.exists(symlink_path) or os.path.islink(symlink_path):
                os.remove(symlink_path)
            os.symlink(devnode, symlink_path)
            os.chown(symlink_path, get_uid(CAMERA_USER), get_gid(CAMERA_USER))
            logging.info(f"Created symlink {symlink_path} -> {devnode}")
        except Exception as e:
            logging.error(f"Failed to create symlink: {e}")
            continue

        # Set device permissions
        try:
            adjust_permissions(devnode)
        except Exception as e:
            logging.error(f"Failed to set permissions: {e}")
if __name__ == '__main__':
    main()
