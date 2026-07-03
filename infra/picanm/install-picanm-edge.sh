#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root, e.g. sudo $0" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

apt-get update
apt-get install -y can-utils socat rsync chrony gzip iproute2

install -d -m 0755 /var/log/n2k
install -m 0755 "$SCRIPT_DIR/scripts/n2k-raw-log-writer.sh" /usr/local/bin/n2k-raw-log-writer
install -m 0755 "$SCRIPT_DIR/scripts/n2k-raw-forwarder.sh" /usr/local/bin/n2k-raw-forwarder
install -m 0755 "$SCRIPT_DIR/scripts/check-picanm-health.sh" /usr/local/bin/check-picanm-health
install -m 0644 "$SCRIPT_DIR/systemd/can0-nmea2000.service" /etc/systemd/system/can0-nmea2000.service
install -m 0644 "$SCRIPT_DIR/systemd/n2k-raw-logger.service" /etc/systemd/system/n2k-raw-logger.service
install -m 0644 "$SCRIPT_DIR/systemd/n2k-raw-forwarder.service" /etc/systemd/system/n2k-raw-forwarder.service

systemctl daemon-reload
systemctl enable --now chrony.service || true
systemctl enable can0-nmea2000.service n2k-raw-logger.service n2k-raw-forwarder.service
systemctl restart can0-nmea2000.service n2k-raw-logger.service n2k-raw-forwarder.service

echo "picanm N2K edge services installed. Check with: check-picanm-health"
