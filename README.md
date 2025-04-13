# GrubPower

## Convert Your Laptop Into a USB Powerbank

GrubPower is an experimental utility that creates a minimal Linux boot environment designed to keep your laptop's USB ports powered without running a full operating system. This allows you to use your laptop's battery to charge USB devices when you don't need to use the computer itself.

## Latest Version: 1.2.0 (April 2025)

The latest GrubPower Advanced release includes significant improvements:
- Enhanced battery monitoring with configurable shutdown threshold
- Automatic display control based on lid state
- Customizable USB port selection (all ports, charging ports, or specific ports)
- Improved hardware detection and compatibility
- Optional logging for troubleshooting
- Recovery boot mode for enhanced safety

## How It Works

GrubPower creates a tiny Linux initramfs that:

1. Loads only the essential USB drivers
2. Configures USB power management to keep ports active
3. Handles laptop lid closure events to keep USB ports powered
4. Controls display power based on lid state (off when closed, on when opened)
5. Monitors battery level and shuts down at configurable threshold
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

## Installation Options

### Standard Installation
```bash
sudo ./grubpower.sh
```

### Advanced Installation with Enhanced Features
```bash
sudo ./grubpower-advanced.sh
```

### Interactive Setup (Recommended for first-time users)
```bash
sudo ./grubpower-advanced.sh --interactive
```

### Direct Install (For troubleshooting compatibility issues)
```bash
sudo ./grubpower-advanced.sh --direct
```

### Debug Mode (For resolving kernel path and GRUB issues)
```bash
sudo ./grubpower-advanced.sh --full-debug
```

After installation, reboot your computer and select "GrubPower Advanced: USB Power Mode" from the GRUB menu.

## Usage

Once booted into GrubPower mode:

- Connect USB devices to be charged
- The system will display a simple message indicating GrubPower is active
- You can close your laptop lid - the system will turn off the display while maintaining USB power
- Opening the lid will turn the display back on while continuing to provide USB power
- The system will automatically shutdown when battery reaches the configured threshold (default: 10%)
- To exit, reboot your computer (press Ctrl+Alt+Del)
- Select your normal OS from the GRUB menu to return to regular operation

## Safety Features

GrubPower Advanced includes several safety features:
- Automatic shutdown at low battery (configurable threshold)
- Recovery boot entry that automatically boots to your main OS after 30 seconds
- Compatibility detection to warn about unsupported hardware
- Rollback functionality in case of installation failure

## Troubleshooting

If USB ports don't remain powered:

1. Check your laptop's BIOS/UEFI settings for "USB power in sleep/off" options
2. Some laptops require specific USB ports for charging (often marked with a lightning bolt)
3. Try using the `--direct` installation option for a simplified setup
4. Use the `--compatibility` flag to check hardware support: `sudo ./grubpower-advanced.sh --compatibility`
5. If you experience kernel loading issues, try the `--full-debug` option

If you have kernel path issues ("file not found" errors in GRUB):
```bash
sudo ./grubpower-advanced.sh --rebuild-grub
```

## Uninstallation

To completely remove GrubPower:
```bash
sudo ./grubpower-advanced.sh --uninstall
```

This will:
1. Remove the initramfs file
2. Clean up GRUB entries
3. Optionally remove the configuration file

## Advanced Configuration

For advanced users, you can modify several aspects through the configuration file at `/etc/grubpower.conf`:

```
# System paths and core settings
KERNEL_PATH, GRUB_ROOT, etc.

# Power management settings
MIN_BATTERY=10           # Auto-shutdown at 10% battery
DISABLE_AUTOSUSPEND=1    # Prevent USB devices from sleeping
ENABLE_LOGGING=0         # Enable/disable logging
LOG_FILE="/var/log/grubpower.log"  # Log file location

# USB port selection
SELECT_PORTS="all"       # Options: all, charging, or specific ports (e.g., "1,2,4")

# Lid control settings
LID_CONTROL=1            # Enable lid detection
HANDLE_ACPI=1            # Handle ACPI events
```

To edit the configuration:
```bash
sudo ./grubpower-advanced.sh --configure
```

## Command-Line Options

The advanced script supports the following options:
- `--help` - Show help message
- `--configure` - Create/edit configuration file
- `--build` - Build initramfs only
- `--install` - Install GRUB entry only
- `--uninstall` - Remove GrubPower from system
- `--full` - Perform full installation (default)
- `--full-debug` - Perform full installation with verbose debugging
- `--interactive` - Run interactive configuration wizard
- `--compatibility` - Check hardware compatibility only
- `--test-usb` - Test USB power management capabilities
- `--check-update` - Check for GrubPower updates
- `--version` - Display version information
- `--direct` - Perform direct installation (bypasses problematic parts)
- `--rebuild-grub` - Rebuild GRUB entry with correct paths

## License

This project is released under the MIT License.

## Disclaimer

This software is provided as-is with no warranty. The authors are not responsible for any damage to your system, loss of data, or other issues that may arise from using this experimental software. Use at your own risk.
