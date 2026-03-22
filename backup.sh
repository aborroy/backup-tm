#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
STATE_DIR="${HOME}/.local/state"
PROGRESS_FILE="${STATE_DIR}/backup-progress"
STATUS_FILE="${STATE_DIR}/backup-status"
LOCK_DIR="${STATE_DIR}/backup.lock"
LAST_SUCCESS_FILE="${STATE_DIR}/backup-last-success"
LAST_PARTIAL_FILE="${STATE_DIR}/backup-last-partial"
LEGACY_LAST_SNAPSHOT_FILE="${STATE_DIR}/backup-last-snapshot"

# ── Config file ──────────────────────────────────────────────────
CONFIG_FILE="${HOME}/.config/backup-tm/config"
# shellcheck source=/dev/null
source "${CONFIG_FILE}" 2>/dev/null \
  || { echo "ERROR: config not found: ${CONFIG_FILE}. Run install.sh first." >&2; exit 1; }

# ── Configuration ────────────────────────────────────────────────
MOUNT_POINT="/Volumes/${VOLUME_NAME}"
SOURCE="${HOME}/"
BACKUP_ROOT="${MOUNT_POINT}/Backup/$(hostname -s)"
CURRENT_DIR_NAME="current"
DEST="${BACKUP_ROOT}/${CURRENT_DIR_NAME}"
LATEST_LINK="${BACKUP_ROOT}/latest"
LOG_FILE="${HOME}/Library/Logs/backup.log"
RUN_ID="$(date '+%Y-%m-%d_%H%M%S')"
EXCLUDES=(
  ".DS_Store"
  ".Trash"
  "Library/Caches"
  "Library/Application Support/com.apple.sharedfilelist"
  "Library/Mail"
  "Library/Photos"
  "Library/Containers/com.apple.mail"
  "Library/Messages"
  "Library/Application Support/MobileSync"
  "Library/CloudStorage"
  ".BurpSuite/updates"
  ".antigravity"
  "*.tmp"
  "*.vmdk"
  "*.vdi"
  "*.iso"
  "node_modules"
  ".git"
)
BACKUP_METADATA_EXCLUDES=(
  "/manifests"
  "/.backup-incomplete"
  "/.backup-complete"
  "/rsync.log"
)

# ── Helpers ──────────────────────────────────────────────────────
log()     { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
die()     { log "ERROR: $*"; exit 1; }
section() { echo "" | tee -a "${LOG_FILE}"; log "━━━  $*  ━━━"; }
elapsed() { echo $(( $(date +%s) - $1 )); }
set_status() { printf '%s\n' "$1" > "${STATUS_FILE}"; }
cleanup() {
  rm -f "${PROGRESS_FILE}" "${STATUS_FILE}"
  rm -rf "${LOCK_DIR}"
}
log_file_lines() {
  local file="$1"
  [[ -f "${file}" ]] || return 0

  while IFS= read -r line; do
    [[ -n "${line//[[:space:]]/}" ]] || continue
    log "  ${line}"
  done < <(grep -E 'No space left|Permission denied|Operation not permitted|Input/output error|Result too large|rsync error|^rsync:' "${file}" | tail -n 10 || true)
}
find_latest_legacy_snapshot() {
  if [[ -L "${LATEST_LINK}" && -d "${LATEST_LINK}" ]]; then
    local latest_target

    latest_target="$(readlink "${LATEST_LINK}")"
    if [[ "$(basename "${latest_target}")" != "${CURRENT_DIR_NAME}" ]]; then
      printf '%s\n' "${latest_target}"
      return 0
    fi
  fi

  find "${BACKUP_ROOT}" -maxdepth 1 -mindepth 1 -type d \
    -name '[0-9][0-9][0-9][0-9]-*' | sort | tail -1 || true
}
migrate_legacy_backup_layout() {
  local seed=""

  [[ -d "${BACKUP_ROOT}" ]] || return 0
  [[ -d "${DEST}" ]] && return 0

  seed="$(find_latest_legacy_snapshot)"
  if [[ -n "${seed}" && -d "${seed}" ]]; then
    log "Migrating legacy snapshot layout: ${seed} → ${DEST}"
    mv "${seed}" "${DEST}"
  fi
}
remove_legacy_snapshots() {
  local removed=0
  local snapshot

  [[ -d "${BACKUP_ROOT}" ]] || return 0

  while IFS= read -r -d '' snapshot; do
    log "Removing legacy snapshot: ${snapshot}"
    chmod -R u+w "${snapshot}" 2>/dev/null || true
    rm -rf "${snapshot}"
    ((removed += 1))
  done < <(find "${BACKUP_ROOT}" -maxdepth 1 -mindepth 1 -type d \
             -name '[0-9][0-9][0-9][0-9]-*' -print0 | sort -z)

  if (( removed > 0 )); then
    log "Removed ${removed} legacy snapshot(s) before starting."
  fi
}

mkdir -p "${STATE_DIR}"

if [[ -d "${LOCK_DIR}" ]]; then
  if [[ -f "${LOCK_DIR}/pid" ]]; then
    STALE_PID="$(< "${LOCK_DIR}/pid")"
    if kill -0 "${STALE_PID}" 2>/dev/null; then
      die "Backup already running with PID ${STALE_PID}. Aborting duplicate launch."
    fi
  fi
  rm -rf "${LOCK_DIR}"
fi

mkdir "${LOCK_DIR}" 2>/dev/null || die "Backup already running. Aborting duplicate launch."
printf '%s\n' "$$" > "${LOCK_DIR}/pid"
trap cleanup EXIT INT TERM

START_TIME=$(date +%s)

# ── Pre-flight checks ────────────────────────────────────────────
set_status "pre-flight"
section "PRE-FLIGHT"
log "Backup job started on $(hostname -s)"
log "Source      : ${SOURCE}"
log "Destination : ${DEST}"
log "Mode        : single in-place incremental mirror"
if [[ ! -d "${MOUNT_POINT}" ]] && [[ -n "${DISK_IDENTIFIER:-}" ]]; then
  log "Volume not mounted — attempting to unlock ${DISK_IDENTIFIER}..."
  PASSPHRASE="$(security find-generic-password -s "backup-tm" -a "${VOLUME_NAME}" -w 2>/dev/null)" \
    || die "Passphrase for '${VOLUME_NAME}' not found in Keychain. Add it with: security add-generic-password -s backup-tm -a '${VOLUME_NAME}' -w"
  diskutil apfs unlockVolume "${DISK_IDENTIFIER}" -passphrase "${PASSPHRASE}" \
    || die "Failed to unlock ${DISK_IDENTIFIER}. Check DISK_IDENTIFIER in ~/.config/backup-tm/config."
  log "Volume unlocked and mounted at ${MOUNT_POINT}."
fi
[[ -d "${MOUNT_POINT}" ]] || die "${VOLUME_NAME} is not mounted. Aborting."
mkdir -p "${BACKUP_ROOT}"

set_status "cleanup"
section "CLEANUP"
migrate_legacy_backup_layout
remove_legacy_snapshots

AVAIL=$(df -h "${MOUNT_POINT}" | awk 'NR==2{print $4}')
log "Disk free   : ${AVAIL} on ${VOLUME_NAME}"

# ── Build exclude arguments ──────────────────────────────────────
EXCLUDE_ARGS=()
for pattern in "${EXCLUDES[@]}"; do
  EXCLUDE_ARGS+=(--exclude="${pattern}")
done
for pattern in "${BACKUP_METADATA_EXCLUDES[@]}"; do
  EXCLUDE_ARGS+=(--exclude="${pattern}")
done

# ── Capture installed software lists ─────────────────────────────
set_status "manifests"
section "MANIFESTS"
MANIFEST_START=$(date +%s)
log "Capturing installed software manifests..."

MANIFEST_DIR="${DEST}/manifests"
mkdir -p "${DEST}"
rm -rf "${MANIFEST_DIR}"
mkdir -p "${MANIFEST_DIR}"
rm -f "${DEST}/.backup-complete"
touch "${DEST}/.backup-incomplete"

if command -v mas &>/dev/null; then
  log "  Running mas list..."
  mas list > "${MANIFEST_DIR}/appstore.txt"
  log "  ✓ App Store apps"
fi

ls /Applications > "${MANIFEST_DIR}/applications.txt"
log "  ✓ /Applications folder"

if command -v brew &>/dev/null; then
  log "  Running brew list..."
  brew list --formula > "${MANIFEST_DIR}/brew-formulae.txt"
  brew list --cask    > "${MANIFEST_DIR}/brew-casks.txt"
  log "  ✓ Homebrew formulae and casks"
fi

sw_vers > "${MANIFEST_DIR}/system.txt"
log "  ✓ System info"
system_profiler SPHardwareDataType >> "${MANIFEST_DIR}/system.txt" 2>/dev/null &
PROFILER_PID=$!
log "  (hardware profile running in background)"

log "Manifests done in $(elapsed $MANIFEST_START)s — rsync starting"

# ── Run rsync ────────────────────────────────────────────────────
set_status "rsync"
section "RSYNC"
log "Sync started → ${DEST}"
RSYNC_START=$(date +%s)

RSYNC_LOG="${DEST}/rsync.log"
RSYNC_EXIT=0
RSYNC_PARTIAL=false
rsync -rlptgoD --delete --human-readable --stats --one-file-system \
  --info=progress2 \
  ${EXCLUDE_ARGS[@]+"${EXCLUDE_ARGS[@]}"} \
  "${SOURCE}" "${DEST}/" 2>&1 | tee "${RSYNC_LOG}" | \
  tr '\r' '\n' | grep --line-buffered 'to-chk=' | \
  sed 's/.*to-chk=\([0-9]*\)\/\([0-9]*\).*/\1 \2/' | \
  awk '{total=$2; rem=$1; if (total>0) { printf "%d%%\n", (total-rem)/total*100; fflush() }}' | \
  while IFS= read -r pct; do printf '%s\n' "${pct}" > "${PROGRESS_FILE}"; done || RSYNC_EXIT=$?
if [[ "${RSYNC_EXIT}" -eq 23 ]]; then
  # Partial transfer: some files could not be transferred (permission errors, I/O errors, etc.)
  # This is a degraded run — do not mark as successful.
  log "WARNING: rsync partial transfer (exit 23) — some files could not be transferred"
  if [[ -f "${RSYNC_LOG}" ]]; then
    log "rsync error details:"
    log_file_lines "${RSYNC_LOG}"
  fi
  RSYNC_PARTIAL=true
elif [[ "${RSYNC_EXIT}" -eq 24 ]]; then
  # Vanished source files: files disappeared mid-transfer (normal on a live filesystem)
  log "WARNING: rsync exit 24 — some source files vanished during transfer (normal for live filesystems)"
elif [[ "${RSYNC_EXIT}" -ne 0 ]]; then
  if [[ -f "${RSYNC_LOG}" ]]; then
    log "rsync failure details:"
    log_file_lines "${RSYNC_LOG}"
  else
    log "rsync.log not found — tee could not write it; the destination may be full or not writable."
  fi
  die "rsync failed with exit code ${RSYNC_EXIT}"
fi

# Append only the stats lines (filter out progress lines which start with spaces)
if [[ -f "${RSYNC_LOG}" ]]; then
  grep -v '^ ' "${RSYNC_LOG}" >> "${LOG_FILE}" || true
  FILES_SENT=$(awk '/Number of regular files transferred/{print $NF}' "${RSYNC_LOG}")
  BYTES_SENT=$(awk '/Total transferred file size/{$1=$2=$3=$4=""; print $0}' "${RSYNC_LOG}" | xargs)
  BYTES_TOTAL=$(awk '/Total file size/{$1=$2=$3=""; print $0}' "${RSYNC_LOG}" | xargs)
  rm -f "${RSYNC_LOG}"
else
  log "WARNING: rsync.log not found — tee failed to write it (disk write error?)"
fi
log "rsync done in $(elapsed $RSYNC_START)s — files transferred: ${FILES_SENT:-n/a}, size: ${BYTES_SENT:-n/a} of ${BYTES_TOTAL:-n/a}"
rm -f "${PROGRESS_FILE}"

wait $PROFILER_PID 2>/dev/null && log "  ✓ Hardware profile" || log "  ⚠ Hardware profile skipped"

# ── Finalize backup metadata ─────────────────────────────────────
set_status "finalize"
section "FINALIZE"
if $RSYNC_PARTIAL; then
  printf '%s\n' "${RUN_ID}" > "${LAST_PARTIAL_FILE}"
  log "Partial backup recorded — not marked as successful: ${DEST}"
  log "Check the log for files that could not be transferred."
else
  rm -f "${DEST}/.backup-incomplete"
  touch "${DEST}/.backup-complete"
  ln -sfn "${DEST}" "${LATEST_LINK}"
  printf '%s\n' "${RUN_ID}" > "${LAST_SUCCESS_FILE}"
  printf '%s\n' "${RUN_ID}" > "${LEGACY_LAST_SNAPSHOT_FILE}"
  log "Backup updated in place: ${DEST}"
  log "Symlink updated: latest → ${DEST}"
fi

# ── Summary ──────────────────────────────────────────────────────
section "SUMMARY"
log "Backup mode        : single in-place incremental mirror"
log "Backup target      : ${DEST}"
log "Total elapsed      : $(elapsed $START_TIME)s"
log "Log file           : ${LOG_FILE}"
if $RSYNC_PARTIAL; then
  section "DONE (PARTIAL)"
else
  section "DONE"
fi
