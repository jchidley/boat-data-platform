# pi5nvme setup summary — 2026-06-30

`pi5nvme` is now the heavier boat-data platform host. `picanm` remains the bare-bones NMEA 2000 gateway/logger.

## Installed on pi5nvme

- PostgreSQL 15
- TimescaleDB extension for PostgreSQL
- Grafana 13.1.0
- `rsync` raw-log mirror from `picanm`

## Storage layout

```text
/srv/boat/raw-n2k/      # mirrored completed candump gzip logs from picanm
/srv/boat/processed/    # reserved for decoded/processed outputs
/etc/boat-data-platform # local secrets/config, root-only where needed
```

## Raw log mirror

Installed files:

```text
/usr/local/bin/boat-raw-log-mirror
/etc/systemd/system/boat-raw-log-mirror.service
/etc/systemd/system/boat-raw-log-mirror.timer
```

The timer runs every 5 minutes and pulls completed immutable files from:

```text
picanm:/var/log/n2k/*.candump.log.gz
```

into:

```text
/srv/boat/raw-n2k/
```

The logger on `picanm` writes active segments as `.tmp` and renames them to `.candump.log.gz` only when complete, so `rsync --ignore-existing` is safe.

## SSH trust for mirroring

`pi5nvme` now has an SSH key for `jack`, and that key is authorized for `jack@picanm`, so the timer can pull logs without a password.

## PostgreSQL / TimescaleDB

Database:

```text
boatdata
```

Roles:

```text
boat_ingest      # intended for collectors/importers
grafana_reader   # intended for Grafana read-only queries
```

Passwords are stored on `pi5nvme` in:

```text
/etc/boat-data-platform/db.env
```

Initial Timescale hypertable:

```text
signal_k_measurements
```

Initial support table:

```text
raw_n2k_log_files
```

Verified TimescaleDB extension version:

```text
2.28.1
```

## Grafana

Grafana is running on `pi5nvme`:

```text
http://pi5nvme:3000/
```

The admin password was randomized and stored root-only in:

```text
/etc/boat-data-platform/grafana.env
```

A provisioned PostgreSQL datasource named `Boat TimescaleDB` points at the `boatdata` database with TimescaleDB mode enabled.

## Repository support files

The repo now contains install/configuration assets under:

```text
infra/pi5nvme/
```

Important files:

```text
infra/pi5nvme/install-pi5nvme.sh
infra/pi5nvme/boat-raw-log-mirror.sh
infra/pi5nvme/systemd/boat-raw-log-mirror.service
infra/pi5nvme/systemd/boat-raw-log-mirror.timer
infra/pi5nvme/sql/001_init_timescale.sql
```

## Current gap

TimescaleDB and Grafana are installed and ready, but the live Signal K collector is not yet implemented. Until that collector exists, Grafana will have the datasource but little/no measurement data except metadata we import later.

Next step: add a collector that subscribes to:

```text
ws://picanm:3000/signalk/v1/stream
```

and inserts deltas into `signal_k_measurements`.
