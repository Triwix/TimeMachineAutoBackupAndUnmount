# Time Machine Auto-Backup v3

This automation is designed for **one local Time Machine destination**.

Behavior:
- `launchd` triggers on login and any volume mount.
- The script asks macOS to decide backup timing with `tmutil startbackup --auto --block`.
- If macOS starts (or is already running) a backup, the script waits for completion.
- If macOS does not start a backup, the script unmounts the Time Machine disk.

## Requirements
- macOS 10.13 (High Sierra) or later
- Time Machine already configured with at least one local destination
- Full Disk Access granted to the process running the script
- Script runs as a **per-user LaunchAgent** (not a daemon).

## Install
1. Copy script:
```bash
mkdir -p "$HOME/Library/Scripts"
cp '~/Documents/Tech/Time Machine Automation/Versions/v3/timemachine-auto.sh' "$HOME/Library/Scripts/timemachine-auto.sh"
chmod +x "$HOME/Library/Scripts/timemachine-auto.sh"
```
2. Copy LaunchAgent plist:
```bash
mkdir -p "$HOME/Library/LaunchAgents"
cp '~/Documents/Tech/Time Machine Automation/Versions/v3/com.user.timemachine-auto.plist' "$HOME/Library/LaunchAgents/com.user.timemachine-auto.plist"
```
3. Load/reload agent:
```bash
launchctl bootout "gui/$(id -u)"/com.user.timemachine-auto 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.user.timemachine-auto.plist"
launchctl enable "gui/$(id -u)"/com.user.timemachine-auto
```

## Full Disk Access
Grant Full Disk Access to the app/process context launching this script (for example Terminal, iTerm, or your automation host):
- System Settings -> Privacy & Security -> Full Disk Access
- Add the app, then restart that app/session.

Common related errors in log output:
- `Operation not permitted`
- `Full Disk Access`

## Destination ID (optional)
If you set `PREFERRED_DESTINATION_ID`:
```bash
tmutil destinationinfo
```
Use the `ID` value from output.
The value must be a full UUID in this format:
`XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX` (hex digits).
If the format is invalid, the script logs an error, shows a notification, and exits.

## Multiple Destinations

This script is designed for single local Time Machine destination setups.

If you have multiple local destinations:
- Set `PREFERRED_DESTINATION_ID` in the script to specify which one to manage
- Get the ID with: `tmutil destinationinfo`

If you have network destinations (iCloud, Time Capsule, NAS):
- The script will wait for ANY backup to complete, not just the local disk backup
- This is safe but may keep the local disk mounted longer than necessary
- Set `PREFERRED_DESTINATION_ID` if you want to manage only one local destination

## StartOnMount Note
`StartOnMount` triggers for **all** mounted volumes (USB, DMG, network, etc.).
The script exits quickly when the configured local Time Machine disk is not mounted.

## First Run vs Later Runs
- First run after mount: evaluates destination, asks macOS auto-policy, waits if backup starts, then unmounts.
- If another instance is already running, lock protection makes the new trigger exit.
- If a stale lock exists without a PID and is at least 60 seconds old, the script reclaims it and continues.

## Troubleshooting
Check LaunchAgent status:
```bash
launchctl print "gui/$(id -u)"/com.user.timemachine-auto
```

Check script process:
```bash
ps aux | grep '[t]imemachine-auto.sh'
```

Tail logs:
```bash
tail -f "$HOME/Library/Logs/AutoTMLogs/tm-auto-backup-v3.log"
```

Manual test run:
```bash
"$HOME/Library/Scripts/timemachine-auto.sh"
```

If unmount keeps failing, find open files:
```bash
lsof +D "/Volumes/<YourTMVolumeName>"
```

Reset local state/lock:
```bash
rm -f "$HOME/Library/Application Support/TimeMachineAutoV3/last-processed-mount.state"
rm -rf "$HOME/Library/Caches/com.user.timemachine-auto-v3.lock"
```

## Configuration Examples
Default (good for most users):
```bash
BACKUP_POLL_SECONDS=15
BACKUP_MAX_WAIT_SECONDS=43200
POST_BACKUP_SETTLE_SECONDS=10
UNMOUNT_RETRY_ATTEMPTS=3
LOCK_STALE_SECONDS=21600
LOCK_REFRESH_SECONDS=600
```

If you want less frequent status polling:
```bash
BACKUP_POLL_SECONDS=30
```

If you temporarily run a very large first backup:
```bash
BACKUP_MAX_WAIT_SECONDS=86400
LOCK_STALE_SECONDS=86400
```
