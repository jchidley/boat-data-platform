#!/bin/bash
set -euo pipefail

IFACE=${IFACE:-can0}
LOG_DIR=${LOG_DIR:-/var/log/n2k}

echo "host=$(hostname -s)"
echo "time_utc=$(date -u --iso-8601=seconds)"

echo "--- clock ---"
if command -v chronyc >/dev/null 2>&1; then
  chronyc tracking || true
else
  timedatectl status || true
fi

echo "--- can interface ---"
ip -details -statistics link show "$IFACE" || true

echo "--- raw log directory ---"
df -h "$LOG_DIR" || true
find "$LOG_DIR" -maxdepth 1 -type f \( -name '*.candump.log.gz' -o -name '*.candump.log.zst' -o -name '*.candump.log.tmp' \) -printf '%TY-%Tm-%TdT%TH:%TM:%TSZ %s %p\n' 2>/dev/null | sort | tail -20 || true

if command -v check-raw-spool-space >/dev/null 2>&1; then
  echo "--- raw spool health ---"
  check-raw-spool-space || true
fi

echo "--- services ---"
systemctl --no-pager --full status can0-nmea2000.service n2k-raw-logger.service n2k-raw-forwarder.service || true
