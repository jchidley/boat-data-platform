#!/bin/bash
set -euo pipefail

LOG_DIR=${LOG_DIR:-/var/log/n2k}
WARN_USE_PCT=${WARN_USE_PCT:-80}
CRIT_USE_PCT=${CRIT_USE_PCT:-90}
WARN_FREE_MIB=${WARN_FREE_MIB:-2048}
CRIT_FREE_MIB=${CRIT_FREE_MIB:-512}
MAX_TMP_AGE_MIN=${MAX_TMP_AGE_MIN:-90}

status=0

echo "host=$(hostname -s)"
echo "time_utc=$(date -u --iso-8601=seconds)"
echo "log_dir=$LOG_DIR"

if [ ! -d "$LOG_DIR" ]; then
  echo "CRIT: log directory missing: $LOG_DIR"
  exit 2
fi

read -r size used avail use_pct mount < <(df -Pm "$LOG_DIR" | awk 'NR==2 {gsub(/%/,"",$5); print $2,$3,$4,$5,$6}')
echo "disk_size_mib=$size"
echo "disk_used_mib=$used"
echo "disk_free_mib=$avail"
echo "disk_use_pct=$use_pct"
echo "mount=$mount"

if [ "$use_pct" -ge "$CRIT_USE_PCT" ] || [ "$avail" -le "$CRIT_FREE_MIB" ]; then
  echo "CRIT: raw spool disk pressure: use=${use_pct}% free=${avail}MiB"
  status=2
elif [ "$use_pct" -ge "$WARN_USE_PCT" ] || [ "$avail" -le "$WARN_FREE_MIB" ]; then
  echo "WARN: raw spool disk pressure: use=${use_pct}% free=${avail}MiB"
  status=1
else
  echo "OK: raw spool disk space acceptable"
fi

completed_count=$(find "$LOG_DIR" -maxdepth 1 -type f \( -name '*.candump.log.gz' -o -name '*.candump.log.zst' \) | wc -l)
tmp_count=$(find "$LOG_DIR" -maxdepth 1 -type f -name '*.candump.log.tmp' | wc -l)
completed_mib=$(find "$LOG_DIR" -maxdepth 1 -type f \( -name '*.candump.log.gz' -o -name '*.candump.log.zst' \) -printf '%s\n' | awk '{s+=$1} END {printf "%.1f", s/1024/1024}')
tmp_mib=$(find "$LOG_DIR" -maxdepth 1 -type f -name '*.candump.log.tmp' -printf '%s\n' | awk '{s+=$1} END {printf "%.1f", s/1024/1024}')
echo "completed_segments=$completed_count"
echo "active_tmp_segments=$tmp_count"
echo "completed_mib=$completed_mib"
echo "active_tmp_mib=$tmp_mib"

latest_tmp=$(find "$LOG_DIR" -maxdepth 1 -type f -name '*.candump.log.tmp' -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
if [ -n "${latest_tmp:-}" ]; then
  echo "latest_tmp=$latest_tmp"
  echo "latest_tmp_lines=$(wc -l < "$latest_tmp" 2>/dev/null || echo unknown)"
  echo "latest_tmp_tail:"
  tail -3 "$latest_tmp" || true
  printf '\n'
fi

old_tmp=$(find "$LOG_DIR" -maxdepth 1 -type f -name '*.candump.log.tmp' -mmin +"$MAX_TMP_AGE_MIN" -print)
if [ -n "$old_tmp" ]; then
  echo "WARN: tmp segments older than ${MAX_TMP_AGE_MIN} minutes:"
  echo "$old_tmp"
  [ "$status" -lt 1 ] && status=1
fi

exit "$status"
