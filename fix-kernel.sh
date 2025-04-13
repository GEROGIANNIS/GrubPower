#!/bin/bash

# Script to fix kernel path issues
echo "GrubPower Kernel Path Fixer"
echo "============================"

# Configuration file
CONFIG_FILE="/etc/grubpower.conf"

# Load configuration if it exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    echo "Loaded configuration from $CONFIG_FILE"
else
    echo "Configuration file not found. Will create one."
    KERNEL_PATH="/boot/vmlinuz-linux"
    GRUB_ROOT="hd0,1"
    OUTPUT_DIR="/boot"
    INITRAMFS_NAME="grubpower-initramfs.img"
fi

# Show current settings
echo "Current settings:"
echo "- Kernel path: $KERNEL_PATH"
echo "- GRUB root: $GRUB_ROOT"

    
    # Fix for genenic typo
if [[ "$KERNEL_PATH" == *"genenic"* ]]; then
    FIXED_PATH="${KERNEL_PATH//genenic/generic}"
    echo "Fixed typo in kernel path:"
    echo "  From: $KERNEL_PATH"
    echo "  To:   $FIXED_PATH"
    
    if [ -f "$FIXED_PATH" ]; then
        KERNEL_PATH="$FIXED_PATH"
        if [ -f "$CONFIG_FILE" ]; then
            sudo sed -i "s|KERNEL_PATH=.*|KERNEL_PATH=\"$KERNEL_PATH\"|" "$CONFIG_FILE"
            echo "Updated configuration file with corrected path."
        fi
    else
        echo "WARNING: Corrected path doesn't exist."
    fi
fi

# Check running kernel as alternative
RUNNING_KERNEL=$(uname -r)
echo "Current running kernel: $RUNNING_KERNEL"

if [ -f "/boot/vmlinuz-$RUNNING_KERNEL" ]; then
    echo "Found kernel file for running kernel: /boot/vmlinuz-$RUNNING_KERNEL"
    
    # Ask user if they want to use this kernel
    read -p "Use running kernel path instead? (y/n): " USE_RUNNING
    if [[ "$USE_RUNNING" =~ ^[Yy]$ ]]; then
        KERNEL_PATH="/boot/vmlinuz-$RUNNING_KERNEL"
        if [ -f "$CONFIG_FILE" ]; then
            sudo sed -i "s|KERNEL_PATH=.*|KERNEL_PATH=\"$KERNEL_PATH\"|" "$CONFIG_FILE"
            echo "Updated configuration to use current running kernel."
        fi
    fi
fi

# Check if GRUB root is correct
if command -v grub-probe &> /dev/null; then
    PROBE_RESULT=$(grub-probe -t drive /boot 2>/dev/null || echo "Error")
    if [ "$PROBE_RESULT" != "Error" ]; then
        echo "GRUB probe reports boot location as: $PROBE_RESULT"
        
        # Extract the actual GRUB root format - using a safer pattern matching approach
        DETECTED_ROOT=$(echo "$PROBE_RESULT" | sed -n 's/.*(\([^)]*\)).*/\1/p')
        if [ -n "$DETECTED_ROOT" ]; then
            if [ "$DETECTED_ROOT" != "$GRUB_ROOT" ]; then
                echo "GRUB root doesn't match probe value:"
                echo "  Current: $GRUB_ROOT"
                echo "  Detected: $DETECTED_ROOT"
                
                read -p "Update GRUB root to detected value? (y/n): " UPDATE_ROOT
                if [[ "$UPDATE_ROOT" =~ ^[Yy]$ ]]; then
                    GRUB_ROOT="$DETECTED_ROOT"
                    if [ -f "$CONFIG_FILE" ]; then
                        sudo sed -i "s|GRUB_ROOT=.*|GRUB_ROOT=\"$GRUB_ROOT\"|" "$CONFIG_FILE"
                        echo "Updated GRUB root to $GRUB_ROOT"
                    fi
                fi
            else
                echo "GRUB root appears to be correct."
            fi
        else
            echo "Could not extract GRUB root format from probe result."
        fi
    else
        echo "Could not detect GRUB root with grub-probe."
    fi
fi

# Final settings
echo ""
echo "Final settings:"
echo "- Kernel path: $KERNEL_PATH (exists: $([ -f "$KERNEL_PATH" ] && echo "YES" || echo "NO"))"
echo "- GRUB root: $GRUB_ROOT"

# Create test GRUB entry
echo ""
echo "Here's what your GRUB entry would look like:"
echo "-----------------------------------------"
echo "menuentry 'GrubPower Advanced: USB Power Mode' {"
echo "    set root=($GRUB_ROOT)"
echo "    linux $KERNEL_PATH quiet init=/init acpi=force"
echo "    initrd /boot/grubpower-initramfs.img"
echo "}"
echo "-----------------------------------------"

# Ask if user wants to rebuild GRUB entries
echo ""
read -p "Do you want to rebuild the GRUB entries with these settings? (y/n): " REBUILD
if [[ "$REBUILD" =~ ^[Yy]$ ]]; then
    echo "Running the grubpower-advanced.sh script with the --rebuild-grub option..."
    
    if [ -f "/home/oldjohn/GrubPower/grubpower-advanced.sh" ]; then
        sudo /home/oldjohn/GrubPower/grubpower-advanced.sh --rebuild-grub
    else
        echo "Could not find grubpower-advanced.sh script. Please run it manually."
    fi
fi

echo ""
echo "Kernel path fix completed."
echo "If you still have issues, you can manually edit $CONFIG_FILE"
echo "and set KERNEL_PATH to the correct path to your kernel file."
