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

echo "--- live raw receiver ports ---"
ss -ltnp 2>/dev/null | grep -E ':(20200|20201)\b' || true
ss -tnp 2>/dev/null | grep -E ':(20200|20201)\b' || true

echo "--- Signal K sources ---"
if command -v curl >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  curl -fsS http://127.0.0.1:3001/signalk/v1/api/sources 2>/dev/null | node -e '
let s = ""
process.stdin.on("data", d => s += d)
process.stdin.on("end", () => {
  if (!s) process.exit(0)
  const sources = JSON.parse(s)
  for (const name of ["picanm-raw-candump-fanout", "can0-nmea2000", "masterbus"]) {
    const src = sources[name]
    if (!src) {
      console.log(`${name}: missing`)
      continue
    }
    const pgns = new Set()
    let n2kSources = 0
    for (const value of Object.values(src)) {
      if (value && value.n2k) {
        n2kSources++
        for (const pgn of Object.keys(value.n2k.pgns || {})) pgns.add(pgn)
      }
    }
    console.log(`${name}: n2k_sources=${n2kSources} pgns=${pgns.size}`)
  }
})
' || true
fi

echo "--- database freshness ---"
if command -v psql >/dev/null 2>&1; then
fi

echo "--- MasterBus replay logs ---"
find /srv/boat/masterbus/signalk-jsonl -maxdepth 1 -type f -name 'masterbus-signalk-*.jsonl*' -printf '%TY-%Tm-%TdT%TH:%TM:%TSZ %s %p\n' 2>/dev/null | sort | tail -20 || true

echo "--- services ---"
systemctl --no-pager --full status boat-n2k-raw-receiver.service boat-raw-log-mirror.timer boat-masterbus-signalk-log.service signalk-pi5nvme.service masterbus-signalk.service || true
