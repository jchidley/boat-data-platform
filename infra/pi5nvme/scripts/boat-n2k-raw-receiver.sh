#!/bin/bash
set -euo pipefail

SCRIPT=${SCRIPT:-/usr/local/bin/boat-n2k-raw-receiver.mjs}

# Accept the raw candump line stream from picanm on LISTEN_PORT, archive it to
# hourly files, and expose a read-only localhost fanout on FANOUT_PORT for
# Signal K/canboat's n2k-ip-gateway input.
exec /usr/bin/node "$SCRIPT"
