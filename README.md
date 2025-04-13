# GrubPower

## Convert Your Laptop Into a USB Powerbank

GrubPower is an experimental utility that creates a minimal Linux boot environment designed to keep your laptop's USB ports powered without running a full operating system. This allows you to use your laptop's battery to charge USB devices when you don't need to use the computer itself.

## How It Works

GrubPower creates a tiny Linux initramfs that:

1. Loads only the essential USB drivers
2. Configures USB power management to keep ports active
3. Handles laptop lid closure events to keep USB ports powered
4. Controls display power based on lid state (off when closed, on when opened)
5. Enters an idle loop to maintain power to USB ports
6. Uses minimal resources to maximize battery efficiency

The system adds a special GRUB boot entry that boots directly into this minimal environment instead of your full operating system.

## ⚠️ Important Warnings ⚠️

- **This is highly experimental** and may not work on all hardware
- USB power management is heavily dependent on your specific laptop model
- Battery will drain faster than in hibernation/standby modes
- The script modifies your GRUB bootloader configuration
- No data protection mechanisms are active in this mode

## Prerequisites

- A Linux system with GRUB bootloader
- Root/sudo privileges
- Basic understanding of Linux boot processes
- Busybox (will be installed if not present)

## Installation

1. Download the `grubpower.sh` script
2. Make it executable: `chmod +x grubpower.sh`
3. Run as root: `sudo ./grubpower.sh`
4. Reboot your computer
5. Select "GrubPower: USB Power Mode" from the GRUB menu

## Usage

Once booted into GrubPower mode:

- Connect USB devices to be charged
- The system will display a simple message indicating GrubPower is active
- You can close your laptop lid - the system will turn off the display while maintaining USB power
- Opening the lid will turn the display back on while continuing to provide USB power
- To exit, reboot your computer (press Ctrl+Alt+Del)
- Select your normal OS from the GRUB menu to return to regular operation

## Troubleshooting

If USB ports don't remain powered:

1. Check your laptop's BIOS/UEFI settings for "USB power in sleep/off" options
2. Some laptops require specific USB ports for charging (often marked with a lightning bolt)
3. Try modifying the init script to load additional USB-related kernel modules
4. Check kernel logs to identify any power management issues

## Uninstallation

To remove GrubPower:

1. Delete the initramfs file: `sudo rm /boot/grubpower-initramfs.img`
2. Edit GRUB custom config: `sudo nano /etc/grub.d/40_custom`
3. Remove the GrubPower menu entry
4. Update GRUB: `sudo update-grub`

## Advanced Configuration

For advanced users, you can modify several aspects:

- Edit the init script to include additional drivers
- Change power management settings in the init script
- Configure automatic shutdown after a certain time period
- Customize lid detection and display power management
- Enable or disable specific USB ports
- Add LED indicators or other status displays if your hardware supports it

The advanced version includes a configuration file at `/etc/grubpower.conf` where you can customize:

```
# System paths and core settings
KERNEL_PATH, GRUB_ROOT, etc.

# Power management settings
MIN_BATTERY=10           # Auto-shutdown at 10% battery
DISABLE_AUTOSUSPEND=1    # Prevent USB devices from sleeping

# Lid control settings
LID_CONTROL=1            # Enable lid detection
HANDLE_ACPI=1            # Handle ACPI events

# USB port selection
SELECT_PORTS="all"       # Options: all, charging, or specific ports (e.g., "1,2,4")
```

## License

This project is released under the MIT License.

## Disclaimer

This software is provided as-is with no warranty. The authors are not responsible for any damage to your system, loss of data, or other issues that may arise from using this experimental software. Use at your own risk.
