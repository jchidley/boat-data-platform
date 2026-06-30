#!/bin/bash
set -euo pipefail

SOURCE_HOST=${SOURCE_HOST:-picanm}
SOURCE_DIR=${SOURCE_DIR:-/var/log/n2k/}
DEST_DIR=${DEST_DIR:-/srv/boat/raw-n2k/}

mkdir -p "$DEST_DIR"

# picanm writes active segments as *.tmp and atomically renames completed files to
# *.candump.log.gz, so --ignore-existing is safe here: completed files are immutable.
rsync -av --ignore-existing --include='*.candump.log.gz' --exclude='*' \
  "${SOURCE_HOST}:${SOURCE_DIR}" "$DEST_DIR"
