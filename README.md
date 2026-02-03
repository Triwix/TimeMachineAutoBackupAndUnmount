# macOS Time Machine Auto-Backup

Automatically triggers Time Machine backups when your backup disk is mounted, then ejects the disk when done.

## Features

- ✅ Runs automatically when Time Machine disk is mounted
- ✅ Runs on login (catches cases where disk was plugged in while Mac was sleeping)
- ✅ Only backs up if last backup is older than 3 days (configurable)
- ✅ Ejects disk automatically after backup completes
- ✅ Sends macOS notifications for backup completion and errors
- ✅ Logs all activity to `~/Library/Logs/tm-auto-backup.log`

## Requirements

- macOS (tested on macOS 15.2+)
- Time Machine already configured with a backup disk
- Terminal with Full Disk Access (for `tmutil` commands)

## Installation

### 1. Copy the script
```bash
mkdir -p ~/Library/Scripts
curl -o ~/Library/Scripts/timemachine-auto.sh https://raw.githubusercontent.com/YOUR_USERNAME/macos-timemachine-auto-backup/main/timemachine-auto.sh
chmod +x ~/Library/Scripts/timemachine-auto.sh
```

### 2. Install the LaunchAgent
```bash
curl -o ~/Library/LaunchAgents/com.user.timemachine-auto.plist https://raw.githubusercontent.com/YOUR_USERNAME/macos-timemachine-auto-backup/main/com.user.timemachine-auto.plist
```

Edit the plist to replace `YOUR_USERNAME` with your actual username:
```bash
nano ~/Library/LaunchAgents/com.user.timemachine-auto.plist
```

### 3. Grant Full Disk Access to Terminal

1. Go to **System Settings** > **Privacy & Security** > **Full Disk Access**
2. Click the **+** button
3. Navigate to **Applications > Utilities > Terminal** and add it

### 4. Load the LaunchAgent
```bash
launchctl load ~/Library/LaunchAgents/com.user.timemachine-auto.plist
```

### 5. Verify it's running
```bash
launchctl list | grep timemachine
```

You should see `com.user.timemachine-auto` in the output.

## Configuration

Edit `~/Library/Scripts/timemachine-auto.sh` to change settings:
```bash
BACKUP_THRESHOLD_DAYS=3  # Change to 7 for weekly backups, 1 for daily, etc.
```

After changing settings, reload the LaunchAgent:
```bash
launchctl unload ~/Library/LaunchAgents/com.user.timemachine-auto.plist
launchctl load ~/Library/LaunchAgents/com.user.timemachine-auto.plist
```

## Usage

Just plug in your Time Machine disk! The automation will:

1. Detect when the disk is mounted
2. Check if a backup is needed (based on `BACKUP_THRESHOLD_DAYS`)
3. Run the backup if needed
4. Eject the disk when done

## Logs

View the log anytime:
```bash
cat ~/Library/Logs/tm-auto-backup.log
```

Or use Console.app and search for "tm-auto-backup"

## Troubleshooting

### Script not running

Check if LaunchAgent is loaded:
```bash
launchctl list | grep timemachine
```

Check error logs:
```bash
cat ~/Library/Logs/tm-launchd-err.log
```

### Permission errors

Make sure Terminal has Full Disk Access (see Installation step 3)

### Disk not ejecting

Check if other apps are using the disk. The script will retry 3 times and send a notification if ejection fails.

## Uninstall
```bash
launchctl unload ~/Library/LaunchAgents/com.user.timemachine-auto.plist
rm ~/Library/LaunchAgents/com.user.timemachine-auto.plist
rm ~/Library/Scripts/timemachine-auto.sh
```

## License

MIT License - see LICENSE file

## Contributing

Pull requests welcome! Feel free to open issues for bugs or feature requests.
