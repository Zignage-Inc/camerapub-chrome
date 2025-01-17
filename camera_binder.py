#!/usr/bin/env python3

import subprocess
import logging
import os
import sys
import hashlib
import glob
import re
import grp
import json

# Configure logging
LOGFILE = '/var/log/camera_binding.log'
logging.basicConfig(filename=LOGFILE, level=logging.INFO,
                    format='%(asctime)s %(levelname)s: %(message)s')

CAMERA_USER = 'zignage'  # Replace with the actual user or service account
SYMLINK_PATH = '/dev/camera_locked'

# Add to the top of your script
def check_root():
    if os.geteuid() != 0:
        logging.error("This script must be run as root")
        sys.exit(1)

def is_4k_camera(bus_num, device_num):
    """Check if the camera is a 4K model based on manufacturer and product names"""
    try:
        # Get detailed device information using lsusb
        # Use the correct format for vendor:product ID from the device info
        lsusb_output = subprocess.check_output(['lsusb'], text=True)
        for line in lsusb_output.split('\n'):
            if f"Bus {bus_num} Device {device_num}" in line:
                # Extract vendor and product ID
                match = re.search(r'ID (\w+:\w+)', line)
                if match:
                    vendor_product = match.group(1)
                    detailed_output = subprocess.check_output(
                        ['lsusb', '-v', '-d', vendor_product],
                        stderr=subprocess.PIPE,
                        text=True
                    )

                    # Check both manufacturer and product names
                    is_4k = False
                    for detail_line in detailed_output.split('\n'):
                        if 'iManufacturer' in detail_line and '4K' in detail_line:
                            is_4k = True
                            break
                        if 'iProduct' in detail_line and '4K' in detail_line:
                            is_4k = True
                            break

                    logging.info(f"Camera on Bus {bus_num} Device {device_num} is 4K: {is_4k}")
                    return is_4k

        return False

    except subprocess.CalledProcessError as e:
        logging.error(f"Error checking for 4K camera on Bus {bus_num} Device {device_num}: {e}")
        return False
    except Exception as e:
        logging.error(f"Unexpected error checking for 4K camera: {e}")
        return False


def load_process_config():
    """Load process camera mapping configuration from file"""
    config_path = '/etc/camera_binding/camera_config.json'
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
        logging.info(f"Loaded camera configuration: {config}")
        return config
    except FileNotFoundError:
        logging.warning(f"Configuration file not found at {config_path}, using defaults")
        return {
            'livedooh-player': {
                'expected_uuid_file': '/etc/camera_binding/livedooh_camera_uuid.txt',
                'symlink_path': '/dev/camera_livedooh',
                'allow_4k': True
            },
            'vidireports': {
                'expected_uuid_file': '/etc/camera_binding/vidireports_camera_uuid.txt',
                'symlink_path': '/dev/camera_vidireports',
                'allow_4k': False
            }
        }
    except Exception as e:
        logging.error(f"Error loading configuration: {e}")
        sys.exit(1)
    except Exception as e:
        logging.error(f"Error loading configuration: {e}")
        sys.exit(1)

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

def find_highest_resolution_device(camera_devices, process_name=None):
    """
    Find the best camera device, considering process requirements
    """
    best_camera = None

    # Get process configuration
    process_config = PROCESS_CAMERA_MAPPING.get(process_name, {})
    allow_4k = process_config.get('allow_4k', True)

    logging.info(f"Finding camera for process {process_name}, allow_4k: {allow_4k}")

    # First, look for appropriate cameras
    for bus_num, device_num, description in camera_devices:
        logging.info(f"Checking camera: Bus {bus_num} Device {device_num}")
        is_4k = is_4k_camera(bus_num, device_num)

        # Skip 4K cameras if not allowed
        if not allow_4k and is_4k:
            logging.info(f"Skipping 4K camera for process {process_name}")
            continue

        devnode = find_device_node(bus_num, device_num)
        if devnode:
            logging.info(f"Found suitable camera at {devnode} (Bus {bus_num}, Device {device_num})")
            return (devnode, bus_num, device_num)

    logging.error(f"No suitable camera found for process {process_name}")
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
    try:
        lsusb_output = subprocess.check_output(['lsusb'], text=True)
    except subprocess.CalledProcessError as e:
        logging.error(f"Error executing lsusb: {e}")
        sys.exit(1)

    camera_devices = []
    for line in lsusb_output.strip().split('\n'):
        if 'Camera' in line or 'camera' in line:
            parts = line.split()
            if len(parts) >= 6:
                # Extract bus and device numbers correctly
                bus_num = parts[1]
                device_num = parts[3].rstrip(':')

                # Format bus and device numbers with leading zeros
                bus_num = bus_num.zfill(3)  # Ensure 3 digits
                device_num = device_num.zfill(3)  # Ensure 3 digits

                logging.debug(f"Found camera device: Bus {bus_num}, Device {device_num}")
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

def find_device_node(bus_num, device_num):
    """Find the video device node for a USB device"""
    try:
        # Construct the correct USB device path
        usb_dev_path = f"/dev/bus/usb/{bus_num}/{device_num}"

        if not os.path.exists(usb_dev_path):
            logging.error(f"USB device path does not exist: {usb_dev_path}")
            return None

        # Get the sysfs path
        usb_sysfs_path = subprocess.check_output(
            ['udevadm', 'info', '-q', 'path', '-n', usb_dev_path],
            stderr=subprocess.PIPE,
            text=True
        ).strip()

        # Look for corresponding video device, preferring higher numbered devices
        video_devices = sorted(glob.glob('/dev/video*'), reverse=True)
        for video_dev in video_devices:
            try:
                video_sysfs_path = subprocess.check_output(
                    ['udevadm', 'info', '-q', 'path', '-n', video_dev],
                    stderr=subprocess.PIPE,
                    text=True
                ).strip()

                if usb_sysfs_path in video_sysfs_path:
                    logging.info(f"Found matching video device: {video_dev}")
                    return video_dev
            except subprocess.CalledProcessError:
                continue

        return None

    except Exception as e:
        logging.error(f"Error in find_device_node: {e}")
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

# Add these to your existing camera_binder.py

# Load process configuration from JSON file
PROCESS_CAMERA_MAPPING = load_process_config()
def debug_camera_info():
    """Print debug information about available cameras"""
    try:
        # List all video devices
        video_devices = glob.glob('/dev/video*')
        logging.info("Available video devices:")
        for dev in video_devices:
            logging.info(f"  {dev}")

        # Run lsusb with verbose output for cameras
        logging.info("USB camera details:")
        lsusb_output = subprocess.check_output(['lsusb', '-v'], stderr=subprocess.PIPE, text=True)
        for line in lsusb_output.split('\n'):
            if 'Camera' in line or 'camera' in line:
                logging.info(f"  {line}")

    except Exception as e:
        logging.error(f"Error in debug_camera_info: {e}")
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

def lock_all_cameras():
    """Set baseline permissions for all video devices"""
    try:
        video_devices = glob.glob('/dev/video*')
        for device in video_devices:
            # Set read/write for owner, nothing for others
            os.chmod(device, 0o660)  # rw-rw----
            # Set ownership to root:video
            os.chown(device, 0, 44)  # 44 is typically the video group ID
            logging.info(f"Set baseline permissions for {device}")
    except Exception as e:
        logging.error(f"Error setting baseline camera permissions: {e}")

def setup_camera_groups(devnode):
    """Setup proper group permissions for the camera"""
    try:
        # Add the device to the video group
        video_gid = grp.getgrnam('video').gr_gid
        os.chown(devnode, 0, video_gid)
        # Set permissions to allow group access
        os.chmod(devnode, 0o660)  # rw-rw----
        logging.info(f"Set group permissions for {devnode}")
    except Exception as e:
        logging.error(f"Error setting group permissions: {e}")

def setup_camera_permissions(devnode, process_name):
    """Set up specific permissions for a camera device"""
    try:
        # Make the device accessible to the video group
        video_gid = grp.getgrnam('video').gr_gid
        os.chown(devnode, 0, video_gid)
        os.chmod(devnode, 0o660)  # rw-rw----
        logging.info(f"Set permissions for {devnode} for process {process_name}")
    except Exception as e:
        logging.error(f"Error setting camera permissions: {e}")


def main():
    check_root()
    debug_camera_info()

    camera_devices = get_usb_camera_devices()
    if not camera_devices:
        logging.error("No camera devices found.")
        sys.exit(1)

    # Log all found cameras
    logging.info("Found cameras:")
    for bus_num, device_num, description in camera_devices:
        logging.info(f"  {description} (Bus {bus_num}, Device {device_num})")

    # Set baseline permissions for all cameras
    lock_all_cameras()

# In the main function, modify this section:
    try:
    # Process binding for each configured process
        for process_name, config in PROCESS_CAMERA_MAPPING.items():
            logging.info(f"Processing camera binding for {process_name}")
            allow_4k = config.get('allow_4k', False)
            only_4k = process_name == 'livedooh-player'  # Add this line

        # Filter cameras based on 4K permission
            available_cameras = []
            for bus_num, device_num, description in camera_devices:
                is_4k = is_4k_camera(bus_num, device_num)
            # Modified condition to handle livedooh special case
                if only_4k:
                    if is_4k:  # Only allow 4K cameras for livedooh
                        available_cameras.append((bus_num, device_num, description))
                        logging.info(f"4K Camera on Bus {bus_num} Device {device_num} is available for {process_name}")
                else:
                    if not is_4k:  # Only allow non-4K cameras for other processes
                        available_cameras.append((bus_num, device_num, description))
                        logging.info(f"Non-4K Camera on Bus {bus_num} Device {device_num} is available for {process_name}")

            # Try to find a suitable camera
            selected_device_info = None
            for bus_num, device_num, description in available_cameras:
                devnode = find_device_node(bus_num, device_num)
                if devnode:
                    selected_device_info = (devnode, bus_num, device_num)
                    break

            if not selected_device_info:
                logging.error(f"No suitable camera found for {process_name}")
                continue

            devnode, bus_num, device_num = selected_device_info
            logging.info(f"Selected camera device for {process_name}: {devnode}")

            # Setup proper group permissions
            setup_camera_groups(devnode)

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

    except Exception as e:
        logging.error(f"Error in main execution: {e}")
        sys.exit(1)
if __name__ == '__main__':
    main()
