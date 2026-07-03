#!/bin/bash
set -euo pipefail

RAW_DIR=${RAW_DIR:-/srv/boat/raw-n2k}
LIVE_DIR=${LIVE_DIR:-/srv/boat/raw-n2k/live}

echo "host=$(hostname -s)"
echo "time_utc=$(date -u --iso-8601=seconds)"

echo "--- clock ---"
if command -v chronyc >/dev/null 2>&1; then
  chronyc tracking || true
else
  timedatectl status || true
fi

echo "--- raw archive ---"
df -h "$RAW_DIR" || true
find "$RAW_DIR" -maxdepth 2 -type f \( -name '*.candump.log.gz' -o -name '*.candump.log.zst' -o -name '*.candump.log.tmp' \) -printf '%TY-%Tm-%TdT%TH:%TM:%TSZ %s %p\n' 2>/dev/null | sort | tail -30 || true

echo "--- database freshness ---"
if command -v psql >/dev/null 2>&1; then
  psql "${DATABASE_URL:-boatdata}" -Atc "select 'signal_k_measurements', count(*), max(time) from signal_k_measurements; select 'n2k_decoded_messages', count(*), max(time) from n2k_decoded_messages;" 2>/dev/null || true
fi

echo "--- services ---"
systemctl --no-pager --full status boat-n2k-raw-receiver.service boat-raw-log-mirror.timer boat-raw-n2k-import.timer signalk-pi5nvme.service masterbus-signalk.service || true
