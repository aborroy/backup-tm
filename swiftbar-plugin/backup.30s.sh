#!/usr/bin/env bash
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>

CONFIG_FILE="${HOME}/.config/backup-tm/config"
if ! source "${CONFIG_FILE}" 2>/dev/null; then
  echo "backup-tm: config missing"
  echo "---"
  echo "Run install.sh to configure | color=red"
  exit 0
fi

LOG="${HOME}/Library/Logs/backup.log"
BACKUP_ROOT="/Volumes/${VOLUME_NAME}/Backup/$(hostname -s)"
BACKUP_DIR="${BACKUP_ROOT}/current"
LATEST_LINK="${BACKUP_ROOT}/latest"
PROGRESS_FILE="${HOME}/.local/state/backup-progress"
STATUS_FILE="${HOME}/.local/state/backup-status"
LAST_SUCCESS_FILE="${HOME}/.local/state/backup-last-success"
LAST_PARTIAL_FILE="${HOME}/.local/state/backup-last-partial"
LEGACY_LAST_SNAPSHOT_FILE="${HOME}/.local/state/backup-last-snapshot"

IS_RUNNING=false
pgrep -qf "[b]ackup.sh" && IS_RUNNING=true

PCT=""
PHASE=""
PCT_AGE_MIN=""
if $IS_RUNNING && [[ -f "${PROGRESS_FILE}" ]]; then
  PCT=$(< "${PROGRESS_FILE}")
  PCT_MTIME=$(stat -f %m "${PROGRESS_FILE}" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  if [[ "${PCT_MTIME}" -gt 0 ]]; then
    PCT_AGE_MIN=$(( (NOW - PCT_MTIME) / 60 ))
  fi
fi
if $IS_RUNNING && [[ -f "${STATUS_FILE}" ]]; then
  PHASE=$(< "${STATUS_FILE}")
fi
if [[ -z "${PHASE}" && -n "${PCT}" ]]; then
  PHASE="rsync"
fi

case "${PHASE}" in
  pre-flight) PHASE_LABEL="Preparing" ;;
  cleanup) PHASE_LABEL="Cleaning old backup" ;;
  manifests) PHASE_LABEL="Building manifests" ;;
  rsync) PHASE_LABEL="Copying data" ;;
  finalize) PHASE_LABEL="Finalizing backup" ;;
  *) PHASE_LABEL="Running" ;;
esac

TITLE="TM"
HAS_SUCCESSFUL_BACKUP=false
if $IS_RUNNING; then
  if [[ "${PHASE}" == "rsync" && -n "${PCT}" ]]; then
    TITLE="TM ↑${PCT}"
    if [[ -n "${PCT_AGE_MIN}" && "${PCT_AGE_MIN}" -ge 10 ]]; then
      TITLE="${TITLE} ${PCT_AGE_MIN}m"
    fi
  else
    TITLE="TM ${PHASE_LABEL}"
  fi
fi

# ── Menu bar title ────────────────────────────────────────────
echo "${TITLE}"
echo "---"

# ── Status ────────────────────────────────────────────────────
if $IS_RUNNING; then
  if [[ "${PHASE}" == "rsync" && -n "${PCT}" ]]; then
    if [[ -n "${PCT_AGE_MIN}" && "${PCT_AGE_MIN}" -ge 10 ]]; then
      echo "Status: ${PHASE_LABEL}; progress unchanged for ${PCT_AGE_MIN}m | color=#f5a623"
    else
      echo "Status: ${PHASE_LABEL}… ${PCT} | color=#f5a623"
    fi
  else
    echo "Status: ${PHASE_LABEL}… | color=#f5a623"
  fi
else
  LAST_BACKUP=""
  IS_PARTIAL=false
  if [[ -f "${LAST_SUCCESS_FILE}" ]]; then
    LAST_BACKUP=$(sed 's/_/ /' "${LAST_SUCCESS_FILE}")
  elif [[ -f "${LEGACY_LAST_SNAPSHOT_FILE}" ]]; then
    LAST_BACKUP=$(sed 's/_/ /' "${LEGACY_LAST_SNAPSHOT_FILE}")
  elif [[ -L "${LATEST_LINK}" ]]; then
    LAST_BACKUP=$(basename "$(readlink "${LATEST_LINK}")" | sed 's/_/ /')
  fi
  if [[ -f "${LAST_PARTIAL_FILE}" ]] && \
     { [[ -z "${LAST_BACKUP}" ]] || [[ "${LAST_PARTIAL_FILE}" -nt "${LAST_SUCCESS_FILE}" ]]; }; then
    LAST_BACKUP=$(sed 's/_/ /' "${LAST_PARTIAL_FILE}")
    IS_PARTIAL=true
  fi
  [[ -n "${LAST_BACKUP}" ]] && HAS_SUCCESSFUL_BACKUP=true

  if $IS_PARTIAL; then
    echo "Last backup: ${LAST_BACKUP} (partial) | color=orange"
  elif [[ -n "${LAST_BACKUP}" && -d "${BACKUP_DIR}" ]]; then
    echo "Last backup: ${LAST_BACKUP} | color=green"
  elif [[ -n "${LAST_BACKUP}" ]]; then
    echo "Last backup: ${LAST_BACKUP} (disk offline) | color=orange"
  else
    echo "Last backup: never | color=red"
  fi
fi

# Last log line (errors or summary)
LAST_LOG=$(grep -E "ERROR|Total elapsed|DONE" "${LOG}" 2>/dev/null | tail -1 | sed 's/\[.*\] //')
if [[ -n "${LAST_LOG}" ]] && { $HAS_SUCCESSFUL_BACKUP || [[ "${LAST_LOG}" != ERROR:* ]]; }; then
  echo "${LAST_LOG} | size=11 color=gray"
fi

echo "---"

# ── Actions ───────────────────────────────────────────────────
if $IS_RUNNING; then
  echo "Stop Backup | bash=${HOME}/scripts/backup-stop.sh terminal=false refresh=true color=red"
else
  echo "Run Backup Now | bash=${HOME}/scripts/backup.sh terminal=false refresh=true"
fi

echo "---"
echo "Open Log | bash=/usr/bin/open param1=${LOG} terminal=false"
echo "Reveal Backup Folder | bash=/usr/bin/open param1=${BACKUP_ROOT} terminal=false"
