#!/bin/bash
set -euo pipefail

IFACE=${IFACE:-can0}
DEST_HOST=${DEST_HOST:-pi5nvme}
DEST_PORT=${DEST_PORT:-20200}
RETRY_SEC=${RETRY_SEC:-5}

# Forward the same candump-compatible records as the local logger. Local logging
# is a separate service and must remain the source of truth if forwarding fails.
while true; do
  if ! timeout 5 bash -c "</dev/tcp/${DEST_HOST}/${DEST_PORT}" 2>/dev/null; then
    echo "n2k raw forwarder cannot connect to ${DEST_HOST}:${DEST_PORT}; retrying in ${RETRY_SEC}s" >&2
    sleep "$RETRY_SEC"
    continue
  fi

  set +e
  candump -L "$IFACE" | socat -u - "TCP:${DEST_HOST}:${DEST_PORT},connect-timeout=10"
  rc=$?
  set -e
  echo "n2k raw forwarder disconnected/exited rc=${rc}; retrying in ${RETRY_SEC}s" >&2
  sleep "$RETRY_SEC"
done
