#!/usr/bin/env bash
# validate.sh — syntax and lint checks for backup-tm
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

check() {
  local label="$1"; shift
  printf '  %-50s' "${label}"
  if "$@" >/dev/null 2>&1; then
    echo "OK"
    PASS=$((PASS + 1))
  else
    echo "FAIL"
    "$@" 2>&1 | sed 's/^/    /' || true
    FAIL=$((FAIL + 1))
  fi
}

echo "==> bash -n (syntax check)"
for f in backup.sh backup-stop.sh install.sh uninstall.sh validate.sh \
          swiftbar-plugin/backup.30s.sh; do
  check "${f}" bash -n "${REPO_DIR}/${f}"
done

echo ""
echo "==> plutil -lint (plist validation)"
# Template plist contains __HOUR__ / __MINUTE__ placeholders — substitute before linting
TMP_PLIST=$(mktemp /tmp/backup-tm-plist.XXXXXX)
trap 'rm -f "${TMP_PLIST}"' EXIT
sed -e "s|__HOME__|${HOME}|g" -e "s|__HOUR__|14|g" -e "s|__MINUTE__|0|g" \
    "${REPO_DIR}/launchagent/org.aborroy.backup-tm.backup.plist" > "${TMP_PLIST}"
check "org.aborroy.backup-tm.backup.plist" plutil -lint "${TMP_PLIST}"
check "org.aborroy.backup-tm.swiftbar-autostart.plist" \
  plutil -lint "${REPO_DIR}/launchagent/org.aborroy.backup-tm.swiftbar-autostart.plist"

echo ""
if command -v shellcheck &>/dev/null; then
  echo "==> shellcheck"
  for f in backup.sh backup-stop.sh install.sh uninstall.sh \
            swiftbar-plugin/backup.30s.sh; do
    check "${f}" shellcheck "${REPO_DIR}/${f}"
  done
else
  echo "==> shellcheck (skipped — not installed; run: brew install shellcheck)"
fi

echo ""
if ((FAIL > 0)); then
  echo "Result: ${FAIL} check(s) FAILED."
  exit 1
else
  echo "Result: all ${PASS} checks passed."
fi
