#!/bin/bash

# Time Machine Auto-Backup v3 (lightweight)
#
# Behavior:
# - Triggered by launchd on mount/login.
# - Uses macOS-native backup timing via: tmutil startbackup --auto --block.
# - If a backup is already running, waits for completion.
# - Unmounts the Time Machine disk afterward.
# - If macOS does not start a backup, unmounts immediately.
#
# Notes:
# - This script only targets Local Time Machine destinations.
# - Designed for single-destination setups (one local Time Machine disk).
# - launchd StartOnMount triggers for all volume mounts; script exits fast when TM disk is absent.
# - Backup frequency comes from Time Machine settings (hourly/daily/weekly retention policy).
# - LaunchAgent commands:
#   unload: launchctl bootout "gui/$(id -u)"/com.user.timemachine-auto 2>/dev/null || true
#   load:   launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.user.timemachine-auto.plist" && launchctl enable "gui/$(id -u)"/com.user.timemachine-auto
#
# -------------------------------------------------------------------------

# User configuration:

# Optional destination UUID. Leave empty to auto-select when exactly one local destination is configured.
PREFERRED_DESTINATION_ID=""

# Poll interval while checking backup status.
BACKUP_POLL_SECONDS=15

# Maximum total wait for an active backup before leaving disk mounted.
BACKUP_MAX_WAIT_SECONDS=43200

# Delay after backup completes before unmount, to let final I/O settle.
POST_BACKUP_SETTLE_SECONDS=10

# Number of unmount retries before failure.
UNMOUNT_RETRY_ATTEMPTS=3

# Lock age threshold before a stale lock is reclaimed.
LOCK_STALE_SECONDS=21600

# How often to refresh lock metadata while waiting in long-running loops.
LOCK_REFRESH_SECONDS=600

# -------------------------------------------------------------------------

# Backward compatibility with previous config name.
if [ -n "${EJECT_RETRY_ATTEMPTS:-}" ]; then
    UNMOUNT_RETRY_ATTEMPTS="$EJECT_RETRY_ATTEMPTS"
fi

# Directory for persistent script state.
STATE_DIR="$HOME/Library/Application Support/TimeMachineAutoV3"
# Log destination file.
LOG_FILE="$HOME/Library/Logs/AutoTMLogs/tm-auto-backup-v3.log"
# Lock directory used for single-instance execution.
LOCK_DIR="$HOME/Library/Caches/com.user.timemachine-auto-v3.lock"
# File storing last processed mount signature + timestamp.
STATE_FILE="$STATE_DIR/last-processed-mount.state"

# Explicit PATH for launchd context.
PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"
# Stable locale to avoid parsing issues.
LC_ALL="C"
LANG="C"
export PATH LC_ALL LANG

# Lock metadata files stored inside LOCK_DIR.
LOCK_PID_FILE="$LOCK_DIR/pid"
LOCK_CREATED_FILE="$LOCK_DIR/created_epoch"

mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$STATE_DIR"
mkdir -p "$(dirname "$LOCK_DIR")"

log() {
    rotate_log_if_needed
    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

rotate_log_if_needed() {
    # Rotate when log reaches 1 MiB.
    local max_bytes=1048576
    # Keep up to 3 rotated logs: .1, .2, .3
    local keep_count=3
    local size
    local idx

    [ -f "$LOG_FILE" ] || return 0
    size=$(stat -f '%z' "$LOG_FILE" 2>/dev/null || true)
    [[ "$size" =~ ^[0-9]+$ ]] || return 0
    [ "$size" -lt "$max_bytes" ] && return 0

    for ((idx=keep_count-1; idx>=1; idx--)); do
        if [ -f "${LOG_FILE}.${idx}" ]; then
            mv -f "${LOG_FILE}.${idx}" "${LOG_FILE}.$((idx + 1))" 2>/dev/null || true
        fi
    done
    mv -f "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || true
}

escape_applescript_string() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

notify_user() {
    local message="$1"
    local title="${2:-Time Machine Auto-Backup}"
    local sound="$3"
    local message_escaped
    local title_escaped
    local sound_escaped
    local script

    message_escaped=$(escape_applescript_string "$message")
    title_escaped=$(escape_applescript_string "$title")

    if [ -n "$sound" ]; then
        sound_escaped=$(escape_applescript_string "$sound")
        script="display notification \"$message_escaped\" with title \"$title_escaped\" sound name \"$sound_escaped\""
    else
        script="display notification \"$message_escaped\" with title \"$title_escaped\""
    fi

    if ! osascript -e "$script" >/dev/null 2>&1; then
        log "WARNING: Failed to display notification: $message"
    fi
}

validate_numeric_configs() {
    if ! [[ "$BACKUP_POLL_SECONDS" =~ ^[0-9]+$ ]] || [ "$BACKUP_POLL_SECONDS" -lt 1 ]; then
        log "WARNING: Invalid BACKUP_POLL_SECONDS ($BACKUP_POLL_SECONDS); using 15"
        BACKUP_POLL_SECONDS=15
    fi
    if ! [[ "$BACKUP_MAX_WAIT_SECONDS" =~ ^[0-9]+$ ]] || [ "$BACKUP_MAX_WAIT_SECONDS" -lt "$BACKUP_POLL_SECONDS" ]; then
        log "WARNING: Invalid BACKUP_MAX_WAIT_SECONDS ($BACKUP_MAX_WAIT_SECONDS); using 43200"
        BACKUP_MAX_WAIT_SECONDS=43200
    fi
    if ! [[ "$POST_BACKUP_SETTLE_SECONDS" =~ ^[0-9]+$ ]] || [ "$POST_BACKUP_SETTLE_SECONDS" -lt 0 ]; then
        log "WARNING: Invalid POST_BACKUP_SETTLE_SECONDS ($POST_BACKUP_SETTLE_SECONDS); using 10"
        POST_BACKUP_SETTLE_SECONDS=10
    fi
    if ! [[ "$UNMOUNT_RETRY_ATTEMPTS" =~ ^[0-9]+$ ]] || [ "$UNMOUNT_RETRY_ATTEMPTS" -lt 1 ]; then
        log "WARNING: Invalid UNMOUNT_RETRY_ATTEMPTS ($UNMOUNT_RETRY_ATTEMPTS); using 3"
        UNMOUNT_RETRY_ATTEMPTS=3
    fi
    if ! [[ "$LOCK_STALE_SECONDS" =~ ^[0-9]+$ ]] || [ "$LOCK_STALE_SECONDS" -lt 60 ]; then
        log "WARNING: Invalid LOCK_STALE_SECONDS ($LOCK_STALE_SECONDS); using 21600"
        LOCK_STALE_SECONDS=21600
    fi
    if ! [[ "$LOCK_REFRESH_SECONDS" =~ ^[0-9]+$ ]] || [ "$LOCK_REFRESH_SECONDS" -lt 60 ]; then
        log "WARNING: Invalid LOCK_REFRESH_SECONDS ($LOCK_REFRESH_SECONDS); using 600"
        LOCK_REFRESH_SECONDS=600
    fi

    if [ "$BACKUP_POLL_SECONDS" -gt 300 ]; then
        log "WARNING: BACKUP_POLL_SECONDS too large ($BACKUP_POLL_SECONDS); capping at 300"
        BACKUP_POLL_SECONDS=300
    fi
    if [ "$BACKUP_MAX_WAIT_SECONDS" -gt 86400 ]; then
        log "WARNING: BACKUP_MAX_WAIT_SECONDS too large ($BACKUP_MAX_WAIT_SECONDS); capping at 86400"
        BACKUP_MAX_WAIT_SECONDS=86400
    fi
    if [ "$POST_BACKUP_SETTLE_SECONDS" -gt 300 ]; then
        log "WARNING: POST_BACKUP_SETTLE_SECONDS too large ($POST_BACKUP_SETTLE_SECONDS); capping at 300"
        POST_BACKUP_SETTLE_SECONDS=300
    fi
    if [ "$UNMOUNT_RETRY_ATTEMPTS" -gt 10 ]; then
        log "WARNING: UNMOUNT_RETRY_ATTEMPTS too large ($UNMOUNT_RETRY_ATTEMPTS); capping at 10"
        UNMOUNT_RETRY_ATTEMPTS=10
    fi
    if [ "$LOCK_STALE_SECONDS" -gt 604800 ]; then
        log "WARNING: LOCK_STALE_SECONDS too large ($LOCK_STALE_SECONDS); capping at 604800"
        LOCK_STALE_SECONDS=604800
    fi
    if [ "$LOCK_REFRESH_SECONDS" -gt "$LOCK_STALE_SECONDS" ]; then
        log "WARNING: LOCK_REFRESH_SECONDS ($LOCK_REFRESH_SECONDS) exceeds LOCK_STALE_SECONDS ($LOCK_STALE_SECONDS); using 600"
        LOCK_REFRESH_SECONDS=600
    fi
}

tmutil_permission_error() {
    printf '%s\n' "$1" | grep -Eqi 'Full Disk Access|Operation not permitted|not authorized|not privileged|permission denied|authorization denied|access denied|insufficient permissions?'
}

verify_tmutil_access() {
    local output=""
    local status=0

    output=$(tmutil version 2>&1)
    status=$?
    if [ "$status" -ne 0 ]; then
        log "ERROR: tmutil command failed ($status): $output"
        notify_user "Time Machine Auto-Backup needs Full Disk Access. Add Terminal/iTerm/your launcher in System Settings > Privacy & Security > Full Disk Access, then RESTART the app to apply changes." "Time Machine Auto-Backup" "Basso"
        return 1
    fi

    output=$(tmutil destinationinfo -X 2>&1)
    status=$?
    if [ "$status" -ne 0 ] && tmutil_permission_error "$output"; then
        log "ERROR: Time Machine destination query blocked by Full Disk Access: $output"
        notify_user "Time Machine Auto-Backup needs Full Disk Access. Add Terminal/iTerm/your launcher in System Settings > Privacy & Security > Full Disk Access, then RESTART the app to apply changes." "Time Machine Auto-Backup" "Basso"
        return 1
    fi

    output=$(tmutil status -X 2>&1)
    status=$?
    if [ "$status" -ne 0 ] && tmutil_permission_error "$output"; then
        log "ERROR: Time Machine status query blocked by Full Disk Access: $output"
        notify_user "Time Machine Auto-Backup needs Full Disk Access. Add Terminal/iTerm/your launcher in System Settings > Privacy & Security > Full Disk Access, then RESTART the app to apply changes." "Time Machine Auto-Backup" "Basso"
        return 1
    fi

    return 0
}

normalize_uuid() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

diskutil_info_plist() {
    diskutil info -plist "$1" 2>/dev/null
}

extract_plist_value() {
    local key="$1"
    plutil -extract "$key" raw -o - - 2>/dev/null
}

mount_point_for_target() {
    local target="$1"
    local disk_info
    local mount_point

    disk_info=$(diskutil_info_plist "$target") || return 1
    [ -n "$disk_info" ] || return 1

    mount_point=$(printf '%s' "$disk_info" | extract_plist_value MountPoint)
    [ -n "$mount_point" ] || return 1

    printf '%s\n' "$mount_point"
}

is_volume_mounted() {
    local target="$1"
    local mount_point

    mount_point=$(mount_point_for_target "$target") || return 1
    if [[ "$target" == /* ]] && [ "$mount_point" != "$target" ]; then
        return 1
    fi
    return 0
}

read_destination_info() {
    tmutil destinationinfo -X 2>/dev/null
}

append_destination_record() {
    local id="$1"
    local name="$2"
    local kind="$3"
    local mount_point="$4"

    DEST_IDS+=("$id")
    DEST_NAMES+=("$name")
    DEST_KINDS+=("$kind")
    DEST_MOUNTS+=("$mount_point")
}

parse_destinations_from_info() {
    local info="$1"
    local idx=0
    local destination_dict
    local current_id
    local current_name
    local current_kind
    local current_mount

    DEST_IDS=()
    DEST_NAMES=()
    DEST_KINDS=()
    DEST_MOUNTS=()

    while :; do
        destination_dict=$(printf '%s' "$info" | plutil -extract "Destinations.$idx" xml1 -o - - 2>/dev/null || true)
        if [ -z "$destination_dict" ]; then
            break
        fi

        current_id=$(printf '%s' "$destination_dict" | plutil -extract ID raw -o - - 2>/dev/null || true)
        current_name=$(printf '%s' "$destination_dict" | plutil -extract Name raw -o - - 2>/dev/null || true)
        current_kind=$(printf '%s' "$destination_dict" | plutil -extract Kind raw -o - - 2>/dev/null || true)
        current_mount=$(printf '%s' "$destination_dict" | plutil -extract "Mount Point" raw -o - - 2>/dev/null || true)

        append_destination_record "$current_id" "$current_name" "$current_kind" "$current_mount"
        idx=$((idx + 1))
    done
}

resolve_mounted_path_for_destination() {
    local idx="$1"
    local mount_point

    mount_point="${DEST_MOUNTS[$idx]}"
    if [ -n "$mount_point" ] && is_volume_mounted "$mount_point"; then
        printf '%s\n' "$mount_point"
        return 0
    fi

    if [ -n "${DEST_NAMES[$idx]}" ]; then
        mount_point=$(mount_point_for_target "${DEST_NAMES[$idx]}" 2>/dev/null || true)
        if [ -n "$mount_point" ] && is_volume_mounted "$mount_point"; then
            printf '%s\n' "$mount_point"
            return 0
        fi
    fi

    if [ -n "${DEST_IDS[$idx]}" ]; then
        mount_point=$(mount_point_for_target "${DEST_IDS[$idx]}" 2>/dev/null || true)
        if [ -n "$mount_point" ] && is_volume_mounted "$mount_point"; then
            printf '%s\n' "$mount_point"
            return 0
        fi
    fi

    return 1
}

find_destination_index() {
    local preferred_id="$1"
    local preferred_upper=""
    local idx
    local local_count=0
    local local_idx=""
    local mounted_local_count=0
    local mounted_local_idx=""

    if [ "${#DEST_IDS[@]}" -eq 0 ]; then
        return 1
    fi

    if [ -n "$preferred_id" ]; then
        preferred_upper=$(normalize_uuid "$preferred_id")
        for idx in "${!DEST_IDS[@]}"; do
            if [ "$(normalize_uuid "${DEST_IDS[$idx]}")" = "$preferred_upper" ]; then
                if [ "${DEST_KINDS[$idx]}" != "Local" ]; then
                    return 3
                fi
                printf '%s\n' "$idx"
                return 0
            fi
        done
        return 1
    fi

    for idx in "${!DEST_IDS[@]}"; do
        if [ "${DEST_KINDS[$idx]}" != "Local" ]; then
            continue
        fi
        local_count=$((local_count + 1))
        if [ -z "$local_idx" ]; then
            local_idx="$idx"
        fi
        if resolve_mounted_path_for_destination "$idx" >/dev/null 2>&1; then
            mounted_local_count=$((mounted_local_count + 1))
            mounted_local_idx="$idx"
        fi
    done

    if [ "$local_count" -eq 0 ]; then
        return 1
    fi

    if [ "$local_count" -eq 1 ]; then
        printf '%s\n' "$local_idx"
        return 0
    fi

    if [ "$mounted_local_count" -eq 1 ]; then
        printf '%s\n' "$mounted_local_idx"
        return 0
    fi

    return 2
}

backup_in_progress() {
    local status_xml
    local running

    # Intentionally global status check for single-destination setups.
    # Any running backup means "leave mounted for safety."
    status_xml=$(tmutil status -X 2>/dev/null || true)
    if [ -n "$status_xml" ]; then
        running=$(printf '%s' "$status_xml" | plutil -extract Running raw -o - - 2>/dev/null || true)
        case "$running" in
            1|true|TRUE|yes|YES)
                return 0
                ;;
            0|false|FALSE|no|NO)
                return 1
                ;;
        esac
    fi

    tmutil status 2>/dev/null | grep -q "Running = 1;"
}

wait_for_backup_completion() {
    local waited=0
    local since_refresh=0

    if ! backup_in_progress; then
        return 0
    fi

    log "Backup running; waiting up to ${BACKUP_MAX_WAIT_SECONDS}s for completion"
    while backup_in_progress; do
        if [ "$waited" -ge "$BACKUP_MAX_WAIT_SECONDS" ]; then
            log "Backup still running after ${waited}s; leaving disk mounted"
            return 1
        fi
        sleep "$BACKUP_POLL_SECONDS"
        waited=$((waited + BACKUP_POLL_SECONDS))
        since_refresh=$((since_refresh + BACKUP_POLL_SECONDS))
        if [ "$since_refresh" -ge "$LOCK_REFRESH_SECONDS" ]; then
            write_lock_metadata
            since_refresh=0
        fi
    done

    log "Backup finished after ${waited}s"
    return 0
}

attempt_unmount() {
    local mount_path="$1"
    local attempt

    for ((attempt=1; attempt<=UNMOUNT_RETRY_ATTEMPTS; attempt++)); do
        if backup_in_progress; then
            log "Backup resumed during unmount attempts; leaving disk mounted"
            return 2
        fi

        if ! is_volume_mounted "$mount_path"; then
            return 0
        fi

        log "Unmount attempt $attempt/$UNMOUNT_RETRY_ATTEMPTS for $mount_path"
        if diskutil unmount "$mount_path" >/dev/null 2>&1; then
            sleep 1
            if ! is_volume_mounted "$mount_path"; then
                return 0
            fi
        fi
        sleep 2
    done

    return 1
}

write_last_signature() {
    local signature="$1"
    printf 'signature=%s\nepoch=%s\n' "$signature" "$(date +%s)" > "$STATE_FILE"
}

safe_remove_lock_dir() {
    case "$LOCK_DIR" in
        "$HOME/Library/Caches/com.user.timemachine-auto-v3.lock")
            ;;
        *)
            log "Refusing unsafe lock cleanup path: $LOCK_DIR"
            return 1
            ;;
    esac

    if [ ! -d "$LOCK_DIR" ] || [ -L "$LOCK_DIR" ]; then
        log "Refusing lock cleanup; path is missing or symlinked: $LOCK_DIR"
        return 1
    fi

    rm -rf "$LOCK_DIR" 2>/dev/null || return 1
    return 0
}

write_lock_metadata() {
    printf '%s\n' "$$" > "$LOCK_PID_FILE"
    printf '%s\n' "$(date +%s)" > "$LOCK_CREATED_FILE"
}

lock_pid_looks_like_tm_script() {
    local pid="$1"
    local cmdline

    cmdline=$(ps -p "$pid" -o command= 2>/dev/null || true)
    [ -n "$cmdline" ] || return 1

    case "$cmdline" in
        *timemachine-auto.sh*)
            return 0
            ;;
    esac
    return 1
}

acquire_lock() {
    local existing_pid=""
    local created_epoch=""
    local now_epoch
    local lock_age=""

    if mkdir "$LOCK_DIR" 2>/dev/null; then
        write_lock_metadata
        return 0
    fi

    if [ ! -d "$LOCK_DIR" ]; then
        log "Lock directory create failed unexpectedly; exiting"
        return 1
    fi

    now_epoch=$(date +%s)

    if [ -f "$LOCK_PID_FILE" ]; then
        existing_pid=$(tr -d '[:space:]' < "$LOCK_PID_FILE" 2>/dev/null)
    fi

    if [[ "$existing_pid" =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
        if lock_pid_looks_like_tm_script "$existing_pid"; then
            log "Another run is already in progress (pid: $existing_pid); exiting"
            return 1
        fi
        log "Lock PID $existing_pid is alive but does not match script command; treating lock as stale"
    fi

    if [ -f "$LOCK_CREATED_FILE" ]; then
        created_epoch=$(tr -d '[:space:]' < "$LOCK_CREATED_FILE" 2>/dev/null)
    else
        created_epoch=$(stat -f '%m' "$LOCK_DIR" 2>/dev/null || true)
    fi

    if [[ "$created_epoch" =~ ^[0-9]+$ ]]; then
        lock_age=$((now_epoch - created_epoch))
        if [ -z "$existing_pid" ] && [ "$lock_age" -lt 60 ]; then
            log "Lock exists without PID and is ${lock_age}s old; assuming setup race, exiting"
            return 1
        fi
        if [ -z "$existing_pid" ] && [ "$lock_age" -ge 60 ]; then
            log "Lock exists without PID and is ${lock_age}s old; treating as stale"
        fi
    fi

    log "Removing stale lock (pid: ${existing_pid:-missing}, age: ${lock_age:-unknown}s)"
    if ! safe_remove_lock_dir; then
        log "Failed to remove stale lock directory; exiting"
        return 1
    fi

    if mkdir "$LOCK_DIR" 2>/dev/null; then
        write_lock_metadata
        return 0
    fi

    log "Could not acquire lock; exiting"
    return 1
}

cleanup() {
    rm -f "$LOCK_PID_FILE" "$LOCK_CREATED_FILE" 2>/dev/null
    rmdir "$LOCK_DIR" 2>/dev/null || true
}

validate_numeric_configs

if ! command -v tmutil >/dev/null 2>&1 || ! command -v diskutil >/dev/null 2>&1 || ! command -v plutil >/dev/null 2>&1; then
    log "Missing required command(s) tmutil/diskutil/plutil; exiting"
    exit 1
fi

if ! verify_tmutil_access; then
    exit 1
fi

if [ -n "$PREFERRED_DESTINATION_ID" ]; then
    if ! [[ "$PREFERRED_DESTINATION_ID" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
        log "ERROR: PREFERRED_DESTINATION_ID is not a valid UUID format: $PREFERRED_DESTINATION_ID"
        log "Expected format: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX (hex digits)"
        log "Run 'tmutil destinationinfo' to get valid destination IDs"
        notify_user "Invalid PREFERRED_DESTINATION_ID format in script. Check logs for details." "Time Machine Auto-Backup" "Basso"
        exit 1
    fi
fi

if ! acquire_lock; then
    exit 0
fi
trap cleanup INT TERM EXIT

DEST_INFO=$(read_destination_info)
if [ -z "$DEST_INFO" ]; then
    log "No Time Machine destination info available; exiting"
    exit 0
fi

parse_destinations_from_info "$DEST_INFO"
if [ "${#DEST_IDS[@]}" -eq 0 ]; then
    log "No destinations parsed from tmutil output; exiting"
    exit 0
fi

DEST_INDEX=""
if [ -n "$PREFERRED_DESTINATION_ID" ]; then
    DEST_INDEX=$(find_destination_index "$PREFERRED_DESTINATION_ID" 2>/dev/null)
    DEST_STATUS=$?
    if [ "$DEST_STATUS" -ne 0 ]; then
        if [ "$DEST_STATUS" -eq 3 ]; then
            log "Preferred destination is not Local (id: $PREFERRED_DESTINATION_ID); exiting"
            notify_user "Preferred Time Machine destination is not a local disk. Update PREFERRED_DESTINATION_ID." "Time Machine Auto-Backup" "Basso"
            exit 0
        fi
        log "Preferred destination ID not found ($PREFERRED_DESTINATION_ID); exiting"
        exit 0
    fi
else
    DEST_INDEX=$(find_destination_index "" 2>/dev/null)
    DEST_STATUS=$?
    if [ "$DEST_STATUS" -ne 0 ]; then
        if [ "$DEST_STATUS" -eq 2 ]; then
            log "Multiple local destinations detected and selection is ambiguous; set PREFERRED_DESTINATION_ID"
            notify_user "Multiple local Time Machine destinations were detected. Set PREFERRED_DESTINATION_ID in the script." "Time Machine Auto-Backup" "Basso"
            exit 0
        fi
        log "No suitable local destination found; exiting"
        exit 0
    fi
fi

SELECTED_DEST_ID="${DEST_IDS[$DEST_INDEX]}"
SELECTED_DEST_NAME="${DEST_NAMES[$DEST_INDEX]}"
TM_MOUNT=$(resolve_mounted_path_for_destination "$DEST_INDEX" 2>/dev/null || true)

if [ -z "$SELECTED_DEST_ID" ]; then
    log "Selected destination has no ID; exiting"
    exit 0
fi

if [ -z "$TM_MOUNT" ]; then
    exit 0
fi

MOUNT_INFO=$(diskutil_info_plist "$TM_MOUNT" || true)
MOUNT_READ_ONLY=""
if [ -n "$MOUNT_INFO" ]; then
    MOUNT_READ_ONLY=$(printf '%s' "$MOUNT_INFO" | extract_plist_value ReadOnly)
fi

if [ ! -r "$TM_MOUNT" ]; then
    log "Mount point is not readable: $TM_MOUNT"
    notify_user "Time Machine disk is mounted but not readable. Check disk access and permissions." "Time Machine Auto-Backup" "Basso"
    exit 1
fi

case "$MOUNT_READ_ONLY" in
    1|[1-9][0-9]*|true|TRUE|True|yes|YES|Yes)
        log "Mount point is read-only: $TM_MOUNT"
        notify_user "Time Machine disk is mounted read-only. Repair the disk before automatic backups." "Time Machine Auto-Backup" "Basso"
        exit 1
        ;;
esac

MOUNT_INODE=$(stat -f '%i' "$TM_MOUNT" 2>/dev/null)
if ! [[ "$MOUNT_INODE" =~ ^[0-9]+$ ]]; then
    MOUNT_INODE="ino-fallback-$(date +%s)-$$-$RANDOM"
fi
# Include inode so unplug/replug is treated as a new mount session.
CURRENT_SIGNATURE="${SELECTED_DEST_ID}|${TM_MOUNT}|${MOUNT_INODE}"

log "Destination mounted (name: ${SELECTED_DEST_NAME:-unknown}, id: $SELECTED_DEST_ID) at $TM_MOUNT"

START_OUTPUT=""
START_STATUS=0
BACKUP_COMPLETED=false

if backup_in_progress; then
    log "Backup already running before auto trigger; waiting for completion"
    if ! wait_for_backup_completion; then
        notify_user "Backup is taking unusually long. Disk was left mounted for safety." "Time Machine Auto-Backup" "Basso"
        exit 1
    fi
    BACKUP_COMPLETED=true
else
    START_OUTPUT=$(tmutil startbackup --auto --block --destination "$SELECTED_DEST_ID" 2>&1)
    START_STATUS=$?

    if [ "$START_STATUS" -eq 0 ]; then
        log "tmutil auto decision completed"
    else
        if printf '%s\n' "$START_OUTPUT" | grep -Eqi 'already running|Backup session is already running'; then
            log "tmutil reported an already-running backup; waiting for completion"
            if ! wait_for_backup_completion; then
                notify_user "Backup is taking unusually long. Disk was left mounted for safety." "Time Machine Auto-Backup" "Basso"
                exit 1
            fi
            BACKUP_COMPLETED=true
        elif tmutil_permission_error "$START_OUTPUT"; then
            log "ERROR: Time Machine command blocked by Full Disk Access; leaving disk mounted"
            notify_user "Time Machine Auto-Backup needs Full Disk Access to run in this context." "Time Machine Auto-Backup" "Basso"
            exit 1
        else
            log "WARNING: tmutil startbackup --auto --block returned $START_STATUS; output: $START_OUTPUT"
        fi
    fi
fi

# Final safety check in case backup started/resumed right around tmutil return.
# Safety check: In rare cases, --auto may start a backup that begins
# just after --block returns. Check one more time before unmounting.
if backup_in_progress; then
    log "Backup running after auto decision; waiting for completion"
    if ! wait_for_backup_completion; then
        notify_user "Backup is taking unusually long. Disk was left mounted for safety." "Time Machine Auto-Backup" "Basso"
        exit 1
    fi
    BACKUP_COMPLETED=true
fi

if [ "$BACKUP_COMPLETED" = "true" ]; then
    if [ "$POST_BACKUP_SETTLE_SECONDS" -gt 0 ]; then
        log "Backup path completed; settling for ${POST_BACKUP_SETTLE_SECONDS}s before unmount"
        sleep "$POST_BACKUP_SETTLE_SECONDS"
        if backup_in_progress; then
            log "Backup resumed during settle delay; leaving disk mounted"
            exit 0
        fi
    fi
    log "Backup completed; proceeding to unmount"
else
    log "No backup active after auto decision; proceeding to unmount"
fi

CURRENT_MOUNT=$(resolve_mounted_path_for_destination "$DEST_INDEX" 2>/dev/null || true)
if [ -n "$CURRENT_MOUNT" ] && [ "$CURRENT_MOUNT" != "$TM_MOUNT" ]; then
    log "Mount point changed from $TM_MOUNT to $CURRENT_MOUNT; skipping unmount for safety"
    exit 0
fi

if ! is_volume_mounted "$TM_MOUNT"; then
    log "Disk already unmounted before unmount step"
    write_last_signature "$CURRENT_SIGNATURE"
    exit 0
fi

attempt_unmount "$TM_MOUNT"
UNMOUNT_RESULT=$?

if [ "$UNMOUNT_RESULT" -eq 0 ]; then
    log "Disk unmounted successfully"
    if backup_in_progress; then
        log "WARNING: Backup reported running immediately after unmount"
    fi
    write_last_signature "$CURRENT_SIGNATURE"
    exit 0
fi

if [ "$UNMOUNT_RESULT" -eq 2 ]; then
    log "Backup resumed during unmount attempts; leaving disk mounted"
    exit 0
fi

log "Failed to unmount disk after $UNMOUNT_RETRY_ATTEMPTS attempts"
write_last_signature "$CURRENT_SIGNATURE"
notify_user "Time Machine disk could not be unmounted and will be retried on next run." "Time Machine Auto-Backup" "Basso"
exit 1
