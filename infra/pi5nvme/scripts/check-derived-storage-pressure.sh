#!/bin/bash
set -euo pipefail

CHECK_PATH=${CHECK_PATH:-/var/lib/postgresql}
WARN_PCT=${WARN_PCT:-75}
STOP_PCT=${STOP_PCT:-85}
CRITICAL_PCT=${CRITICAL_PCT:-90}
DERIVED_UNITS=${DERIVED_UNITS:-}

for value in "$WARN_PCT" "$STOP_PCT" "$CRITICAL_PCT"; do
  [[ "$value" =~ ^[0-9]+$ ]] || { echo "invalid percentage: $value" >&2; exit 2; }
done
if (( WARN_PCT >= STOP_PCT || STOP_PCT >= CRITICAL_PCT || CRITICAL_PCT > 100 )); then
  echo "thresholds must satisfy WARN_PCT < STOP_PCT < CRITICAL_PCT <= 100" >&2
  exit 2
fi

use_pct=$(df -P "$CHECK_PATH" | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
[[ "$use_pct" =~ ^[0-9]+$ ]] || { echo "could not read filesystem use for $CHECK_PATH" >&2; exit 2; }

echo "derived_storage_path=$CHECK_PATH use_pct=$use_pct warn_pct=$WARN_PCT stop_pct=$STOP_PCT critical_pct=$CRITICAL_PCT"

if (( use_pct >= STOP_PCT )); then
  for unit in $DERIVED_UNITS; do
    if systemctl is-active --quiet "$unit"; then
      systemctl stop "$unit"
      logger -t boat-derived-storage-guard "stopped $unit at ${use_pct}% filesystem use"
      echo "stopped=$unit"
    fi
  done
  if (( use_pct >= CRITICAL_PCT )); then
    echo "CRITICAL: derived writers stopped; operator cleanup required"
    exit 2
  fi
  echo "STOP: disk threshold reached; configured derived writers stopped"
  exit 1
fi

if (( use_pct >= WARN_PCT )); then
  echo "WARN: derived storage filesystem is ${use_pct}% used"
  exit 0
fi

echo "OK: derived storage filesystem is ${use_pct}% used"
