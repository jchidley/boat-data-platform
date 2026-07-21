#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root, e.g. sudo $0" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release rsync postgresql postgresql-contrib nodejs socat gzip chrony logrotate

install -d -m 0755 /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/timescale.gpg ]; then
  curl -fsSL https://packagecloud.io/timescale/timescaledb/gpgkey | gpg --dearmor -o /etc/apt/keyrings/timescale.gpg
fi
cat >/etc/apt/sources.list.d/timescale_timescaledb.list <<'LIST'
deb [signed-by=/etc/apt/keyrings/timescale.gpg] https://packagecloud.io/timescale/timescaledb/debian/ bookworm main
LIST

if [ ! -f /etc/apt/keyrings/grafana.gpg ]; then
  curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
fi
cat >/etc/apt/sources.list.d/grafana.list <<'LIST'
deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main
LIST

apt-get update
apt-get install -y timescaledb-2-postgresql-15 grafana

install -d -m 0755 /srv/boat/raw-n2k/live /srv/boat/masterbus /srv/boat/processed /etc/boat-data-platform
chown -R jack:jack /srv/boat
install -m 0755 "$SCRIPT_DIR/boat-raw-log-mirror.sh" /usr/local/bin/boat-raw-log-mirror
install -m 0755 "$SCRIPT_DIR/scripts/boat-n2k-stream-segment-writer.sh" /usr/local/bin/boat-n2k-stream-segment-writer
install -m 0755 "$SCRIPT_DIR/scripts/boat-n2k-raw-receiver.sh" /usr/local/bin/boat-n2k-raw-receiver
install -m 0755 "$SCRIPT_DIR/scripts/boat-n2k-raw-receiver.mjs" /usr/local/bin/boat-n2k-raw-receiver.mjs
install -m 0755 "$SCRIPT_DIR/scripts/check-pi5-boat-health.sh" /usr/local/bin/check-pi5-boat-health
install -m 0755 "$SCRIPT_DIR/scripts/check-derived-storage-pressure.sh" /usr/local/bin/check-derived-storage-pressure
install -m 0755 "$SCRIPT_DIR/scripts/capture-masterbus-snapshot.sh" /usr/local/bin/capture-masterbus-snapshot
install -m 0644 "$SCRIPT_DIR/systemd/boat-raw-log-mirror.service" /etc/systemd/system/boat-raw-log-mirror.service
install -m 0644 "$SCRIPT_DIR/systemd/boat-raw-log-mirror.timer" /etc/systemd/system/boat-raw-log-mirror.timer
install -m 0644 "$SCRIPT_DIR/systemd/boat-n2k-raw-receiver.service" /etc/systemd/system/boat-n2k-raw-receiver.service
install -m 0644 "$SCRIPT_DIR/systemd/boat-derived-storage-guard.service" /etc/systemd/system/boat-derived-storage-guard.service
install -m 0644 "$SCRIPT_DIR/systemd/boat-derived-storage-guard.timer" /etc/systemd/system/boat-derived-storage-guard.timer
# The old Signal K WebSocket JSONL logger is retained in the repository only as
# a comparison/fallback tool. Native decoded events are logged inside the single
# MasterBus USB owner installed by install-masterbus-tools.sh.
systemctl disable --now boat-masterbus-signalk-log.service 2>/dev/null || true
rm -f /etc/systemd/system/boat-masterbus-signalk-log.service
install -d -m 0755 /etc/logrotate.d
systemctl enable --now postgresql
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='boatdata'" | grep -q 1 || sudo -u postgres createdb boatdata
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='boat_ingest'" | grep -q 1 || sudo -u postgres createuser boat_ingest
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='grafana_reader'" | grep -q 1 || sudo -u postgres createuser grafana_reader

if ! grep -q '^BOAT_INGEST_PASSWORD=' /etc/boat-data-platform/db.env 2>/dev/null; then
  umask 077
  cat >/etc/boat-data-platform/db.env <<ENV
BOAT_INGEST_PASSWORD=$(openssl rand -base64 36)
GRAFANA_READER_PASSWORD=$(openssl rand -base64 36)
ENV
fi
. /etc/boat-data-platform/db.env
sudo -u postgres psql <<SQL
ALTER ROLE boat_ingest LOGIN PASSWORD '${BOAT_INGEST_PASSWORD}';
ALTER ROLE grafana_reader LOGIN PASSWORD '${GRAFANA_READER_PASSWORD}';
ALTER DATABASE boatdata OWNER TO postgres;
ALTER SYSTEM SET shared_preload_libraries = 'timescaledb';
SQL
systemctl restart postgresql
for sql in "$SCRIPT_DIR"/sql/*.sql; do
  sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d boatdata -f "$sql"
done

install -d -m 0755 /etc/grafana/provisioning/datasources /etc/grafana/provisioning/dashboards /etc/grafana/dashboards/boat-data-platform
install -m 0644 "$SCRIPT_DIR/grafana/provisioning/dashboards/boatdata.yaml" /etc/grafana/provisioning/dashboards/boatdata.yaml
install -m 0644 "$SCRIPT_DIR/grafana/dashboards/boat-history.json" /etc/grafana/dashboards/boat-data-platform/boat-history.json
cat >/etc/grafana/provisioning/datasources/boatdata-postgres.yaml <<YAML
apiVersion: 1

datasources:
  - name: Boat TimescaleDB
    uid: boat-timescaledb
    type: postgres
    access: proxy
    url: localhost:5432
    database: boatdata
    user: grafana_reader
    secureJsonData:
      password: ${GRAFANA_READER_PASSWORD}
    jsonData:
      sslmode: disable
      postgresVersion: 1500
      timescaledb: true
YAML
chown root:grafana /etc/grafana/provisioning/datasources/boatdata-postgres.yaml
chmod 0640 /etc/grafana/provisioning/datasources/boatdata-postgres.yaml

if [ -f "$REPO_ROOT/package.json" ]; then
  sudo -u jack bash -lc "cd '$REPO_ROOT' && npm install"
fi

# Enforce the two-path end state: Signal K is live-only; PostgreSQL is fed from
# typed N2K/MasterBus source conversion, not a Signal K telemetry collector.
systemctl disable --now boat-signalk-collector.service 2>/dev/null || true
rm -f /etc/systemd/system/boat-signalk-collector.service
systemctl daemon-reload
systemctl enable --now chrony.service || true
systemctl enable --now boat-raw-log-mirror.timer boat-n2k-raw-receiver.service boat-derived-storage-guard.timer grafana-server
if ! grep -q '^GRAFANA_ADMIN_PASSWORD=' /etc/boat-data-platform/grafana.env 2>/dev/null; then
  umask 077
  grafana_pw=$(openssl rand -base64 24)
  echo "GRAFANA_ADMIN_PASSWORD=${grafana_pw}" >/etc/boat-data-platform/grafana.env
  grafana cli admin reset-admin-password "$grafana_pw" >/dev/null
fi

systemctl start boat-raw-log-mirror.service || true

echo "pi5nvme boat data platform base install complete. Grafana: http://$(hostname):3000/"
echo "Grafana admin password is stored root-only in /etc/boat-data-platform/grafana.env"
