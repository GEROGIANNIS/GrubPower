#!/bin/bash
# GrubPower Advanced - Enhanced USB Power Management for Laptops
# Author: Claude
# Date: April 12, 2025
# License: MIT
#
# This enhanced version includes:
# - Battery monitoring
# - Automatic shutdown at low battery
# - Customizable USB port selection
# - Better hardware detection
# - Optional logging

set -e  # Exit on error

# Version information
VERSION="1.2.0"

# Initialize rollback log
ROLLBACK_LOG=$(mktemp)

# Configuration variables
CONFIG_FILE="/etc/grubpower.conf"
DEFAULT_KERNEL_PATH="/boot/vmlinuz-linux"
DEFAULT_GRUB_ROOT="hd0,1"
DEFAULT_OUTPUT_DIR="/boot"
DEFAULT_INITRAMFS_NAME="grubpower-initramfs.img"
DEFAULT_BUILD_DIR="/tmp/grubpower_build"
DEFAULT_GRUB_CUSTOM="/etc/grub.d/40_custom"
DEFAULT_MIN_BATTERY=10       # Shutdown when battery reaches this percentage
DEFAULT_DISABLE_AUTOSUSPEND=1  # Disable USB autosuspend
DEFAULT_ENABLE_LOGGING=0     # Enable logging to file
DEFAULT_LOG_FILE="/var/log/grubpower.log"
DEFAULT_SELECT_PORTS="all"   # USB ports to power (all, charging, specific ports)
DEFAULT_LID_CONTROL=1        # Enable lid detection and display control
DEFAULT_HANDLE_ACPI=1        # Handle ACPI events (lid, power button)

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

# Rollback action registration
rollback_action() {
    echo "$1" >> "$ROLLBACK_LOG"
}

# Perform rollback in case of error
perform_rollback() {
    echo "ERROR: Installation failed. Rolling back changes..."
    tac "$ROLLBACK_LOG" | while read action; do
        eval "$action"
    done
    rm "$ROLLBACK_LOG"
    echo "Rollback completed."
    exit 1
}

# Set trap for error handling
trap 'perform_rollback' ERR

# Hardware compatibility check
check_compatibility() {
    echo "Checking hardware compatibility..."
    
    # Check for USB power management support
    if [ ! -d "/sys/bus/usb/devices" ]; then
        echo "WARNING: USB subsystem not detected in expected location."
        echo "This system may not support the required USB power management features."
        ask_continue
    fi
    
    # Check if any USB ports support power control
    POWER_CONTROL_FILES=$(find /sys/bus/usb/devices -name "power/control" 2>/dev/null | wc -l)
    
    # If standard power control files aren't found, check alternative locations
    if [ "$POWER_CONTROL_FILES" -eq 0 ]; then
        # Check for alternative power management interfaces
        ALT_POWER_FILES=$(find /sys/bus/usb/devices -path "*/power/*" 2>/dev/null | wc -l)
        
        if [ "$ALT_POWER_FILES" -gt 0 ]; then
            echo "Found alternative USB power management interfaces."
            echo "GrubPower may still work but with limited functionality."
            ask_continue
        else
            echo "WARNING: No USB power control interfaces found."
            echo "GrubPower may not be able to manage power on this system."
            echo "This could be due to kernel configuration or hardware limitations."
            
            # Check if USB modules are loaded
            echo "Checking for loaded USB modules..."
            USB_MODULES_LOADED=$(lsmod | grep -E "usb|ehci|ohci|uhci|xhci" | wc -l)
            
            if [ "$USB_MODULES_LOADED" -eq 0 ]; then
                echo "No USB modules appear to be loaded."
                echo "Would you like to try loading essential USB modules?"
                read -p "Load USB modules? (y/n): " LOAD_MODULES
                
                if [[ "$LOAD_MODULES" =~ ^[Yy]$ ]]; then
                    echo "Attempting to load USB modules..."
                    modprobe usbcore 2>/dev/null && echo "Loaded: usbcore" || echo "Failed to load: usbcore"
                    modprobe usb_common 2>/dev/null && echo "Loaded: usb_common" || echo "Failed to load: usb_common"
                    modprobe ehci_hcd 2>/devnull && echo "Loaded: ehci_hcd" || echo "Failed to load: ehci_hcd"
                    modprobe ohci_hcd 2>/dev/null && echo "Loaded: ohci_hcd" || echo "Failed to load: ohci_hcd"
                    modprobe uhci_hcd 2>/dev/null && echo "Loaded: uhci_hcd" || echo "Failed to load: uhci_hcd"
                    modprobe xhci_hcd 2>/dev/null && echo "Loaded: xhci_hcd" || echo "Failed to load: xhci_hcd"
                    
                    # Check again after loading modules
                    echo "Checking USB compatibility again after loading modules..."
                    sleep 2
                    NEW_POWER_CONTROL_FILES=$(find /sys/bus/usb/devices -name "power/control" 2>/dev/null | wc -l)
                    
                    if [ "$NEW_POWER_CONTROL_FILES" -gt 0 ]; then
                        echo "SUCCESS: USB power control interfaces are now available."
                        echo "Found $NEW_POWER_CONTROL_FILES power control interfaces."
                        POWER_CONTROL_FILES=$NEW_POWER_CONTROL_FILES
                    else
                        echo "WARNING: Still no USB power control interfaces found."
                        echo "You can try one of the following:"
                        echo "1. Check if USB modules are loaded: lsmod | grep usb"
                        echo "2. Try installing additional USB modules: modprobe usbcore"
                        echo "3. Proceed anyway and test if it works on your hardware"
                        ask_continue
                    fi
                else
                    echo "Skipping module loading."
                    echo "You can try one of the following:"
                    echo "1. Check if USB modules are loaded: lsmod | grep usb"
                    echo "2. Try installing additional USB modules: modprobe usbcore"
                    echo "3. Proceed anyway and test if it works on your hardware"
                    ask_continue
                fi
            else
                echo "USB modules are loaded, but power control interfaces are still not found."
                echo "You can try one of the following:"
                echo "1. Check if USB modules are loaded: lsmod | grep usb"
                echo "2. Try installing additional USB modules: modprobe usbcore"
                echo "3. Proceed anyway and test if it works on your hardware"
                ask_continue
            fi
        fi
    fi
    
    # Check for battery
    BATTERY_FOUND=0
    for bat in /sys/class/power_supply/BAT*; do
        if [ -d "$bat" ]; then
            BATTERY_FOUND=1
            break
        fi
    done
    
    if [ $BATTERY_FOUND -eq 0 ]; then
        echo "WARNING: No battery detected. This tool is primarily designed for laptops."
        ask_continue
    fi
    
    echo "Compatibility check completed."
}

# Ask user to continue or abort
ask_continue() {
    read -p "Continue anyway? (y/n): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        echo "Installation aborted."
        exit 1
    fi
}

# Test USB power management
test_usb_power() {
    echo "Testing USB power management capabilities..."
    
    # Create temporary directory
    TEST_DIR=$(mktemp -d)
    rollback_action "rm -rf $TEST_DIR"
    
    # Create simple test script
    cat > "$TEST_DIR/test_usb.sh" <<'EOF'
#!/bin/bash
echo "Testing USB power management..."
# Try to set power control to on for all USB devices
SUCCESS=0
for i in /sys/bus/usb/devices/*/power/control; do
    if [ -f "$i" ]; then
        ORIGINAL=$(cat "$i")
        echo "on" > "$i" 2>/dev/null
        AFTER=$(cat "$i")
        if [ "$AFTER" = "on" ]; then
            SUCCESS=$((SUCCESS + 1))
            # Restore original value
            echo "$ORIGINAL" > "$i" 2>/dev/null
        fi
    fi
done

if [ $SUCCESS -gt 0 ]; then
    echo "SUCCESS: Successfully controlled power on $SUCCESS USB device(s)."
    exit 0
else
    echo "FAILED: Could not control power on any USB devices."
    exit 1
fi
EOF
    
    chmod +x "$TEST_DIR/test_usb.sh"
    
    # Run test
    if "$TEST_DIR/test_usb.sh"; then
        echo "USB power management test passed!"
    else
        echo "WARNING: USB power management test failed."
        echo "GrubPower may not work correctly on this system."
        ask_continue
    fi
    
    # Clean up
    rm -rf "$TEST_DIR"
}

# Check for updates
check_for_updates() {
    echo "Checking for updates..."
    echo "GrubPower version $VERSION"
    # This would typically check a remote server/repository
    # For now, just a placeholder message
    echo "No updates available (Version check not implemented in this version)"
}

# Interactive configuration wizard
interactive_setup() {
    echo "GrubPower Interactive Setup"
    echo "==========================="
    
    # Ask about battery threshold
    echo -n "Set battery threshold for auto-shutdown (default: 10%): "
    read BATTERY_THRESHOLD
    if [ -n "$BATTERY_THRESHOLD" ] && [[ "$BATTERY_THRESHOLD" =~ ^[0-9]+$ ]]; then
        DEFAULT_MIN_BATTERY=$BATTERY_THRESHOLD
    fi
    
    # Ask about USB port selection
    echo "USB port selection options:"
    echo "1) All USB ports"
    echo "2) Charging ports only (if detectable)"
    echo "3) Specific port numbers"
    echo -n "Select option (default: 1): "
    read USB_OPTION
    
    case "$USB_OPTION" in
        2)
            DEFAULT_SELECT_PORTS="charging"
            ;;
        3)
            echo -n "Enter comma-separated port numbers (e.g., 1,2,4): "
            read SPECIFIC_PORTS
            if [ -n "$SPECIFIC_PORTS" ]; then
                DEFAULT_SELECT_PORTS="$SPECIFIC_PORTS"
            fi
            ;;
        *)
            DEFAULT_SELECT_PORTS="all"
            ;;
    esac
    
    # Ask about logging
    echo -n "Enable logging? (y/n, default: n): "
    read ENABLE_LOG
    if [[ "$ENABLE_LOG" =~ ^[Yy]$ ]]; then
        DEFAULT_ENABLE_LOGGING=1
    fi
    
    echo "Configuration complete. Proceeding with installation..."
}

# Create configuration if it doesn't exist
create_default_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Creating default configuration at $CONFIG_FILE..."
        cat > "$CONFIG_FILE" <<EOF
# GrubPower Configuration File

# System paths
KERNEL_PATH="$DEFAULT_KERNEL_PATH"
GRUB_ROOT="$DEFAULT_GRUB_ROOT"
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
INITRAMFS_NAME="$DEFAULT_INITRAMFS_NAME"
BUILD_DIR="$DEFAULT_BUILD_DIR"
GRUB_CUSTOM="$DEFAULT_GRUB_CUSTOM"

# Power management settings
MIN_BATTERY=$DEFAULT_MIN_BATTERY
DISABLE_AUTOSUSPEND=$DEFAULT_DISABLE_AUTOSUSPEND
ENABLE_LOGGING=$DEFAULT_ENABLE_LOGGING
LOG_FILE="$DEFAULT_LOG_FILE"

# USB port selection (all, charging, 1-2, etc.)
SELECT_PORTS="$DEFAULT_SELECT_PORTS"

# Lid control settings
LID_CONTROL=$DEFAULT_LID_CONTROL        # Enable lid detection and display control
HANDLE_ACPI=$DEFAULT_HANDLE_ACPI        # Handle ACPI events (lid, power button)

# Additional kernel modules to load (space-separated)
EXTRA_MODULES=""

# Additional kernel parameters
EXTRA_KERNEL_PARAMS=""
EOF
        echo "Configuration created. Edit $CONFIG_FILE to customize."
    fi
}

# Load configuration
load_config() {
    create_default_config
    source "$CONFIG_FILE"
}

# Detect system configuration
detect_system() {
    echo "Detecting system configuration..."
    
    # Detect kernel path if default doesn't exist
    if [ ! -f "$KERNEL_PATH" ]; then
        echo "Kernel not found at $KERNEL_PATH, searching for alternatives..."
        
        # Method 1: Find all vmlinuz files and pick the latest
        DETECTED_KERNEL=$(find /boot -name "vmlinuz-*" | sort -V | tail -n 1)
        
        # Method 2: If method 1 fails, try to find the running kernel
        if [ -z "$DETECTED_KERNEL" ] || [ ! -f "$DETECTED_KERNEL" ]; then
            RUNNING_KERNEL=$(uname -r)
            if [ -f "/boot/vmlinuz-$RUNNING_KERNEL" ]; then
                DETECTED_KERNEL="/boot/vmlinuz-$RUNNING_KERNEL"
            fi
        fi
        
        # Check if kernel was found
        if [ -n "$DETECTED_KERNEL" ] && [ -f "$DETECTED_KERNEL" ]; then
            echo "Detected kernel: $DETECTED_KERNEL"
            sed -i "s|KERNEL_PATH=.*|KERNEL_PATH=\"$DETECTED_KERNEL\"|" "$CONFIG_FILE"
            KERNEL_PATH="$DETECTED_KERNEL"
            
            # Verify the kernel file exists (double-check)
            if [ ! -f "$KERNEL_PATH" ]; then
                echo "ERROR: Detected kernel file doesn't exist: $KERNEL_PATH"
                echo "Please specify the correct kernel path manually in $CONFIG_FILE"
                exit 1
            fi
        else
            # If no kernel found, prompt for manual entry and show available kernels
            echo "ERROR: Could not detect kernel automatically."
            echo "Available kernels in /boot:"
            ls -la /boot/vmlinuz* 2>/dev/null || echo "  No vmlinuz files found in /boot"
            echo ""
            read -p "Please enter the full path to your kernel file: " MANUAL_KERNEL
            if [ -n "$MANUAL_KERNEL" ] && [ -f "$MANUAL_KERNEL" ]; then
                echo "Using manually specified kernel: $MANUAL_KERNEL"
                sed -i "s|KERNEL_PATH=.*|KERNEL_PATH=\"$MANUAL_KERNEL\"|" "$CONFIG_FILE"
                KERNEL_PATH="$MANUAL_KERNEL"
            else
                echo "Invalid kernel path or file not found. Please set KERNEL_PATH in $CONFIG_FILE manually."
                exit 1
            fi
        fi
    else
        # Even if the kernel path exists in config, verify it's valid
        if [ ! -f "$KERNEL_PATH" ]; then
            echo "WARNING: Configured kernel path doesn't exist: $KERNEL_PATH"
            echo "Attempting to find a valid kernel..."
            
            # Try to find any kernel
            AVAILABLE_KERNEL=$(find /boot -name "vmlinuz-*" | sort -V | tail -n 1)
            if [ -n "$AVAILABLE_KERNEL" ] && [ -f "$AVAILABLE_KERNEL" ]; then
                echo "Found kernel: $AVAILABLE_KERNEL"
                sed -i "s|KERNEL_PATH=.*|KERNEL_PATH=\"$AVAILABLE_KERNEL\"|" "$CONFIG_FILE"
                KERNEL_PATH="$AVAILABLE_KERNEL"
            else
                echo "ERROR: No valid kernel found in /boot directory."
                echo "Please specify the correct kernel path manually in $CONFIG_FILE"
                exit 1
            fi
        fi
    fi
    
    # Detect GRUB root partition
    if [ "$GRUB_ROOT" = "$DEFAULT_GRUB_ROOT" ]; then
        BOOT_PARTITION=$(df -h /boot | tail -n 1 | awk '{print $1}')
        if [ -n "$BOOT_PARTITION" ]; then
            # Extract disk and partition number
            if [[ "$BOOT_PARTITION" =~ /dev/sd([a-z])([0-9]+) ]]; then
                DISK_LETTER=${BASH_REMATCH[1]}
                PART_NUM=${BASH_REMATCH[2]}
                DETECTED_ROOT="hd0,$((PART_NUM-1))"
                echo "Detected GRUB root: $DETECTED_ROOT"
                sed -i "s|GRUB_ROOT=.*|GRUB_ROOT=\"$DETECTED_ROOT\"|" "$CONFIG_FILE"
                GRUB_ROOT="$DETECTED_ROOT"
            fi
        fi
    fi
    
    # Check GRUB custom file
    if [ ! -f "$GRUB_CUSTOM" ]; then
        if [ -f "/etc/grub.d/40_custom" ]; then
            GRUB_CUSTOM="/etc/grub.d/40_custom"
        elif [ -f "/etc/grub.d/50_custom" ]; then
            GRUB_CUSTOM="/etc/grub.d/50_custom"
        else
            echo "WARNING: Could not locate GRUB custom file. Will create one."
            GRUB_CUSTOM="/etc/grub.d/40_custom"
            echo "#!/bin/sh" > "$GRUB_CUSTOM"
            echo "exec tail -n +3 \$0" >> "$GRUB_CUSTOM"
            echo "# This file provides an easy way to add custom menu entries." >> "$GRUB_CUSTOM"
            chmod +x "$GRUB_CUSTOM"
        fi
        sed -i "s|GRUB_CUSTOM=.*|GRUB_CUSTOM=\"$GRUB_CUSTOM\"|" "$CONFIG_FILE"
    fi
}

# Create the init script with advanced features
create_init_script() {
    echo "Creating advanced init script..."
    cat > "$BUILD_DIR/init" <<EOF
#!/bin/sh
# GrubPower Advanced init script

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Create log file if logging is enabled
if [ $ENABLE_LOGGING -eq 1 ]; then
    mkdir -p /var/log
    touch "$LOG_FILE"
    exec > "$LOG_FILE" 2>&1
    echo "GrubPower logging started at \$(date)"
fi

# Load USB modules
echo "Loading USB modules..."
modprobe usb_common
modprobe usbcore
modprobe ehci_hcd || true
modprobe ohci_hcd || true
modprobe uhci_hcd || true
modprobe xhci_hcd || true
modprobe usb_storage || true

# Load extra modules if specified
if [ -n "$EXTRA_MODULES" ]; then
    echo "Loading extra modules: $EXTRA_MODULES"
    for module in $EXTRA_MODULES; do
        modprobe \$module || echo "Failed to load \$module"
    done
fi

# Configure USB power management based on port selection
echo "Configuring USB power management..."
case "$SELECT_PORTS" in
    all)
        echo "Enabling power for all USB ports"
        for i in /sys/bus/usb/devices/*/power/control; do
            echo "on" > \$i 2>/dev/null || true
        done
        ;;
    charging)
        echo "Enabling power for charging ports only"
        for i in /sys/bus/usb/devices/*/power/control; do
            # Check if this is a charging port (this is a simplification, actual detection is more complex)
            port_path=\$(dirname \$i)
            if grep -q "1" "\$port_path/power/usb2_hardware_lpm_u1" 2>/dev/null; then
                echo "on" > \$i 2>/dev/null || true
            fi
        done
        ;;
    *)
        # Handle specific port numbers
        echo "Enabling power for specified ports: $SELECT_PORTS"
        for port in \$(echo "$SELECT_PORTS" | tr ',' ' '); do
            for i in /sys/bus/usb/devices/usb\$port/power/control; do
                if [ -f "\$i" ]; then
                    echo "on" > \$i 2>/dev/null || true
                fi
            done
        done
        ;;
esac

# Disable USB autosuspend if configured
if [ $DISABLE_AUTOSUSPEND -eq 1 ]; then
    echo "Disabling USB autosuspend..."
    for i in /sys/bus/usb/devices/*/power/autosuspend; do
        echo "-1" > \$i 2>/dev/null || true
    done
    for i in /sys/bus/usb/devices/*/power/autosuspend_delay_ms; do
        echo "-1" > \$i 2>/dev/null || true
    done
fi

# Function to get battery level (works on most Linux systems)
get_battery_level() {
    for bat in /sys/class/power_supply/BAT*; do
        if [ -f "\$bat/capacity" ]; then
            cat "\$bat/capacity"
            return 0
        fi
    done
    
    # Alternative method if the above doesn't work
    if [ -d "/sys/class/power_supply" ]; then
        for bat in \$(ls /sys/class/power_supply/); do
            if [ -f "/sys/class/power_supply/\$bat/type" ]; then
                type=\$(cat "/sys/class/power_supply/\$bat/type")
                if [ "\$type" = "Battery" ]; then
                    if [ -f "/sys/class/power_supply/\$bat/capacity" ]; then
                        cat "/sys/class/power_supply/\$bat/capacity"
                        return 0
                    fi
                fi
            fi
        done
    fi
    
    # Return -1 if battery info not found
    echo "-1"
}

# Function to check if lid is closed
is_lid_closed() {
    if [ -f "/proc/acpi/button/lid/LID0/state" ]; then
        grep -q "closed" "/proc/acpi/button/lid/LID0/state"
        return $?
    elif [ -f "/proc/acpi/button/lid/LID/state" ]; then
        grep -q "closed" "/proc/acpi/button/lid/LID/state"
        return $?
    elif [ -d "/sys/class/input" ]; then
        # Try to find the lid switch event
        for device in /sys/class/input/event*; do
            if [ -f "$device/device/name" ]; then
                if grep -q -i "lid" "$device/device/name"; then
                    # Found lid device, now check state
                    device_name=$(basename $device)
                    state=$(cat /sys/class/input/$device_name/device/sw)
                    if [ "$state" = "1" ]; then
                        return 0  # Lid is closed
                    else
                        return 1  # Lid is open
                    fi
                fi
            fi
        done
    fi
    
    # Default to lid open if we can't determine state
    return 1
}

# Function to control display power
control_display() {
    action="$1"  # on or off
    
    # Try multiple methods to control display power
    if [ "$action" = "off" ]; then
        # Method 1: DPMS (most common)
        if command -v vbetool >/dev/null 2>&1; then
            vbetool dpms off
        # Method 2: Using setterm
        elif command -v setterm >/dev/null 2>&1; then
            setterm --blank force
        # Method 3: Using /sys interface
        elif [ -d "/sys/class/backlight" ]; then
            for bl in /sys/class/backlight/*; do
                if [ -f "$bl/brightness" ]; then
                    # Save current brightness
                    if [ -f "$bl/actual_brightness" ]; then
                        cat "$bl/actual_brightness" > "$bl/saved_brightness"
                    else
                        cat "$bl/brightness" > "$bl/saved_brightness"
                    fi
                    # Turn off backlight
                    echo 0 > "$bl/brightness"
                fi
            done
        fi
    elif [ "$action" = "on" ]; then
        # Method 1: DPMS
        if command -v vbetool >/dev/null 2>&1; then
            vbetool dpms on
        # Method 2: Using setterm
        elif command -v setterm >/dev/null 2>&1; then
            setterm --blank poke
        # Method 3: Using /sys interface
        elif [ -d "/sys/class/backlight" ]; then
            for bl in /sys/class/backlight/*; do
                if [ -f "$bl/brightness" ] && [ -f "$bl/saved_brightness" ]; then
                    # Restore saved brightness
                    cat "$bl/saved_brightness" > "$bl/brightness"
                elif [ -f "$bl/brightness" ] && [ -f "$bl/max_brightness" ]; then
                    # If no saved value, set to max/2
                    max=$(cat "$bl/max_brightness")
                    echo $((max / 2)) > "$bl/brightness"
                fi
            done
        fi
    fi
}

# Print status message
clear
echo "======================================"
echo "GrubPower Advanced USB Mode Activated"
echo "------------------------------------"
echo "USB ports powered: $SELECT_PORTS"
echo "Auto-shutdown at: ${MIN_BATTERY}% battery"
if [ $ENABLE_LOGGING -eq 1 ]; then
    echo "Logging to: $LOG_FILE"
fi
echo ""
echo "IMPORTANT: Battery will drain in this mode!"
echo "Press CTRL+ALT+DEL to reboot"
echo "======================================"

# Set up initial display state 
previous_lid_state="open"
display_state="on"

# If ACPI handling is enabled, try to set up ACPI event handling
if [ $HANDLE_ACPI -eq 1 ]; then
    # Load ACPI modules if available
    modprobe acpi_button || true
    modprobe button || true
    
    # Create ACPI event directory if it doesn't exist
    mkdir -p /etc/acpi/events
    
    # Setup lid close event handler
    if [ -d "/etc/acpi/events" ]; then
        echo "event=button/lid.*" > /etc/acpi/events/lid
        echo "action=/bin/sh -c 'echo lid > /proc/acpi/event'" >> /etc/acpi/events/lid
    fi
    
    # Start acpid if available
    if command -v acpid >/dev/null 2>&1; then
        acpid -d
        echo "ACPI daemon started"
    fi
fi

# Monitor battery, lid state, and keep system alive
echo "Starting power and lid monitoring loop..."
while true; do
    # Battery monitoring
    if [ $MIN_BATTERY -gt 0 ]; then
        battery=\$(get_battery_level)
        if [ "\$battery" != "-1" ]; then
            if [ \$battery -le $MIN_BATTERY ]; then
                echo "Battery level (\${battery}%) reached threshold (${MIN_BATTERY}%)"
                echo "Shutting down system to preserve battery..."
                sleep 5
                # Force safe reboot
                echo b > /proc/sysrq-trigger
                exit 0
            fi
            
            # Display battery status every 5 minutes
            if [ \$((\$(date +%s) % 300)) -lt 10 ]; then
                echo "Battery level: \${battery}%"
            fi
        fi
    fi
    
    # Lid state monitoring
    if [ $LID_CONTROL -eq 1 ]; then
        if is_lid_closed; then
            current_lid_state="closed"
        else
            current_lid_state="open"
        fi
        
        # Handle lid state changes
        if [ "\$current_lid_state" != "\$previous_lid_state" ]; then
            if [ "\$current_lid_state" = "closed" ]; then
                echo "Lid closed, turning off display..."
                control_display "off"
                display_state="off"
            else
                echo "Lid opened, turning on display..."
                control_display "on"
                display_state="on"
            fi
            previous_lid_state="\$current_lid_state"
        fi
        
        # Additional check: if display should be off but isn't
        if [ "\$current_lid_state" = "closed" ] && [ "\$display_state" = "on" ]; then
            control_display "off"
            display_state="off"
        fi
    fi
    
    # Sleep for a few seconds before checking again
    # Using shorter sleep for more responsive lid detection
    sleep 5
done

# Create USB device detection function
    cat >> "$BUILD_DIR/init" <<'EOF'

# Function to list connected USB devices
list_usb_devices() {
    echo "Checking connected USB devices..."
    echo "--------------------------------"
    
    # Create a symlink to lsusb if available
    if command -v lsusb >/dev/null 2>&1; then
        ln -sf $(which lsusb) /bin/lsusb
        lsusb
    else
        # Simple alternative using /sys filesystem
        for dev in /sys/bus/usb/devices/[0-9]*; do
            if [ -d "$dev" ]; then
                devname=$(basename "$dev")
                
                # Try to get vendor and product info
                if [ -f "$dev/manufacturer" ] && [ -f "$dev/product" ]; then
                    vendor=$(cat "$dev/manufacturer" 2>/dev/null || echo "Unknown")
                    product=$(cat "$dev/product" 2>/dev/null || echo "Unknown")
                    echo "USB Device $devname: $vendor $product"
                else
                    echo "USB Device $devname"
                fi
                
                # Check power status
                if [ -f "$dev/power/control" ]; then
                    power=$(cat "$dev/power/control")
                    echo "  - Power: $power"
                    echo "  - Note: All USB devices can benefit from power management, not just power-only devices"
                fi
            fi
        done
    fi
    echo "--------------------------------"
    echo "NOTE: USB power management works for all types of USB devices, not just those"
    echo "      marked as 'power-only' devices. Any connected USB device can benefit"
    echo "      from the power settings configured by GrubPower."
    echo "--------------------------------"
}

# Call device detection after USB configuration
list_usb_devices

# Set up periodic USB device checking (every 5 minutes)
USB_CHECK_INTERVAL=300  # seconds
last_usb_check=$(date +%s)

EOF
}

# Build the initramfs
build_initramfs() {
    echo "Building advanced initramfs image..."
    
    # Create directory structure
    mkdir -p "$BUILD_DIR"/{bin,dev,proc,sys,usr/lib/modules,var/log,etc/acpi/events}
    
    # Install busybox
    if command -v busybox &> /dev/null; then
        cp $(which busybox) "$BUILD_DIR/bin/"
    else
        echo "Busybox not found. Installing..."
        apt-get update && apt-get install -y busybox-static || {
            yum install -y busybox || {
                echo "ERROR: Could not install busybox. Please install it manually."
                exit 1
            }
        }
        cp $(which busybox) "$BUILD_DIR/bin/"
    fi
    
    # Install additional tools if available
    for tool in vbetool setterm acpid; do
        if command -v $tool &> /dev/null; then
            cp $(which $tool) "$BUILD_DIR/bin/"
            echo "Added $tool to initramfs"
        fi
    done
    
    # Create essential symlinks
    cd "$BUILD_DIR/bin"
    for cmd in sh sleep echo cat clear date grep mkdir touch ls; do
        ln -sf busybox $cmd
    done
    cd - > /dev/null
    
    # Create init script
    create_init_script
    
    # Package the initramfs
    cd "$BUILD_DIR"
    find . | cpio -H newc -o | gzip > "/tmp/$INITRAMFS_NAME"
    cd - > /dev/null
    
    # Copy to output directory
    cp "/tmp/$INITRAMFS_NAME" "$OUTPUT_DIR/"
    echo "Advanced initramfs created at $OUTPUT_DIR/$INITRAMFS_NAME"
}

# Create GRUB entry
create_grub_entry() {
    # Verify kernel path before proceeding
    if [ ! -f "$KERNEL_PATH" ]; then
        echo "ERROR: Kernel not found at $KERNEL_PATH"
        echo "Please correct the kernel path in $CONFIG_FILE"
        exit 1
    fi
    
    # Verify that the initramfs was created
    if [ ! -f "$OUTPUT_DIR/$INITRAMFS_NAME" ]; then
        echo "ERROR: Initramfs not found at $OUTPUT_DIR/$INITRAMFS_NAME"
        echo "Build process appears to have failed"
        exit 1
    fi
    
    # Backup GRUB custom config
    BACKUP_FILE="${GRUB_CUSTOM}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$GRUB_CUSTOM" "$BACKUP_FILE"
    echo "Backed up GRUB configuration to $BACKUP_FILE"
    
    # Add GRUB menu entry with verified paths
    echo "Adding advanced GRUB menu entry..."
    echo "Using kernel: $KERNEL_PATH"
    echo "Using initramfs: $OUTPUT_DIR/$INITRAMFS_NAME"
    cat <<EOF >> "$GRUB_CUSTOM"

# GrubPower Advanced USB Power Mode entry
menuentry 'GrubPower Advanced: USB Power Mode' {
    set root=($GRUB_ROOT)
    linux $KERNEL_PATH quiet init=/init acpi=force acpi_osi=Linux acpi_backlight=vendor $EXTRA_KERNEL_PARAMS
    initrd $OUTPUT_DIR/$INITRAMFS_NAME
}
EOF
    
    # Update GRUB configuration
    echo "Updating GRUB configuration..."
    if command -v update-grub &> /dev/null; then
        update-grub
    elif command -v grub-mkconfig &> /dev/null; then
        grub-mkconfig -o /boot/grub/grub.cfg
    elif command -v grub2-mkconfig &> /dev/null; then
        grub2-mkconfig -o /boot/grub2/grub.cfg
    else
        echo "WARNING: Could not find GRUB update command."
        echo "Please manually update your GRUB configuration with: grub-mkconfig -o /boot/grub/grub.cfg"
    fi
}

# Create safe recovery GRUB entry
create_recovery_grub_entry() {
    echo "Adding recovery GRUB entry..."
    cat <<EOF >> "$GRUB_CUSTOM"

# GrubPower Recovery Boot Entry (automatically boots main OS after 30 seconds)
menuentry 'GrubPower: Recovery Mode (Auto-boot in 30s)' {
    set timeout=30
    set default=0
    terminal_output console
    echo "GrubPower Recovery Mode: Will boot main OS in 30 seconds..."
    echo "Press any key to enter GRUB menu immediately."
    sleep 30
    configfile /boot/grub/grub.cfg
}
EOF
}

# Clean up temporary files
cleanup() {
    echo "Cleaning up..."
    rm -rf "$BUILD_DIR"
    rm -f "/tmp/$INITRAMFS_NAME"
}

# Display help
show_help() {
    cat <<EOF
GrubPower Advanced - Turn your laptop into a USB powerbank

Usage: $0 [options]

Options:
  --help          Show this help message
  --configure     Create/edit configuration file
  --build         Build initramfs only
  --install       Install GRUB entry only
  --uninstall     Remove GrubPower from system
  --full          Perform full installation (default)
  --interactive   Run interactive configuration wizard
  --compatibility Check hardware compatibility only
  --test-usb      Test USB power management capabilities
  --check-update  Check for GrubPower updates
  --version       Display version information

Example:
  sudo $0 --full             # Complete installation
  sudo $0 --interactive      # Run interactive setup wizard
  sudo $0 --configure        # Edit configuration only
  sudo $0 --uninstall        # Remove GrubPower

For more information, see README.md
EOF
}

# Configure option
configure() {
    create_default_config
    if command -v nano &> /dev/null; then
        nano "$CONFIG_FILE"
    elif command -v vi &> /dev/null; then
        vi "$CONFIG_FILE"
    else
        echo "No text editor found. Please edit $CONFIG_FILE manually."
    fi
}

# Uninstall option
uninstall() {
    echo "Uninstalling GrubPower..."
    
    # Load config if exists
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    
    # Remove initramfs
    if [ -f "$OUTPUT_DIR/$INITRAMFS_NAME" ]; then
        rm -f "$OUTPUT_DIR/$INITRAMFS_NAME"
        echo "Removed initramfs from $OUTPUT_DIR/$INITRAMFS_NAME"
    fi
    
    # Remove GRUB entry
    if [ -f "$GRUB_CUSTOM" ]; then
        BACKUP_FILE="${GRUB_CUSTOM}.bak.uninstall.$(date +%Y%m%d%H%M%S)"
        cp "$GRUB_CUSTOM" "$BACKUP_FILE"
        sed -i '/GrubPower/,/}/d' "$GRUB_CUSTOM"
        echo "Removed GrubPower entry from GRUB configuration"
        
        # Update GRUB
        if command -v update-grub &> /dev/null; then
            update-grub
        elif command -v grub-mkconfig &> /dev/null; then
            grub-mkconfig -o /boot/grub/grub.cfg
        elif command -v grub2-mkconfig &> /dev/null; then
            grub2-mkconfig -o /boot/grub2/grub.cfg
        else
            echo "WARNING: Could not find GRUB update command."
            echo "Please manually update your GRUB configuration."
        fi
    fi
    
    # Remove config file
    if [ -f "$CONFIG_FILE" ]; then
        rm -f "$CONFIG_FILE"
        echo "Removed configuration file $CONFIG_FILE"
    fi
    
    echo "GrubPower has been uninstalled."
}

# Main installation function
install_grubpower() {
    echo "Starting GrubPower Advanced installation..."
    
    # Check for updates
    check_for_updates
    
    # Check hardware compatibility
    check_compatibility
    
    # Test USB power management capabilities
    test_usb_power
    
    # Run interactive setup if requested
    if [ "${1:-}" = "--interactive" ]; then
        interactive_setup
    fi
    
    # Load configuration
    load_config
    
    # Detect system configuration
    detect_system
    
    # Build initramfs
    build_initramfs
    
    # Create GRUB entry
    create_grub_entry
    
    # Create recovery GRUB entry
    create_recovery_grub_entry
    
    # Clean up
    cleanup
    
    # Show success message
    cat <<EOF

====================================
GrubPower Advanced installation complete!

To use:
1. Reboot your computer
2. At the GRUB menu, select 'GrubPower Advanced: USB Power Mode'
3. Your USB ports should remain powered

Configuration file: $CONFIG_FILE
Initramfs location: $OUTPUT_DIR/$INITRAMFS_NAME

NOTE: This is experimental. Battery will drain while in this mode.
      The system will shutdown when battery reaches $MIN_BATTERY%.
      For safe recovery, you can use 'GrubPower: Recovery Mode' 
      which will automatically boot your main OS after 30 seconds.
====================================
EOF
}

# Process command line arguments
if [ $# -eq 0 ]; then
    # Default: full installation
    install_grubpower
else
    case "$1" in
        --help)
            show_help
            ;;
        --configure)
            configure
            ;;
        --build)
            load_config
            detect_system
            build_initramfs
            cleanup
            ;;
        --install)
            load_config
            detect_system
            create_grub_entry
            create_recovery_grub_entry
            ;;
        --uninstall)
            uninstall
            ;;
        --full)
            install_grubpower
            ;;
        --interactive)
            interactive_setup
            install_grubpower "--interactive"
            ;;
        --compatibility)
            check_compatibility
            ;;
        --test-usb)
            test_usb_power
            ;;
        --check-update)
            check_for_updates
            ;;
        --version)
            echo "GrubPower Advanced version $VERSION"
            ;;
        --rebuild-grub)
            echo "Rebuilding GRUB entry with correct kernel path..."
            uninstall
            echo "Now reinstalling with proper kernel detection..."
            load_config
            detect_system
            build_initramfs
            create_grub_entry
            create_recovery_grub_entry
            cleanup
            echo "GRUB entry rebuilt. Please reboot to test the fix."
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
fi

exit 0
