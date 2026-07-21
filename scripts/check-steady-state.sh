#!/usr/bin/env bash
set -euo pipefail

PICANM_HOST=${PICANM_HOST:-picanm}
PI5_HOST=${PI5_HOST:-pi5nvme}
PI5_SIGNALK_URL=${PI5_SIGNALK_URL:-http://${PI5_HOST}:3001}
SAMPLE_SEC=${SAMPLE_SEC:-30}
FRESH_SEC=${FRESH_SEC:-15}
MASTERBUS_FRESH_SEC=${MASTERBUS_FRESH_SEC:-30}
SSH_OPTS=${SSH_OPTS:- -o ConnectTimeout=5}

pass=0
warn=0
fail=0

say() { printf '%s\n' "$*"; }
record() {
  local level=$1; shift
  case "$level" in
    PASS) pass=$((pass + 1)) ;;
    WARN) warn=$((warn + 1)) ;;
    FAIL) fail=$((fail + 1)) ;;
  esac
  printf '%-4s %s\n' "$level" "$*"
}

ssh_host() {
  local host=$1; shift
  # shellcheck disable=SC2086
  ssh $SSH_OPTS "$host" "$@"
}

kv_get() {
  local key=$1 file=$2
  awk -F= -v k="$key" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

num_gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'; }
num_eq() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a == b) }'; }
num_le() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a <= b) }'; }
num_ge() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >= b) }'; }
num_abs() { awk -v a="$1" 'BEGIN { if (a < 0) a = -a; print a }'; }
hex_nonzero() {
  local h=${1:-0x0}
  h=${h#0x}
  [[ -n "$h" ]] && (( 16#$h != 0 ))
}
hex_current_throttled() {
  local h=${1:-0x0}
  h=${h#0x}
  [[ -n "$h" ]] && (( (16#$h & 0xF) != 0 ))
}

TMPDIR=${TMPDIR:-/tmp}
RUN_DIR=$(mktemp -d "$TMPDIR/boat-steady-state.XXXXXX")
trap 'rm -rf "$RUN_DIR"' EXIT

say "# Boat steady-state health check"
say "time_utc=$(date -u --iso-8601=seconds)"
say "sample_sec=${SAMPLE_SEC} fresh_sec=${FRESH_SEC} masterbus_fresh_sec=${MASTERBUS_FRESH_SEC}"
say ""

collect_picanm() {
  ssh_host "$PICANM_HOST" 'bash -s' <<'REMOTE'
set -euo pipefail
echo host=$(hostname -s)
echo time_epoch=$(date +%s)
echo can0_active=$(systemctl is-active can0-nmea2000 || true)
echo raw_logger_active=$(systemctl is-active n2k-raw-logger || true)
echo raw_forwarder_active=$(systemctl is-active n2k-raw-forwarder || true)
if command -v vcgencmd >/dev/null 2>&1; then
  vcgencmd measure_temp | sed -n "s/temp=\([0-9.]*\).*/temp_c=\1/p" || true
  vcgencmd get_throttled | sed -n "s/throttled=\(0x[0-9a-fA-F]*\).*/throttled=\1/p" || true
fi
if command -v chronyc >/dev/null 2>&1; then
  chronyc tracking | awk -F: '
    /System time/ { gsub(/^[[:space:]]+/, "", $2); split($2, a, " "); v=a[1]; if ($0 ~ /slow/) v=-v; print "chrony_system_offset_s=" v }
    /Leap status/ { gsub(/^[[:space:]]+/, "", $2); print "chrony_leap_status=" $2 }
  ' || true
fi
free -m | awk 'NR==2 {print "mem_available_mib="$7; print "mem_used_mib="$3} NR==3 {print "swap_used_mib="$3}'
df -Pm /var/log/n2k | awk 'NR==2 {print "n2k_free_mib="$4; gsub(/%/,"",$5); print "n2k_used_pct="$5}'
active_tmp=$(find /var/log/n2k -maxdepth 1 -name '*.candump.log.tmp' -type f | sort | tail -1)
echo active_tmp=$active_tmp
stat -c 'active_tmp_size=%s' "$active_tmp"
stat -c 'active_tmp_mtime_epoch=%Y' "$active_tmp"
ip -details -statistics link show can0 | awk '
  /can state/ {print "can_state="$3}
  /bus-off/ {hdr=1; next}
  hdr && /^[[:space:]]*[0-9]/ {print "can_bus_off="$6; hdr=0}
  /RX:/ {rx=1; next}
  rx && /^[[:space:]]*[0-9]/ {print "can_rx_bytes="$1; print "can_rx_packets="$2; print "can_rx_errors="$3; print "can_rx_dropped="$4; rx=0}
'
REMOTE
}

collect_pi5() {
  ssh_host "$PI5_HOST" 'bash -s' <<'REMOTE'
set -euo pipefail
echo host=$(hostname -s)
echo time_epoch=$(date +%s)
echo receiver_active=$(systemctl is-active boat-n2k-raw-receiver || true)
echo signalk_active=$(systemctl is-active signalk-pi5nvme || true)
echo masterbus_active=$(systemctl is-active masterbus-signalk || true)
if command -v vcgencmd >/dev/null 2>&1; then
  vcgencmd measure_temp | sed -n "s/temp=\([0-9.]*\).*/temp_c=\1/p" || true
  vcgencmd get_throttled | sed -n "s/throttled=\(0x[0-9a-fA-F]*\).*/throttled=\1/p" || true
fi
if command -v chronyc >/dev/null 2>&1; then
  chronyc tracking | awk -F: '
    /System time/ { gsub(/^[[:space:]]+/, "", $2); split($2, a, " "); v=a[1]; if ($0 ~ /slow/) v=-v; print "chrony_system_offset_s=" v }
    /Leap status/ { gsub(/^[[:space:]]+/, "", $2); print "chrony_leap_status=" $2 }
  ' || true
fi
free -m | awk 'NR==2 {print "mem_available_mib="$7; print "mem_used_mib="$3} NR==3 {print "swap_used_mib="$3}'
df -Pm /srv/boat/raw-n2k | awk 'NR==2 {print "raw_free_mib="$4; gsub(/%/,"",$5); print "raw_used_pct="$5}'
live_tmp=$(find /srv/boat/raw-n2k/live -maxdepth 1 -name '*.candump.log.tmp' -type f | sort | tail -1)
echo live_tmp=$live_tmp
stat -c 'live_tmp_size=%s' "$live_tmp"
stat -c 'live_tmp_mtime_epoch=%Y' "$live_tmp"
if ss -tnp 2>/dev/null | grep -q ':20200'; then echo raw_tcp_established=yes; else echo raw_tcp_established=no; fi
if ss -tnp 2>/dev/null | grep -q ':20201'; then echo fanout_tcp_established=yes; else echo fanout_tcp_established=no; fi
REMOTE
}

say "## Sampling picanm and pi5 raw file growth"
collect_picanm > "$RUN_DIR/picanm1.kv" || { record FAIL "cannot collect initial picanm state"; : > "$RUN_DIR/picanm1.kv"; }
collect_pi5 > "$RUN_DIR/pi51.kv" || { record FAIL "cannot collect initial pi5 state"; : > "$RUN_DIR/pi51.kv"; }
sleep "$SAMPLE_SEC"
collect_picanm > "$RUN_DIR/picanm2.kv" || { record FAIL "cannot collect second picanm state"; : > "$RUN_DIR/picanm2.kv"; }
collect_pi5 > "$RUN_DIR/pi52.kv" || { record FAIL "cannot collect second pi5 state"; : > "$RUN_DIR/pi52.kv"; }

say ""
say "## picanm"
for svc in can0_active raw_logger_active raw_forwarder_active; do
  val=$(kv_get "$svc" "$RUN_DIR/picanm2.kv" || true)
  if [[ "$val" == active ]]; then record PASS "$svc=$val"; else record FAIL "$svc=$val"; fi
done
can_state=$(kv_get can_state "$RUN_DIR/picanm2.kv" || true)
if [[ "$can_state" == ERROR-ACTIVE ]]; then record PASS "can0 state ${can_state}"; else record FAIL "can0 state ${can_state:-unknown}"; fi
p_chrony_offset=$(kv_get chrony_system_offset_s "$RUN_DIR/picanm2.kv" || true)
p_chrony_leap=$(kv_get chrony_leap_status "$RUN_DIR/picanm2.kv" || true)
if [[ -n "$p_chrony_offset" ]]; then
  p_chrony_abs=$(num_abs "$p_chrony_offset")
  if [[ "$p_chrony_leap" != Normal ]]; then record WARN "picanm chrony leap status ${p_chrony_leap:-unknown}"; fi
  if num_le "$p_chrony_abs" 0.1; then record PASS "picanm chrony system offset ${p_chrony_offset}s"; elif num_le "$p_chrony_abs" 1; then record WARN "picanm chrony system offset ${p_chrony_offset}s"; else record FAIL "picanm chrony system offset ${p_chrony_offset}s"; fi
else
  record WARN "picanm chrony system offset unavailable"
fi
p_temp=$(kv_get temp_c "$RUN_DIR/picanm2.kv" || true)
if [[ -n "$p_temp" ]]; then
  if num_ge "$p_temp" 80; then record FAIL "picanm temperature ${p_temp}C"; elif num_ge "$p_temp" 70; then record WARN "picanm temperature ${p_temp}C"; else record PASS "picanm temperature ${p_temp}C"; fi
else
  record WARN "picanm temperature unavailable"
fi
p_throttled=$(kv_get throttled "$RUN_DIR/picanm2.kv" || echo 0x0)
if hex_current_throttled "$p_throttled"; then record WARN "picanm current throttling flags ${p_throttled}"; else record PASS "picanm no current throttling flags ${p_throttled}"; fi
p_size1=$(kv_get active_tmp_size "$RUN_DIR/picanm1.kv" || echo 0)
p_size2=$(kv_get active_tmp_size "$RUN_DIR/picanm2.kv" || echo 0)
if num_gt "$p_size2" "$p_size1"; then record PASS "picanm active raw log grew ${p_size1} -> ${p_size2} bytes"; else record FAIL "picanm active raw log did not grow ${p_size1} -> ${p_size2} bytes"; fi
rx1=$(kv_get can_rx_packets "$RUN_DIR/picanm1.kv" || echo 0)
rx2=$(kv_get can_rx_packets "$RUN_DIR/picanm2.kv" || echo 0)
if num_gt "$rx2" "$rx1"; then record PASS "CAN RX packets increased ${rx1} -> ${rx2}"; else record FAIL "CAN RX packets did not increase ${rx1} -> ${rx2}"; fi
for metric in can_rx_errors can_rx_dropped can_bus_off; do
  a=$(kv_get "$metric" "$RUN_DIR/picanm1.kv" || echo 0)
  b=$(kv_get "$metric" "$RUN_DIR/picanm2.kv" || echo 0)
  if num_eq "$a" "$b"; then record PASS "$metric stable at $b"; else record WARN "$metric changed ${a} -> ${b}"; fi
done
mem=$(kv_get mem_available_mib "$RUN_DIR/picanm2.kv" || echo 0)
if num_gt "$mem" 128; then record PASS "picanm memory available ${mem} MiB"; else record WARN "picanm memory available ${mem} MiB"; fi
free_mib=$(kv_get n2k_free_mib "$RUN_DIR/picanm2.kv" || echo 0)
used_pct=$(kv_get n2k_used_pct "$RUN_DIR/picanm2.kv" || echo 100)
if num_gt "$free_mib" 2048 && num_le "$used_pct" 80; then record PASS "picanm /var/log/n2k free ${free_mib} MiB used ${used_pct}%"; else record WARN "picanm /var/log/n2k free ${free_mib} MiB used ${used_pct}%"; fi

say ""
say "## pi5nvme"
for svc in receiver_active signalk_active masterbus_active; do
  val=$(kv_get "$svc" "$RUN_DIR/pi52.kv" || true)
  if [[ "$val" == active ]]; then record PASS "$svc=$val"; else record FAIL "$svc=$val"; fi
done
pi_chrony_offset=$(kv_get chrony_system_offset_s "$RUN_DIR/pi52.kv" || true)
pi_chrony_leap=$(kv_get chrony_leap_status "$RUN_DIR/pi52.kv" || true)
if [[ -n "$pi_chrony_offset" ]]; then
  pi_chrony_abs=$(num_abs "$pi_chrony_offset")
  if [[ "$pi_chrony_leap" != Normal ]]; then record WARN "pi5 chrony leap status ${pi_chrony_leap:-unknown}"; fi
  if num_le "$pi_chrony_abs" 0.1; then record PASS "pi5 chrony system offset ${pi_chrony_offset}s"; elif num_le "$pi_chrony_abs" 1; then record WARN "pi5 chrony system offset ${pi_chrony_offset}s"; else record FAIL "pi5 chrony system offset ${pi_chrony_offset}s"; fi
else
  record WARN "pi5 chrony system offset unavailable"
fi
pi_temp=$(kv_get temp_c "$RUN_DIR/pi52.kv" || true)
if [[ -n "$pi_temp" ]]; then
  if num_ge "$pi_temp" 80; then record FAIL "pi5 temperature ${pi_temp}C"; elif num_ge "$pi_temp" 70; then record WARN "pi5 temperature ${pi_temp}C"; else record PASS "pi5 temperature ${pi_temp}C"; fi
else
  record WARN "pi5 temperature unavailable"
fi
pi_throttled=$(kv_get throttled "$RUN_DIR/pi52.kv" || echo 0x0)
if hex_current_throttled "$pi_throttled"; then record WARN "pi5 current throttling flags ${pi_throttled}"; else record PASS "pi5 no current throttling flags ${pi_throttled}"; fi
l_size1=$(kv_get live_tmp_size "$RUN_DIR/pi51.kv" || echo 0)
l_size2=$(kv_get live_tmp_size "$RUN_DIR/pi52.kv" || echo 0)
if num_gt "$l_size2" "$l_size1"; then record PASS "pi5 live archive grew ${l_size1} -> ${l_size2} bytes"; else record FAIL "pi5 live archive did not grow ${l_size1} -> ${l_size2} bytes"; fi
raw_est=$(kv_get raw_tcp_established "$RUN_DIR/pi52.kv" || true)
fan_est=$(kv_get fanout_tcp_established "$RUN_DIR/pi52.kv" || true)
[[ "$raw_est" == yes ]] && record PASS "raw TCP stream established on 20200" || record WARN "raw TCP stream not observed on 20200"
[[ "$fan_est" == yes ]] && record PASS "Signal K fanout TCP established on 20201" || record WARN "Signal K fanout TCP not observed on 20201"
pi_mem=$(kv_get mem_available_mib "$RUN_DIR/pi52.kv" || echo 0)
if num_gt "$pi_mem" 1024; then record PASS "pi5 memory available ${pi_mem} MiB"; else record WARN "pi5 memory available ${pi_mem} MiB"; fi
raw_free=$(kv_get raw_free_mib "$RUN_DIR/pi52.kv" || echo 0)
raw_used=$(kv_get raw_used_pct "$RUN_DIR/pi52.kv" || echo 100)
if num_gt "$raw_free" 10240 && num_le "$raw_used" 80; then record PASS "pi5 raw archive free ${raw_free} MiB used ${raw_used}%"; else record WARN "pi5 raw archive free ${raw_free} MiB used ${raw_used}%"; fi
say ""
say "## Signal K API freshness"
if curl -fsS --max-time 5 "$PI5_SIGNALK_URL/signalk/v1/api/vessels/self" > "$RUN_DIR/vessel.json"; then
  node - "$RUN_DIR/vessel.json" "$FRESH_SEC" "$MASTERBUS_FRESH_SEC" <<'NODE' > "$RUN_DIR/signalk_api.kv"
const fs = require('fs')
const file = process.argv[2]
const freshSec = Number(process.argv[3])
const masterFreshSec = Number(process.argv[4])
const vessel = JSON.parse(fs.readFileSync(file, 'utf8'))
const now = Date.now()
const rows = []
function walk(node, path = []) {
  if (!node || typeof node !== 'object') return
  if (Object.prototype.hasOwnProperty.call(node, 'value') && node.$source) {
    rows.push({ path: path.join('.'), source: node.$source, timestamp: node.timestamp || null })
  }
  for (const [key, child] of Object.entries(node)) {
    if (['value', 'timestamp', '$source', 'meta', 'values', 'pgn'].includes(key)) continue
    walk(child, path.concat(key))
  }
}
walk(vessel)
const raw = rows.filter(r => String(r.source).startsWith('picanm-raw-candump-fanout') && r.timestamp)
const mb = rows.filter(r => (r.source === 'masterbus' || String(r.source).startsWith('masterbus.')) && r.timestamp)
function minAge(list) {
  if (!list.length) return null
  return Math.min(...list.map(r => (now - Date.parse(r.timestamp)) / 1000).filter(Number.isFinite))
}
function countFresh(list, maxAge) {
  return list.filter(r => Number.isFinite(Date.parse(r.timestamp)) && ((now - Date.parse(r.timestamp)) / 1000) <= maxAge).length
}
const rawAge = minAge(raw)
const mbAge = minAge(mb)
console.log(`raw_path_count=${raw.length}`)
console.log(`raw_fresh_count=${countFresh(raw, freshSec)}`)
console.log(`raw_min_age_sec=${rawAge == null ? '' : rawAge.toFixed(1)}`)
console.log(`masterbus_path_count=${mb.length}`)
console.log(`masterbus_fresh_count=${countFresh(mb, masterFreshSec)}`)
console.log(`masterbus_min_age_sec=${mbAge == null ? '' : mbAge.toFixed(1)}`)
NODE
  raw_count=$(kv_get raw_path_count "$RUN_DIR/signalk_api.kv" || echo 0)
  raw_fresh=$(kv_get raw_fresh_count "$RUN_DIR/signalk_api.kv" || echo 0)
  raw_age=$(kv_get raw_min_age_sec "$RUN_DIR/signalk_api.kv" || echo '')
  raw_ratio=$(awk -v f="$raw_fresh" -v c="$raw_count" 'BEGIN { if (c > 0) printf "%.0f", (100*f/c); else print 0 }')
  if num_gt "$raw_count" 0 && num_ge "$raw_ratio" 80; then record PASS "Signal K raw-feed paths fresh: ${raw_fresh}/${raw_count} (${raw_ratio}%), newest age ${raw_age}s"; elif num_gt "$raw_fresh" 0; then record WARN "Signal K raw-feed paths partly fresh: ${raw_fresh}/${raw_count} (${raw_ratio}%), newest age ${raw_age}s"; else record FAIL "Signal K raw-feed paths not fresh: ${raw_fresh}/${raw_count}"; fi
  mb_count=$(kv_get masterbus_path_count "$RUN_DIR/signalk_api.kv" || echo 0)
  mb_fresh=$(kv_get masterbus_fresh_count "$RUN_DIR/signalk_api.kv" || echo 0)
  mb_age=$(kv_get masterbus_min_age_sec "$RUN_DIR/signalk_api.kv" || echo '')
  mb_ratio=$(awk -v f="$mb_fresh" -v c="$mb_count" 'BEGIN { if (c > 0) printf "%.0f", (100*f/c); else print 0 }')
  if num_gt "$mb_count" 0 && num_ge "$mb_ratio" 80; then record PASS "MasterBus vessel paths fresh: ${mb_fresh}/${mb_count} (${mb_ratio}%), newest age ${mb_age}s"; elif num_gt "$mb_fresh" 0; then record WARN "MasterBus vessel paths partly fresh: ${mb_fresh}/${mb_count} (${mb_ratio}%), newest age ${mb_age}s"; else record FAIL "MasterBus vessel paths not fresh: ${mb_fresh}/${mb_count}"; fi
else
  record FAIL "cannot fetch pi5 Signal K vessel API"
fi

say ""
say "## Summary"
say "PASS=$pass WARN=$warn FAIL=$fail"
if (( fail > 0 )); then
  exit 2
fi
if (( warn > 0 )); then
  exit 1
fi
exit 0
