# Rebuild from source material

This runbook defines what must be preserved and how the experimental boat data platform should be rebuilt if derived state is deleted or a host is reinstalled.

## Rebuild principle

The system is experimental. Preserve source material and documentation; treat derived stores as rebuildable.

Source material:

```text
NMEA 2000:
  raw candump logs from picanm

MasterBus/Mastervolt:
  discovery/config/mapping snapshots from pi5nvme

Repository:
  scripts, SQL, systemd units, docs, and config templates
```

Derived/rebuildable:

```text
Signal K current state/cache
TimescaleDB decoded N2K rows
TimescaleDB Signal K measurement rows
inventory tables/views
summary tables/views
Grafana dashboards, if provisioned from repo
optional sidecar summaries
```

Important caveat: MasterBus historical values cannot be rebuilt from NMEA 2000 candump logs. If long-term MasterBus history matters, it must be retained in TimescaleDB or captured separately. The minimum source-material requirement is enough MasterBus discovery/config data to rediscover and remap the system.

## Must-preserve locations

### picanm

```text
/var/log/n2k/
```

Local raw NMEA 2000 candump spool.

### pi5nvme

```text
/srv/boat/raw-n2k/
/srv/boat/masterbus/
/srv/boat/signalk/
/etc/boat-data-platform/
```

Expected roles:

- `/srv/boat/raw-n2k/`: canonical mirrored/received raw N2K archive.
- `/srv/boat/masterbus/`: MasterBus discovery/config/snapshot archive.
- `/srv/boat/signalk/`: Signal K config and plugin/app state.
- `/etc/boat-data-platform/`: local environment files and credential references.

Secrets/passwords are not committed to the repo. The repo should document where they live, not contain plaintext secrets.

## Minimum rebuild inputs

A rebuild should need only:

1. this repository;
2. raw N2K candump logs from `/srv/boat/raw-n2k/` or `/var/log/n2k/`;
3. MasterBus snapshots/configs from `/srv/boat/masterbus/` and/or current USB rediscovery;
4. local credential/env files from `/etc/boat-data-platform/` or regenerated equivalents.

## Rebuild outline

### 1. Restore/install base services on pi5nvme

Use the repo infrastructure scripts where possible:

```text
infra/pi5nvme/install-pi5nvme.sh
infra/pi5nvme/install-signalk-fat.sh
infra/pi5nvme/install-masterbus-tools.sh
```

Expected services after install:

```text
postgresql
grafana-server
signalk-pi5nvme
masterbus-signalk
boat-raw-log-mirror.timer
boat-signalk-collector.service
boat-raw-n2k-import.timer
```

### 2. Restore raw N2K archive

Place raw logs under:

```text
/srv/boat/raw-n2k/
```

Use canonical names where possible:

```text
can0-YYYYMMDDTHH0000Z.candump.log.gz
```

Verify integrity with stored checksums/manifests where available.

### 3. Restore or rediscover MasterBus

Restore saved MasterBus config/snapshots to:

```text
/srv/boat/masterbus/
/etc/default/masterbus/
/etc/default/masterbus-signalk/
```

Then verify USB discovery:

```text
lsusb
ls -l /dev/hidraw*
masterbus-tui
systemctl status masterbus-signalk.service
```

If mappings changed, save a fresh discovery/config snapshot before relying on derived Signal K paths.

### 4. Recreate database schema

Run committed SQL migrations from:

```text
infra/pi5nvme/sql/
```

Expected core tables:

```text
boatdata.signal_k_measurements
boatdata.n2k_decoded_messages
boatdata.raw_n2k_log_files
```

Expected/desired rebuildable inventory tables or views:

```text
boatdata.masterbus_snapshots
boatdata.n2k_pgn_inventory
boatdata.n2k_source_inventory
boatdata.n2k_decode_examples
boatdata.boat_data_summaries
boatdata.data_quality_observations
```

### 5. Re-import raw N2K

Use the raw importer:

```text
npm run import:n2k
```

or the systemd timer/service:

```text
boat-raw-n2k-import.service
boat-raw-n2k-import.timer
```

The importer should be idempotent: rerunning should not duplicate rows for the same raw file/segment.

### 6. Rebuild inventories and summaries

Use inventory tooling, currently:

```text
npm run inventory:n2k
```

Future tooling should populate compact SQL views/tables first; optional markdown/json sidecars can then be generated from SQL.

### 7. Restore Signal K/Grafana convenience layers

Signal K and Grafana are useful but not the source of truth.

Restore or regenerate:

```text
/srv/boat/signalk/
Grafana datasource/dashboard provisioning
Signal K app/plugin configuration
```

Then check:

```text
http://pi5nvme:3001/
http://pi5nvme:3000/
```

### 8. Verify rebuild

Minimum verification:

```text
raw N2K files present on pi5nvme
raw file manifests/checksums available or regenerated
n2k_decoded_messages row count increasing after import
signal_k_measurements row count increasing while live Signal K runs
MasterBus USB visible or snapshots restored
known devices/PGNs visible in inventory views/docs
```

## Documentation update rule

After a rebuild or rediscovery, update:

```text
docs/plan.md
docs/2026-07-03-edge-backend-migration-plan.md
docs/2026-07-03-boat-discovery-and-decoder-inventory.md
```

if paths, services, devices, decoders, or known gaps changed.
