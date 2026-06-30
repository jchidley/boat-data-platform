#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root, e.g. sudo $0" >&2
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl gnupg

install -d -m 0755 /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/nodesource.gpg ]; then
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
fi
cat >/etc/apt/sources.list.d/nodesource.list <<'LIST'
deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main
LIST

apt-get update
apt-get install -y nodejs
npm install -g signalk-server

install -d -o jack -g jack -m 0755 /srv/boat/signalk

if [ ! -f /srv/boat/signalk/settings.json ]; then
  install -o jack -g jack -m 0644 infra/pi5nvme/signalk-settings.json /srv/boat/signalk/settings.json
fi

# Install useful webapps on the fat Signal K host, not on picanm.
sudo -u jack npm --prefix /srv/boat/signalk install \
  @mxtommy/kip \
  @signalk/freeboard-sk \
  @signalk/instrumentpanel

install -m 0644 infra/pi5nvme/systemd/signalk-pi5nvme.service /etc/systemd/system/signalk-pi5nvme.service
systemctl daemon-reload
systemctl enable --now signalk-pi5nvme.service

echo "Fat Signal K installed on pi5nvme: http://$(hostname):3001/"
