#!/usr/bin/env bash
# install.sh — sets up backup-tm on a fresh macOS machine
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${HOME}/scripts"
PLUGINS_DIR="${HOME}/scripts/swiftbar-plugins"
RUNNER_APP_NAME="BackupRunner.app"
BACKUP_PLIST_NAME="org.aborroy.backup-tm.backup.plist"
SWIFTBAR_PLIST_NAME="org.aborroy.backup-tm.swiftbar-autostart.plist"
LAUNCH_AGENTS="${HOME}/Library/LaunchAgents"
LAUNCHD_DOMAIN="gui/$(id -u)"
CONFIG_DIR="${HOME}/.config/backup-tm"
CONFIG_FILE="${CONFIG_DIR}/config"

echo "==> backup-tm installer"

# ── 0. Config file ────────────────────────────────────────────
if [[ -f "${CONFIG_FILE}" ]]; then
  echo "--> Config already exists at ${CONFIG_FILE}, skipping creation."
else
  read -r -p "Enter backup volume name (mounted at /Volumes/<name>) [BackupDisk]: " VOLUME_NAME_INPUT
  VOLUME_NAME_INPUT="${VOLUME_NAME_INPUT:-BackupDisk}"
  echo "Enter disk identifier for APFS-encrypted volume (e.g. disk2s1)."
  echo "  Find it with: diskutil list | grep -B1 ${VOLUME_NAME_INPUT}"
  read -r -p "  Disk identifier (empty if unencrypted or mounted manually): " DISK_ID_INPUT
  read -r -p "Enter daily backup hour (0-23) [14]: " SCHEDULE_HOUR_INPUT
  SCHEDULE_HOUR_INPUT="${SCHEDULE_HOUR_INPUT:-14}"
  read -r -p "Enter daily backup minute (0-59) [0]: " SCHEDULE_MINUTE_INPUT
  SCHEDULE_MINUTE_INPUT="${SCHEDULE_MINUTE_INPUT:-0}"
  mkdir -p "${CONFIG_DIR}"
  cat > "${CONFIG_FILE}" <<EOF
# backup-tm configuration
# Name of the external backup volume (must be mounted at /Volumes/<VOLUME_NAME>)
VOLUME_NAME="${VOLUME_NAME_INPUT}"

# Disk identifier for APFS-encrypted volumes (e.g. disk2s1).
# Leave empty if the drive is unencrypted or must be mounted manually.
DISK_IDENTIFIER="${DISK_ID_INPUT}"

# Daily backup schedule
SCHEDULE_HOUR="${SCHEDULE_HOUR_INPUT}"
SCHEDULE_MINUTE="${SCHEDULE_MINUTE_INPUT}"
EOF
  echo "--> Config written to ${CONFIG_FILE}"
  if [[ -n "${DISK_ID_INPUT}" ]]; then
    echo "--> Storing drive passphrase in Keychain (service=backup-tm, account=${VOLUME_NAME_INPUT})..."
    read -r -s -p "    Passphrase (empty to skip — add later with: security add-generic-password -s backup-tm -a '${VOLUME_NAME_INPUT}' -w): " DRIVE_PASS
    echo
    if [[ -n "${DRIVE_PASS}" ]]; then
      security add-generic-password -s "backup-tm" -a "${VOLUME_NAME_INPUT}" -w "${DRIVE_PASS}" 2>/dev/null \
        || security add-generic-password -U -s "backup-tm" -a "${VOLUME_NAME_INPUT}" -w "${DRIVE_PASS}"
      echo "--> Passphrase stored."
    else
      echo "--> Skipped."
    fi
  fi
fi

# Source config so SCHEDULE_HOUR/SCHEDULE_MINUTE are available for plist templating
# shellcheck source=/dev/null
source "${CONFIG_FILE}"

# ── 1. Homebrew ───────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  echo "--> Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/homebrew/install/HEAD/install.sh)"
  # Initialize Homebrew in the current shell session (not yet in PATH after a fresh install)
  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

# ── 2. SwiftBar ───────────────────────────────────────────────
if [ ! -d "/Applications/SwiftBar.app" ]; then
  echo "--> Installing SwiftBar..."
  brew install --cask swiftbar
else
  echo "--> SwiftBar already installed, skipping."
fi

# ── 3. Copy scripts ───────────────────────────────────────────
echo "--> Copying scripts to ${SCRIPTS_DIR}/"
mkdir -p "${SCRIPTS_DIR}"
cp "${REPO_DIR}/backup.sh" "${SCRIPTS_DIR}/backup.sh"
chmod +x "${SCRIPTS_DIR}/backup.sh"
cp "${REPO_DIR}/backup-stop.sh" "${SCRIPTS_DIR}/backup-stop.sh"
chmod +x "${SCRIPTS_DIR}/backup-stop.sh"
rm -rf "${SCRIPTS_DIR}/${RUNNER_APP_NAME}"
cp -R "${REPO_DIR}/${RUNNER_APP_NAME}" "${SCRIPTS_DIR}/${RUNNER_APP_NAME}"

# ── 4. SwiftBar plugin ────────────────────────────────────────
echo "--> Installing SwiftBar plugin..."
mkdir -p "${PLUGINS_DIR}"
cp "${REPO_DIR}/swiftbar-plugin/backup.30s.sh" "${PLUGINS_DIR}/backup.30s.sh"
chmod +x "${PLUGINS_DIR}/backup.30s.sh"
defaults write com.ameba.SwiftBar PluginDirectory "${PLUGINS_DIR}"

# ── 5. LaunchAgent ────────────────────────────────────────────
echo "--> Installing backup LaunchAgent..."
mkdir -p "${LAUNCH_AGENTS}"
sed -e "s|__HOME__|${HOME}|g" \
    -e "s|__HOUR__|${SCHEDULE_HOUR}|g" \
    -e "s|__MINUTE__|${SCHEDULE_MINUTE}|g" \
    "${REPO_DIR}/launchagent/${BACKUP_PLIST_NAME}" > "${LAUNCH_AGENTS}/${BACKUP_PLIST_NAME}"

# Bootout first in case it's already registered
launchctl bootout "${LAUNCHD_DOMAIN}" "${LAUNCH_AGENTS}/${BACKUP_PLIST_NAME}" 2>/dev/null || true
launchctl bootstrap "${LAUNCHD_DOMAIN}" "${LAUNCH_AGENTS}/${BACKUP_PLIST_NAME}"

# ── 6. SwiftBar autostart ─────────────────────────────────────
echo "--> Installing SwiftBar autostart LaunchAgent..."
cp "${REPO_DIR}/launchagent/${SWIFTBAR_PLIST_NAME}" "${LAUNCH_AGENTS}/${SWIFTBAR_PLIST_NAME}"

# Bootout first in case it's already registered
launchctl bootout "${LAUNCHD_DOMAIN}" "${LAUNCH_AGENTS}/${SWIFTBAR_PLIST_NAME}" 2>/dev/null || true
launchctl bootstrap "${LAUNCHD_DOMAIN}" "${LAUNCH_AGENTS}/${SWIFTBAR_PLIST_NAME}"

# Load starts SwiftBar immediately via RunAtLoad, but open it directly as a fallback.
echo "--> Launching SwiftBar..."
open -g -a /Applications/SwiftBar.app

echo ""
printf 'Done! Backup will run automatically at %02d:%02d every day.\n' "${SCHEDULE_HOUR}" "${SCHEDULE_MINUTE}"
echo "Use the TM icon in the menu bar to run or stop it manually."
