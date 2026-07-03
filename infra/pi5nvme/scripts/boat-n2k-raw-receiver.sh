#!/bin/bash
set -euo pipefail

LISTEN_PORT=${LISTEN_PORT:-20200}
DEST_DIR=${DEST_DIR:-/srv/boat/raw-n2k/live}

mkdir -p "$DEST_DIR"

# Accept raw candump line streams from picanm. Each connection is handled by a
# segment writer that keeps hourly compressed candump files. This receiver does
# not decode and is safe to run before Signal K raw-stream ingestion is proven.
exec socat -u "TCP-LISTEN:${LISTEN_PORT},reuseaddr,fork" "SYSTEM:DEST_DIR=${DEST_DIR} /usr/local/bin/boat-n2k-stream-segment-writer"
