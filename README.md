# Time Machine Auto-Backup

> **Automatically backup to Time Machine when your external disk is plugged in, then safely eject when done.**

Stop worrying about whether you remembered to backup or safely eject your Time Machine disk. This script handles it automatically—just plug in your backup drive and let it work.

[![macOS](https://img.shields.io/badge/macOS-26.2+-blue.svg)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

## ✨ Features

### Core Functionality
- **🔌 Plug & Forget**: Automatically detects when Time Machine disk is mounted
- **⚡ Smart Backups**: Only backs up when threshold time has elapsed (default: 72 hours)
- **🎯 Auto-Eject**: Safely ejects disk after backup completes (or immediately if no backup needed)
- **🔒 Single-Instance**: Prevents multiple simultaneous runs with intelligent lock mechanism
- **💪 Resilient**: Handles interrupted backups, disk unplugging, and edge cases gracefully

### Advanced Features
- **🎨 Menu Bar Icon**: Optionally shows Time Machine icon during active backups
- **📊 Smart Scheduling**: Fallback to timestamp-based scheduling if backup history unavailable
- **🔄 Conflict Resolution**: Waits for user-initiated backups to complete before proceeding
- **⚙️ Multi-Destination Support**: Can target specific backup disk via UUID (required if you have multiple)
- **📝 Comprehensive Logging**: Automatic log rotation with configurable size limits
- **🛡️ Full Disk Access Handling**: Graceful degradation when FDA is missing

---

## 📋 Requirements

- **macOS 10.13+** (High Sierra or later)
- **Time Machine** configured with a local backup destination
- **Full Disk Access** (optional but recommended for best reliability)

> **Note**: Network Time Machine destinations (SMB/AFP) are not currently supported.

---

## 🚀 Quick Start

### 1. Install the Script

```bash
# Create directories
mkdir -p "$HOME/Library/Scripts"
mkdir -p "$HOME/Library/LaunchAgents"

# Download and install the script
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/timemachine-auto/main/timemachine-auto.sh
mv timemachine-auto.sh "$HOME/Library/Scripts/"
chmod +x "$HOME/Library/Scripts/timemachine-auto.sh"

# Download and install the launchd agent
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/timemachine-auto/main/com.user.timemachine-auto.plist
mv com.user.timemachine-auto.plist "$HOME/Library/LaunchAgents/"
```

### 2. Grant Full Disk Access (Recommended)

1. Open **System Settings** → **Privacy & Security** → **Full Disk Access**
2. Click the **+** button
3. Navigate to `/bin/bash` and add it
4. Alternatively, add your terminal emulator (Terminal.app, iTerm, etc.)

> Without Full Disk Access, the script will still work using fallback scheduling, but won't be able to read backup history directly.

### 3. Load the Agent

```bash
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.user.timemachine-auto.plist"
```

### 4. Test It

```bash
# Plug in your Time Machine disk and watch the log:
tail -f "$HOME/Library/Logs/AutoTMLogs/tm-auto-backup.log"

# Or trigger manually:
launchctl kickstart -k "gui/$(id -u)/com.user.timemachine-auto"
```

---

## ⚙️ Configuration

Edit `~/Library/Scripts/timemachine-auto.sh` to customize behavior:

### Basic Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `BACKUP_THRESHOLD_HOURS` | `72` | Minimum hours between backups (72 = 3 days) |
| `EJECT_WHEN_NO_BACKUP` | `true` | Auto-eject disk if backup not needed |
| `SHOW_MENUBAR_ICON_DURING_BACKUP` | `true` | Show Time Machine icon during backup |
| `ALLOW_AUTOMOUNT` | `false` | Attempt to mount unmounted TM disks |

### Advanced Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `PREFERRED_DESTINATION_ID` | `""` | Target specific backup disk UUID (required if you have multiple) |
| `REQUIRE_SNAPSHOT_VERIFICATION` | `false` | Verify new snapshot before ejecting |
| `BACKUP_BLOCK_TIMEOUT_SECONDS` | `14400` | Max backup duration (4 hours) |
| `EJECT_RETRY_ATTEMPTS` | `3` | Number of eject retries |
| `DUPLICATE_WINDOW_SECONDS` | `120` | Ignore duplicate triggers within this time |

### Finding Your Destination UUID

If you have multiple Time Machine destinations:

```bash
tmutil destinationinfo -X | grep -A1 "ID"
```

Copy the UUID and set it in the script:
```bash
PREFERRED_DESTINATION_ID="YOUR-UUID-HERE"
```

---

## 📖 How It Works

### Automatic Triggers

The script runs automatically when:
1. **Any volume mounts** (`StartOnMount` in launchd)
2. **User logs in** (`RunAtLoad` in launchd)
3. **Every 30 minutes** as a safety check (`StartInterval` in launchd)

### Decision Flow

```
Disk Mounted
    ↓
Is it a Time Machine disk?
    ↓ Yes
Was backup done recently? (< BACKUP_THRESHOLD_HOURS)
    ↓ No
Start Time Machine backup
    ↓
Wait for completion (with timeout)
    ↓
Backup successful?
    ↓ Yes
Eject disk safely
    ↓
Done ✓
```

If backup not needed, disk is ejected immediately (unless `EJECT_WHEN_NO_BACKUP=false`).

### Safety Features

- **Single-instance lock**: Prevents overlapping runs
- **Backup timeout**: Won't wait indefinitely (default: 4 hours)
- **Eject verification**: Confirms disk is actually ejected
- **Conflict detection**: Waits for user-initiated backups
- **Duplicate suppression**: Won't re-process same mount multiple times
- **State persistence**: Remembers last backup across runs

---

## 🔧 Management Commands

### Check Status
```bash
launchctl print "gui/$(id -u)/com.user.timemachine-auto"
```

### View Logs
```bash
# Real-time
tail -f "$HOME/Library/Logs/AutoTMLogs/tm-auto-backup.log"

# Recent entries
tail -50 "$HOME/Library/Logs/AutoTMLogs/tm-auto-backup.log"
```

### Manual Trigger
```bash
launchctl kickstart -k "gui/$(id -u)/com.user.timemachine-auto"
```

### Disable Temporarily
```bash
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.user.timemachine-auto.plist"
```

### Re-enable
```bash
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.user.timemachine-auto.plist"
```

### Run Manually (for debugging)
```bash
"$HOME/Library/Scripts/timemachine-auto.sh"
```

---

## 🗑️ Uninstall

```bash
# 1. Stop and remove the agent
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.user.timemachine-auto.plist"

# 2. Remove files
rm -f "$HOME/Library/LaunchAgents/com.user.timemachine-auto.plist"
rm -f "$HOME/Library/Scripts/timemachine-auto.sh"

# 3. Remove state and logs (optional)
rm -rf "$HOME/Library/Application Support/TimeMachineAuto"
rm -rf "$HOME/Library/Caches/com.user.timemachine-auto.lock"
rm -rf "$HOME/Library/Logs/AutoTMLogs"
```

---

## 🐛 Troubleshooting

### Script Not Running

**Check if agent is loaded:**
```bash
launchctl print "gui/$(id -u)/com.user.timemachine-auto"
```

If not loaded, bootstrap it:
```bash
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.user.timemachine-auto.plist"
```

### Disk Not Ejecting

**Check logs for errors:**
```bash
tail -50 "$HOME/Library/Logs/AutoTMLogs/tm-auto-backup.log"
```

**Common causes:**
- Finder window open to the disk
- Files on disk in use by another app
- Backup still running

**Force re-attempt:**
Close all windows/apps using the disk, then:
```bash
launchctl kickstart -k "gui/$(id -u)/com.user.timemachine-auto"
```

### Backup Not Starting

**Verify Time Machine is configured:**
```bash
tmutil destinationinfo
```

**Check Full Disk Access:**
System Settings → Privacy & Security → Full Disk Access → Add `/bin/bash`

### Multiple Destination Warning

If you have multiple Time Machine disks, set `PREFERRED_DESTINATION_ID`:

```bash
# Find your UUID
tmutil destinationinfo -X | grep -A1 "ID"

# Edit script
nano "$HOME/Library/Scripts/timemachine-auto.sh"
# Set: PREFERRED_DESTINATION_ID="YOUR-UUID-HERE"
```

### Menu Icon Not Appearing

The script tries multiple paths for the Time Machine menu extra. If none work on your macOS version:
```bash
# Disable the feature
nano "$HOME/Library/Scripts/timemachine-auto.sh"
# Set: SHOW_MENUBAR_ICON_DURING_BACKUP=false
```

---

## 📊 Log File Locations

| File | Purpose |
|------|---------|
| `~/Library/Logs/AutoTMLogs/tm-auto-backup.log` | Main log file |
| `~/Library/Logs/AutoTMLogs/tm-auto-backup.log.1` | Previous log (rotated) |
| `~/Library/Application Support/TimeMachineAuto/` | State files |
| `~/Library/Caches/com.user.timemachine-auto.lock/` | Lock files |

Logs automatically rotate when they exceed 5 MB (configurable via `MAX_LOG_BYTES`).

---

## ⚡ Performance Impact

- **CPU**: Negligible (only active during mount events and 30-min checks)
- **Battery**: Minimal (smart fast-path exits immediately for non-TM mounts)
- **Disk**: Only writes to log file and small state files
- **Network**: None (local operations only)

The script is designed to be extremely lightweight and exit quickly when nothing needs to be done.

---

## 🔒 Security & Privacy

- **No network communication**: All operations are local
- **No data collection**: Script doesn't send data anywhere
- **Minimal permissions**: Only needs Full Disk Access for `tmutil` commands
- **Open source**: Fully auditable code
- **Sandboxed**: Runs in user context, not as root

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development

**Run with debug output:**
```bash
set -x  # Enable bash debug mode
"$HOME/Library/Scripts/timemachine-auto.sh"
set +x
```

**Test without launchd:**
```bash
# Direct execution
"$HOME/Library/Scripts/timemachine-auto.sh"

# Check exit code
echo $?
```

---

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Built for macOS using native `tmutil`, `diskutil`, and `launchd`
- Inspired by the need for safer, automatic Time Machine workflows
- Thanks to the macOS automation community

---

## ⚠️ Disclaimer

This script automates Time Machine backups and disk ejection. While extensively tested, use at your own risk. Always maintain multiple backups of important data. The authors are not responsible for data loss.

---

**Made with ❤️ for the macOS community**
