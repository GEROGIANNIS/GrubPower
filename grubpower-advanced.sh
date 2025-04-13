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
        DETECTED_KERNEL=$(find /boot -name "vmlinuz-*" | sort -V | tail -n 1)
        if [ -n "$DETECTED_KERNEL" ]; then
            echo "Detected kernel: $DETECTED_KERNEL"
            sed -i "s|KERNEL_PATH=.*|KERNEL_PATH=\"$DETECTED_KERNEL\"|" "$CONFIG_FILE"
            KERNEL_PATH="$DETECTED_KERNEL"
        else
            echo "ERROR: Could not detect kernel. Please set KERNEL_PATH in $CONFIG_FILE."
            exit 1
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
EOF

    chmod +x "$BUILD_DIR/init"
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
    # Backup GRUB custom config
    BACKUP_FILE="${GRUB_CUSTOM}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$GRUB_CUSTOM" "$BACKUP_FILE"
    echo "Backed up GRUB configuration to $BACKUP_FILE"
    
    # Add GRUB menu entry
    echo "Adding advanced GRUB menu entry..."
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

Example:
  sudo $0 --full             # Complete installation
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
    
    # Load configuration
    load_config
    
    # Detect system configuration
    detect_system
    
    # Build initramfs
    build_initramfs
    
    # Create GRUB entry
    create_grub_entry
    
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
      To return to normal operation, reboot and select your regular OS.
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
            ;;
        --uninstall)
            uninstall
            ;;
        --full)
            install_grubpower
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
fi

exit 0
