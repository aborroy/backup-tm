#!/usr/bin/env bash
# Stops the running backup-tm process using the lock file PID.
# Scoped to the exact backup.sh process tree — does not kill unrelated rsync processes.
LOCK_PID_FILE="${HOME}/.local/state/backup.lock/pid"

if [[ ! -f "${LOCK_PID_FILE}" ]]; then
  exit 0
fi

PID=$(< "${LOCK_PID_FILE}")
if ! kill -0 "${PID}" 2>/dev/null; then
  exit 0
fi

pkill -TERM -P "${PID}" 2>/dev/null || true
kill -TERM "${PID}" 2>/dev/null || true
