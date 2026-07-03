#!/bin/bash
set -euo pipefail

IFACE=${IFACE:-can0}
LOG_DIR=${LOG_DIR:-/var/log/n2k}
COMPRESSOR=${COMPRESSOR:-gzip}

mkdir -p "$LOG_DIR"

compress_file() {
  local f=$1
  [ -s "$f" ] || { rm -f "$f"; return 0; }
  case "$COMPRESSOR" in
    zstd) zstd -q --rm "$f" ;;
    gzip|*) gzip -n -f "$f" ;;
  esac
}

current_hour=$(date -u +%Y%m%dT%H0000Z)
find "$LOG_DIR" -maxdepth 1 -type f -name "${IFACE}-*.candump.log.tmp" ! -name "${IFACE}-${current_hour}.candump.log.tmp" -print0 |
  while IFS= read -r -d '' tmp; do
    final=${tmp%.tmp}
    mv -n "$tmp" "$final" || true
    [ -f "$final" ] && compress_file "$final"
  done

# candump -L emits SocketCAN log format with edge host timestamps:
#   (seconds.microseconds) can0 CANID#DATA
# Rotate by current UTC hour without forking once per frame. LOG_DIR/IFACE are
# intentionally constrained to simple system paths/names by the service file.
candump -L "$IFACE" | awk -v logdir="$LOG_DIR" -v iface="$IFACE" -v compressor="$COMPRESSOR" '
function segment() { return strftime("%Y%m%dT%H0000Z", systime(), 1) }
function open_segment(seg) {
  current = seg
  out = logdir "/" iface "-" current ".candump.log.tmp"
}
function rotate(seg, final, cmd) {
  if (out != "") {
    close(out)
    final = substr(out, 1, length(out)-4)
    system("mv -f " out " " final)
    if (compressor == "zstd") cmd = "zstd -q --rm " final; else cmd = "gzip -n -f " final
    system(cmd)
  }
  open_segment(seg)
}
{
  seg = segment()
  if (seg != current) rotate(seg)
  print $0 >> out
}
END { if (out != "") close(out) }
'
