#!/usr/bin/env bash
# uninstall.sh — removes backup-tm from the system
set -euo pipefail

BACKUP_PLIST_NAME="org.aborroy.backup-tm.backup.plist"
SWIFTBAR_PLIST_NAME="org.aborroy.backup-tm.swiftbar-autostart.plist"
LAUNCH_AGENTS="${HOME}/Library/LaunchAgents"
LAUNCHD_DOMAIN="gui/$(id -u)"

echo "==> backup-tm uninstaller"

# Stop and remove LaunchAgents
if [ -f "${LAUNCH_AGENTS}/${BACKUP_PLIST_NAME}" ]; then
  echo "--> Unloading backup LaunchAgent..."
  launchctl bootout "${LAUNCHD_DOMAIN}" "${LAUNCH_AGENTS}/${BACKUP_PLIST_NAME}" 2>/dev/null || true
  rm -f "${LAUNCH_AGENTS}/${BACKUP_PLIST_NAME}"
fi

if [ -f "${LAUNCH_AGENTS}/${SWIFTBAR_PLIST_NAME}" ]; then
  echo "--> Unloading SwiftBar autostart LaunchAgent..."
  launchctl bootout "${LAUNCHD_DOMAIN}" "${LAUNCH_AGENTS}/${SWIFTBAR_PLIST_NAME}" 2>/dev/null || true
  rm -f "${LAUNCH_AGENTS}/${SWIFTBAR_PLIST_NAME}"
fi

# Kill any running backup using the lock file PID (scoped — does not kill unrelated processes)
LOCK_PID_FILE="${HOME}/.local/state/backup.lock/pid"
if [[ -f "${LOCK_PID_FILE}" ]]; then
  BACKUP_PID=$(< "${LOCK_PID_FILE}")
  if kill -0 "${BACKUP_PID}" 2>/dev/null; then
    echo "--> Stopping running backup (PID ${BACKUP_PID})..."
    pkill -TERM -P "${BACKUP_PID}" 2>/dev/null || true
    kill -TERM "${BACKUP_PID}" 2>/dev/null || true
    sleep 2
  fi
fi

# Remove scripts
echo "--> Removing scripts..."
rm -f "${HOME}/scripts/backup.sh"
rm -f "${HOME}/scripts/backup-stop.sh"
rm -f "${HOME}/scripts/swiftbar-plugins/backup.30s.sh"
rm -rf "${HOME}/scripts/BackupRunner.app"

echo ""
echo "Done. SwiftBar and snapshots on the backup disk were left intact."
