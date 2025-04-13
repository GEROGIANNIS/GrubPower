#!/bin/bash
# GrubPower - Turn your laptop into a USB powerbank using a minimal Linux environment
# Author: Claude
# Date: April 12, 2025
# License: MIT
#
# This script creates a minimal Linux environment that boots just enough to power USB ports
# without running a full desktop session.
#
# WARNING: This is highly experimental. Success depends on your hardware's support for
# USB power management. Always back up your system before proceeding.

set -e  # Exit on error

# Configuration variables (adjust these for your system)
KERNEL_PATH="/boot/vmlinuz-linux"  # Path to your Linux kernel
GRUB_ROOT="hd0,1"                 # GRUB root partition (adjust for your system)
OUTPUT_DIR="/boot"                 # Where to place the initramfs
INITRAMFS_NAME="grubpower-initramfs.img"
BUILD_DIR="/tmp/grubpower_build"   # Temporary build directory
GRUB_CUSTOM="/etc/grub.d/40_custom"  # GRUB custom config file

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

# Check if kernel exists
if [ ! -f "$KERNEL_PATH" ]; then
    echo "Kernel not found at $KERNEL_PATH"
    echo "Please adjust KERNEL_PATH in the script to point to your kernel."
    exit 1
fi

# Create build directory
echo "Creating build environment..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"/{bin,dev,proc,sys,usr/lib/modules}

# Copy essential binaries (busybox for basic functionality)
echo "Installing busybox..."
if command -v busybox &> /dev/null; then
    cp $(which busybox) "$BUILD_DIR/bin/"
    # Create essential symlinks
    cd "$BUILD_DIR/bin"
    ln -s busybox sh
    ln -s busybox sleep
    ln -s busybox echo
    ln -s busybox cat
    cd - > /dev/null
else
    echo "Busybox not found. Installing..."
    apt-get update && apt-get install -y busybox-static
    cp $(which busybox) "$BUILD_DIR/bin/"
    # Create essential symlinks
    cd "$BUILD_DIR/bin"
    ln -s busybox sh
    ln -s busybox sleep
    ln -s busybox echo
    ln -s busybox cat
    cd - > /dev/null
fi

# Create minimal init script
echo "Creating init script..."
cat > "$BUILD_DIR/init" <<'EOF'
#!/bin/sh
# GrubPower minimal init script
# This script initializes USB subsystem and then idles to keep power flowing

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Load USB modules (commonly needed for USB power)
modprobe usb_common
modprobe usbcore
modprobe ehci_hcd
modprobe ohci_hcd
modprobe uhci_hcd
modprobe xhci_hcd
modprobe usb_storage

# Enable USB ports power management
for i in /sys/bus/usb/devices/*/power/control; do
    echo "on" > $i 2>/dev/null || true
done

# Disable USB autosuspend
for i in /sys/bus/usb/devices/*/power/autosuspend; do
    echo "-1" > $i 2>/dev/null || true
done

# Print status message
echo ""
echo "======================================"
echo "GrubPower USB mode activated"
echo "USB ports should now be powered"
echo "IMPORTANT: Battery will drain in this mode!"
echo "Press CTRL+ALT+DEL to reboot if needed"
echo "======================================"
echo ""

# Stay alive loop
while true; do
    sleep 60
done
EOF

chmod +x "$BUILD_DIR/init"

# Package the initramfs
echo "Building initramfs image..."
cd "$BUILD_DIR"
find . | cpio -H newc -o | gzip > "/tmp/$INITRAMFS_NAME"
cd - > /dev/null

# Copy the initramfs to boot directory
cp "/tmp/$INITRAMFS_NAME" "$OUTPUT_DIR/"
echo "Initramfs created at $OUTPUT_DIR/$INITRAMFS_NAME"

# Backup GRUB custom config
BACKUP_FILE="${GRUB_CUSTOM}.bak.$(date +%Y%m%d%H%M%S)"
cp "$GRUB_CUSTOM" "$BACKUP_FILE"
echo "Backed up GRUB configuration to $BACKUP_FILE"

# Add GRUB menu entry
echo "Adding GRUB menu entry..."
cat <<EOF >> "$GRUB_CUSTOM"

# GrubPower USB Power Mode entry
menuentry 'GrubPower: USB Power Mode' {
    set root=($GRUB_ROOT)
    linux $KERNEL_PATH quiet init=/init acpi=force
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
    echo "Please manually update your GRUB configuration."
fi

# Clean up
rm -rf "$BUILD_DIR"
rm "/tmp/$INITRAMFS_NAME"

echo ""
echo "======================================"
echo "GrubPower installation complete!"
echo "To use:"
echo "1. Reboot your computer"
echo "2. At the GRUB menu, select 'GrubPower: USB Power Mode'"
echo "3. Your USB ports should remain powered"
echo ""
echo "NOTE: This is experimental. Battery will drain while in this mode."
echo "To return to normal operation, reboot and select your regular OS."
echo "======================================"
