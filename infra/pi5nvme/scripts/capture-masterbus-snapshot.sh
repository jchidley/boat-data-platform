#!/bin/bash
set -euo pipefail

SNAPSHOT_ROOT=${SNAPSHOT_ROOT:-/srv/boat/masterbus}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$SNAPSHOT_ROOT/$STAMP"
mkdir -p "$OUT"

run_capture() {
  local name=$1
  shift
  {
    echo "# $*"
    echo "# captured_at=$(date -u --iso-8601=seconds)"
    "$@"
  } >"$OUT/$name" 2>&1 || true
}

run_capture hostname.txt hostnamectl
run_capture usb.txt lsusb
run_capture hidraw.txt sh -c 'ls -l /dev/hidraw* 2>/dev/null || true'
run_capture masterbus-service.txt systemctl --no-pager --full status masterbus-signalk.service
run_capture masterbus-journal.txt journalctl -u masterbus-signalk.service --no-pager -n 300

if [ -d /etc/default/masterbus ]; then
  cp -a /etc/default/masterbus "$OUT/etc-default-masterbus"
fi
if [ -d /etc/default/masterbus-signalk ]; then
  mkdir -p "$OUT/etc-default-masterbus-signalk"
  for f in /etc/default/masterbus-signalk/*; do
    [ -f "$f" ] || continue
    # Avoid copying secrets blindly; keep useful config shape.
    sed -E 's/(PASSWORD|TOKEN|SECRET|KEY)=.*/\1=<redacted>/I' "$f" >"$OUT/etc-default-masterbus-signalk/$(basename "$f")"
  done
fi

if command -v masterbus-tui >/dev/null 2>&1; then
  run_capture masterbus-tui-version.txt masterbus-tui --version
fi
if command -v masterbus-signalk >/dev/null 2>&1; then
  run_capture masterbus-signalk-version.txt masterbus-signalk --version
fi

# Optional project-specific non-interactive dump command. Example:
#   MASTERBUS_SNAPSHOT_COMMAND='masterbus-dump --json'
if [ -n "${MASTERBUS_SNAPSHOT_COMMAND:-}" ]; then
  run_capture masterbus-dump.txt sh -c "$MASTERBUS_SNAPSHOT_COMMAND"
fi

cat >"$OUT/manifest.json" <<JSON
{
  "captured_at": "$(date -u --iso-8601=seconds)",
  "host": "$(hostname -s)",
  "snapshot_dir": "$OUT",
  "note": "Best-effort MasterBus discovery/config snapshot. Add MASTERBUS_SNAPSHOT_COMMAND for a richer non-interactive field dump when available."
}
JSON

ln -sfn "$OUT" "$SNAPSHOT_ROOT/latest"
echo "$OUT"
