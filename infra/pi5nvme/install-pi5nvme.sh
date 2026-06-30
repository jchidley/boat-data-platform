#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root, e.g. sudo $0" >&2
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release rsync postgresql postgresql-contrib

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

install -d -m 0755 /srv/boat/raw-n2k /srv/boat/processed /etc/boat-data-platform
chown -R jack:jack /srv/boat
install -m 0755 infra/pi5nvme/boat-raw-log-mirror.sh /usr/local/bin/boat-raw-log-mirror
install -m 0644 infra/pi5nvme/systemd/boat-raw-log-mirror.service /etc/systemd/system/boat-raw-log-mirror.service
install -m 0644 infra/pi5nvme/systemd/boat-raw-log-mirror.timer /etc/systemd/system/boat-raw-log-mirror.timer

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
sudo -u postgres psql -d boatdata -f infra/pi5nvme/sql/001_init_timescale.sql

install -d -m 0755 /etc/grafana/provisioning/datasources
cat >/etc/grafana/provisioning/datasources/boatdata-postgres.yaml <<YAML
apiVersion: 1

datasources:
  - name: Boat TimescaleDB
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

systemctl daemon-reload
systemctl enable --now boat-raw-log-mirror.timer grafana-server

if ! grep -q '^GRAFANA_ADMIN_PASSWORD=' /etc/boat-data-platform/grafana.env 2>/dev/null; then
  umask 077
  grafana_pw=$(openssl rand -base64 24)
  echo "GRAFANA_ADMIN_PASSWORD=${grafana_pw}" >/etc/boat-data-platform/grafana.env
  grafana cli admin reset-admin-password "$grafana_pw" >/dev/null
fi

systemctl start boat-raw-log-mirror.service || true

echo "pi5nvme boat data platform base install complete. Grafana: http://$(hostname):3000/"
echo "Grafana admin password is stored root-only in /etc/boat-data-platform/grafana.env"
