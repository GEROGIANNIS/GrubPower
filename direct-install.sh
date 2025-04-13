#!/bin/bash
# GrubPower Direct Installation Script
# Created: April 13, 2025
# This script bypasses problematic parts of the main script

echo "GrubPower Direct Installation"
echo "============================"

# Configuration variables
CONFIG_FILE="/etc/grubpower.conf"
KERNEL_PATH="/boot/vmlinuz-6.8.0-57-generic"
GRUB_ROOT="hostdisk//dev/nvme0n1,gpt5"
OUTPUT_DIR="/boot"
INITRAMFS_NAME="grubpower-initramfs.img"
BUILD_DIR="/tmp/grubpower_build"
GRUB_CUSTOM="/etc/grub.d/40_custom"

# Load configuration if it exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    echo "Loaded configuration from $CONFIG_FILE"
fi

echo "Using the following settings:"
echo "- Kernel path: $KERNEL_PATH"
echo "- GRUB root: $GRUB_ROOT"
echo "- Output directory: $OUTPUT_DIR"
echo "- Initramfs name: $INITRAMFS_NAME"

# Verify kernel path
if [ ! -f "$KERNEL_PATH" ]; then
    echo "ERROR: Kernel not found at $KERNEL_PATH"
    exit 1
else
    echo "Verified kernel exists at $KERNEL_PATH"
fi

# Create build directory
echo "Creating build environment..."
mkdir -p "$BUILD_DIR"/{bin,dev,proc,sys,usr/lib/modules,var/log,etc/acpi/events,lib/modules}

# Install busybox
if command -v busybox &> /dev/null; then
    cp $(which busybox) "$BUILD_DIR/bin/"
    echo "Installed busybox"
else
    echo "ERROR: Busybox not found. Please install it with 'sudo apt install busybox-static'"
    exit 1
fi

# Create symlinks
echo "Creating essential symlinks..."
cd "$BUILD_DIR/bin"
for cmd in sh sleep echo cat clear date grep mkdir touch ls modprobe insmod lsmod rmmod find; do
    ln -sf busybox $cmd
done
cd - > /dev/null

# Create basic init script
echo "Creating init script..."
cat > "$BUILD_DIR/init" << 'EOFSCRIPT'
#!/bin/sh
# GrubPower init script

echo "GrubPower USB Power Mode initializing..."

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Load USB modules
echo "Loading USB modules..."
modprobe usbcore
modprobe usb_common
modprobe ehci_hcd || true
modprobe ohci_hcd || true
modprobe uhci_hcd || true
modprobe xhci_hcd || true

# Wait for USB subsystem
sleep 3

# Enable USB power
echo "Enabling USB power..."
for i in /sys/bus/usb/devices/*/power/control; do
    if [ -f "$i" ]; then
        echo "on" > "$i" 2>/dev/null || true
        echo "Power enabled for $i"
    fi
done

# Disable USB autosuspend
for i in /sys/bus/usb/devices/*/power/autosuspend; do
    if [ -f "$i" ]; then
        echo "-1" > "$i" 2>/dev/null || true
    fi
done

# Print status
clear
echo "======================================"
echo "GrubPower USB Power Mode Activated"
echo "======================================"
echo "All USB ports are now powered"
echo ""
echo "IMPORTANT: Battery will drain in this mode!"
echo "Press CTRL+ALT+DEL to reboot"
echo "======================================"

# Keep system alive
while true; do
    # Refresh USB power settings every minute
    if [ $(($(date +%s) % 60)) -eq 0 ]; then
        for i in /sys/bus/usb/devices/*/power/control; do
            if [ -f "$i" ]; then
                echo "on" > "$i" 2>/dev/null || true
            fi
        done
    fi
    sleep 5
done
EOFSCRIPT

# Make init script executable
chmod +x "$BUILD_DIR/init"

# Package the initramfs
echo "Building initramfs image..."
cd "$BUILD_DIR"
find . | cpio -H newc -o | gzip > "/tmp/$INITRAMFS_NAME"
cd - > /dev/null

# Copy to output directory
sudo cp "/tmp/$INITRAMFS_NAME" "$OUTPUT_DIR/"
echo "Initramfs created at $OUTPUT_DIR/$INITRAMFS_NAME"

# Backup GRUB custom file
BACKUP_FILE="${GRUB_CUSTOM}.bak.$(date +%Y%m%d%H%M%S)"
sudo cp "$GRUB_CUSTOM" "$BACKUP_FILE"
echo "Backed up GRUB configuration to $BACKUP_FILE"

# Add GRUB entry
echo "Adding GRUB menu entry..."
sudo bash -c "cat >> $GRUB_CUSTOM << EOFGRUB

# GrubPower USB Power Mode entry
menuentry 'GrubPower: USB Power Mode' {
    set root=($GRUB_ROOT)
    linux $KERNEL_PATH quiet init=/init acpi=force
    initrd $OUTPUT_DIR/$INITRAMFS_NAME
}

# GrubPower Recovery Mode entry
menuentry 'GrubPower: Recovery Mode (Auto-boot in 30s)' {
    set timeout=30
    set default=0
    terminal_output console
    echo 'GrubPower Recovery Mode - Will boot main OS in 30 seconds...'
    echo 'Press any key to enter GRUB menu immediately.'
    sleep 30
    configfile /boot/grub/grub.cfg
}
EOFGRUB"

# Update GRUB
echo "Updating GRUB configuration..."
if command -v update-grub &> /dev/null; then
    sudo update-grub
elif command -v grub-mkconfig &> /dev/null; then
    sudo grub-mkconfig -o /boot/grub/grub.cfg
elif command -v grub2-mkconfig &> /dev/null; then
    sudo grub2-mkconfig -o /boot/grub2/grub.cfg
else
    echo "WARNING: Could not find GRUB update command."
    echo "Please manually update your GRUB configuration with:"
    echo "sudo grub-mkconfig -o /boot/grub/grub.cfg"
fi

# Clean up
echo "Cleaning up..."
rm -rf "$BUILD_DIR"
rm -f "/tmp/$INITRAMFS_NAME"

echo ""
echo "Installation completed successfully!"
echo "======================================"
echo "To use GrubPower USB Power Mode:"
echo "1. Reboot your computer"
echo "2. At the GRUB menu, select 'GrubPower: USB Power Mode'"
echo "3. Your USB ports should remain powered"
echo ""
echo "If you have any issues, use the Recovery Mode option"
echo "which will automatically boot your main OS after 30 seconds."
echo "======================================"
