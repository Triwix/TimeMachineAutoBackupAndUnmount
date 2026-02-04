# Time Machine Auto-Backup

- Runs a backup when your Time Machine disk is mounted
- Only backs up if it's been more than 3 days since the last backup (configurable)
- Automatically ejects the disk when done
- Shows notifications for backup status
- Logs all activity

## Files
1. timemachine-auto.sh -- This is the logic that handles whether or not to backup, and eject the time machine disk.
3. com.user.timemachine-auto.plist -- This file defines the triggers to run the script (login or disk mount).


## Installation

1. **Clone or download this repository**

2. **Make the script executable**
   ```bash
   chmod +x timemachine-auto.sh
   ```
   
3. **Update the plist file path**
   
   Open `com.user.timemachine-auto.plist` and replace `YOUR_USERNAME` with your actual macOS username in all three locations for proper log functionality.
   
4. **Copy files to the correct locations**
   ```bash
   # Copy the script
   cp timemachine-auto.sh ~/Library/Scripts/
   
   # Copy the LaunchAgent
   cp com.user.timemachine-auto.plist ~/Library/LaunchAgents/
   ```
   
5. **Load the LaunchAgent**
   ```bash
   launchctl load ~/Library/LaunchAgents/com.user.timemachine-auto.plist
   ```
   The script `timemachine-auto.sh` will now execute automatically

   To disable the LaunchAgent:
   ```bash
   launchctl unload ~/Library/LaunchAgents/com.user.timemachine-auto.plist
   ```

## Configuration

Edit `~/Library/Scripts/timemachine-auto.sh` to change settings:

- `BACKUP_THRESHOLD_DAYS=3` - Minimum days between backups (default: 3)

## Usage

Once installed, the script runs automatically when either occurs:
- Your Time Machine disk is mounted
- You log in (if the disk is already connected)

Just plug in your Time Machine backup disk and it will handle the rest!

## How It Works

1. Script waits 5 seconds for disk to fully mount
2. Checks if Time Machine destination is available
3. Gets the last backup timestamp from the backup folder name
4. Compares against threshold (default: 3 days)
5. Runs backup if needed (or skips if recent)
6. Ejects disk automatically
7. Sends notifications for completion/errors

## Logs

Log Location: ~/Library/Logs/AutoTMLogs/tm-auto-backup.log

Check backup activity by opening the log file, checking tm-auto-backup.log in the Console app, or through Terminal with:

```bash
tail -f ~/Library/Logs/AutoTMLogs/tm-auto-backup.log
```

## Uninstall

```bash
# Stop the service
launchctl unload ~/Library/LaunchAgents/com.user.timemachine-auto.plist

# Remove files
rm ~/Library/LaunchAgents/com.user.timemachine-auto.plist
rm ~/Library/Scripts/timemachine-auto.sh
rm -rf ~/Library/Logs/AutoTMLogs/
```

## Troubleshooting

**Script not running?**
- Verify Time Machine is configured and the disk is currently mounted.
- Check if the LaunchAgent is loaded: `launchctl list | grep timemachine`
- Verify the script path in the plist file matches your username
- Check logs for errors: `cat ~/Library/Logs/AutoTMLogs/tm-auto-backup.log`
- Full-Disk Access for Terminal might be needed.

**Disk not ejecting?**
- The disk may still be in use by another application
- Check the logs to see if Time Machine completed successfully

## Requirements

- macOS with Time Machine configured
- Time Machine backup disk

## License

MIT
