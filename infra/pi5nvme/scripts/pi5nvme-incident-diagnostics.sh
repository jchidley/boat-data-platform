#!/bin/bash
set -euo pipefail

SINCE=${SINCE:-2026-07-03 12:00}
PROTECT=0
if [ "${1:-}" = "--protect" ]; then
  PROTECT=1
fi

echo "# pi5nvme incident diagnostics"
echo "host=$(hostname -s)"
echo "time_utc=$(date -u --iso-8601=seconds)"
echo "since=$SINCE"

if [ "$PROTECT" -eq 1 ]; then
  echo
  echo "== protective action: stop/disable raw importer =="
  sudo systemctl stop boat-raw-n2k-import.service 2>/dev/null || true
  sudo systemctl disable --now boat-raw-n2k-import.timer 2>/dev/null || true
else
  echo
  echo "== protective action not run =="
  echo "Run with --protect to stop/disable boat-raw-n2k-import.service/timer."
fi

echo
echo "== uptime / boot history =="
uptime || true
last -x | head -40 || true

echo
echo "== thermals / throttling / power =="
if command -v vcgencmd >/dev/null 2>&1; then
  vcgencmd measure_temp || true
  vcgencmd get_throttled || true
fi
for z in /sys/class/thermal/thermal_zone*/temp; do
  [ -r "$z" ] && printf "%s " "$z" && cat "$z"
done

echo
echo "== memory / disk =="
free -h || true
df -h / /srv/boat /tmp 2>/dev/null || df -h || true

echo
echo "== failed units =="
systemctl --failed --no-pager || true

echo
echo "== key service states =="
systemctl --no-pager --full status \
  boat-raw-n2k-import.service \
  boat-raw-n2k-import.timer \
  postgresql.service \
  ssh.service \
  signalk-pi5nvme.service \
  boat-n2k-raw-receiver.service \
  masterbus-signalk.service 2>/dev/null | sed -n '1,260p' || true

echo
echo "== high-severity current boot =="
journalctl -b -p warning..alert --no-pager | tail -250 || true

echo
echo "== high-severity previous boot =="
journalctl -b -1 -p warning..alert --no-pager | tail -250 || true

echo
echo "== relevant unit logs since $SINCE =="
journalctl \
  -u boat-raw-n2k-import.service \
  -u postgresql.service \
  -u ssh.service \
  -u signalk-pi5nvme.service \
  -u boat-n2k-raw-receiver.service \
  --since "$SINCE" --no-pager | tail -500 || true

echo
echo "== kernel OOM / power / thermal / storage clues =="
dmesg -T 2>/dev/null | grep -Ei 'oom|killed process|out of memory|nvme|ext4|under-voltage|undervoltage|throttl|thermal|reset|error|i/o|voltage' | tail -250 || true

echo
echo "== raw importer safety gate =="
systemctl cat boat-raw-n2k-import.service 2>/dev/null || true
if [ -e /etc/boat-data-platform/allow-raw-n2k-import ]; then
  echo "ALLOW FILE PRESENT: /etc/boat-data-platform/allow-raw-n2k-import"
else
  echo "allow file absent: /etc/boat-data-platform/allow-raw-n2k-import"
fi
