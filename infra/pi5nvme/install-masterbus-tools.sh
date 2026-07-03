#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root, e.g. sudo $0" >&2
  exit 1
fi

apt-get update
apt-get install -y build-essential pkg-config libudev-dev curl ca-certificates git

# Install/update Rust for the jack user; masterbus currently requires Rust 1.85+ / edition 2024.
if [ ! -x /home/jack/.cargo/bin/rustup ]; then
  sudo -u jack bash -lc 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal'
fi
sudo -u jack bash -lc 'rustup update stable'

sudo -u jack mkdir -p /home/jack/src
if [ ! -d /home/jack/src/masterbus/.git ]; then
  sudo -u jack git clone https://github.com/keesverruijt/masterbus.git /home/jack/src/masterbus
else
  sudo -u jack bash -lc 'cd /home/jack/src/masterbus && git pull --ff-only'
fi

sudo -u jack bash -lc 'cd /home/jack/src/masterbus && cargo install --path crates/masterbus-tools --locked'

install -m 0755 /home/jack/.cargo/bin/masterbus-tui /usr/local/bin/masterbus-tui
install -m 0755 /home/jack/.cargo/bin/masterbus-signalk /usr/local/bin/masterbus-signalk
install -m 0755 /home/jack/.cargo/bin/masterbus-set-field /usr/local/bin/masterbus-set-field

install -d -m 0755 /etc/default/masterbus /etc/default/masterbus-signalk /var/lib/masterbus /srv/boat/masterbus
chown jack:jack /srv/boat/masterbus
install -m 0755 infra/pi5nvme/scripts/capture-masterbus-snapshot.sh /usr/local/bin/capture-masterbus-snapshot
install -m 0644 infra/pi5nvme/masterbus/config.ini /etc/default/masterbus/config.ini
install -m 0644 infra/pi5nvme/masterbus/masterbus-signalk.env /etc/default/masterbus-signalk/config
install -m 0644 /home/jack/src/masterbus/crates/masterbus-tools/etc/masterbus-signalk.service /etc/systemd/system/masterbus-signalk.service
install -m 0644 infra/pi5nvme/udev/70-mastervolt-masterbus.rules /etc/udev/rules.d/70-mastervolt-masterbus.rules

udevadm control --reload-rules
systemctl daemon-reload
# Do not start automatically until the USB interface is plugged in and we have verified discovery.
systemctl disable --now masterbus-signalk.service || true

echo "MasterBus tools installed. After plugging in the Mastervolt USB interface:"
echo "  lsusb | grep -i 1a64"
echo "  masterbus-tui"
echo "  sudo systemctl start masterbus-signalk"
