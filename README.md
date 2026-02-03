# Time Machine Auto-Backup

- Runs a backup when your Time Machine disk is mounted
- Only backs up if it's been more than 3 days since the last backup
- Automatically ejects the disk when done
- Shows notifications for backup status
- Logs all activity

## Installation

1. **Clone or download this repository**
   ```bash
   git clone https://github.com/Triwix/TimeMachineAutoBackupAndUnmount.git
   cd timemachine-auto
   ```

2. **Make the script executable**
   ```bash
   chmod +x timemachine-auto.sh
   ```

3. **Copy files to the correct locations**
   ```bash
   # Copy the script
   cp timemachine-auto.sh ~/Library/Scripts/
   
   # Copy the LaunchAgent
   cp com.user.timemachine-auto.plist ~/Library/LaunchAgents/
   ```

4. **Update the plist file path**
   
   Open `~/Library/LaunchAgents/com.user.timemachine-auto.plist` and replace `YOUR_USERNAME` with your actual macOS username:
   ```bash
   # Quick way to do this:
   sed -i '' "s/YOUR_USERNAME/$USER/g" ~/Library/LaunchAgents/com.user.timemachine-auto.plist
   ```

5. **Load the LaunchAgent**
   ```bash
   launchctl load ~/Library/LaunchAgents/com.user.timemachine-auto.plist
   ```

## Configuration

Edit `~/Library/Scripts/timemachine-auto.sh` to change settings:

- `BACKUP_THRESHOLD_DAYS=3` - Minimum days between backups (default: 3)

## Usage

Once installed, the script runs automatically when:
- Your Time Machine disk is mounted
- You log in (if the disk is already connected)

Just plug in your Time Machine backup disk and it will handle the rest!

## Logs

Check backup activity:
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
