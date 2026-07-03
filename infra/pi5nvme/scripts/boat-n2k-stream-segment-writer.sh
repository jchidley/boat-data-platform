#!/bin/bash
set -euo pipefail

DEST_DIR=${DEST_DIR:-/srv/boat/raw-n2k/live}
IFACE=${IFACE:-can0}
COMPRESSOR=${COMPRESSOR:-gzip}

mkdir -p "$DEST_DIR"

# Read candump-compatible lines from stdin and write hourly backend-received
# segments. Rotate without forking once per frame.
awk -v dest="$DEST_DIR" -v iface="$IFACE" -v compressor="$COMPRESSOR" '
function segment() { return strftime("%Y%m%dT%H0000Z", systime(), 1) }
function open_segment(seg) {
  current = seg
  out = dest "/" iface "-" current ".candump.log.tmp"
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
/^\([0-9]+\.[0-9]+\)[[:space:]]+[^[:space:]]+[[:space:]]+[0-9A-Fa-f]+#/ {
  seg = segment()
  if (seg != current) rotate(seg)
  print $0 >> out
}
END { if (out != "") close(out) }
'
