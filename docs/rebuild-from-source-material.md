# Rebuild from source material

This runbook defines what must be preserved and how the boat data platform end state is rebuilt if derived state is deleted or a host is reinstalled.

## Rebuild principle

Preserve source material and documentation; treat Signal K state and PostgreSQL history as rebuildable outputs.

Source material:

```text
NMEA 2000:
  raw candump logs from picanm

MasterBus/Mastervolt:
  discovery/config/mapping snapshots from pi5nvme
  mapped JSONL replay logs until a rawer native event source is available

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

Important caveat: MasterBus history cannot be rebuilt from NMEA 2000 candump logs. Preserve mapped JSONL replay logs and snapshots now, and pursue a rawer native event source. PostgreSQL remains derived; it must not be the only copy of MasterBus historical source material.

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
boat-n2k-raw-receiver.service
boat-raw-log-mirror.timer
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

Expected core layers:

```text
n2k_raw_files_v2                  raw-file provenance and import status
n2k_<pgn-shaped>_v2               selected typed N2K history
masterbus_*_samples_v1            selected typed MasterBus history
health_observations               bounded health evidence
```

Recreate inventory and app-facing views from typed tables.

### 5. Re-import selected raw N2K history

Historical conversion is a high CPU, memory, disk I/O, and PostgreSQL workload. Run it offline or on staging with explicit resource and disk limits.

Current rebuild path:

```text
raw candump.gz
  -> offline/staging analyzer/canboat
  -> PGN-shaped TSV staging files
  -> PostgreSQL COPY into unlogged staging tables
  -> selected typed PGN tables with raw-file provenance
  -> summaries/import status
```

The wrapper, merge SQL and supported typed PGNs have bounded sample validation. Research output defaults to `none`; full-file use requires explicit permission and resource limits. Do not run a broad rebuild until typed-only versus envelope-plus-typed storage has been measured and approved.

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
raw N2K files present and checksummed
Signal K current N2K and MasterBus paths fresh
selected typed N2K rows traceable to raw_file_id/message_index
no broad research EAV rows from normal imports
MasterBus replay logs/snapshots present and selected typed rows rebuildable from them
known devices/PGNs visible in typed inventory views
```

## Documentation update rule

After a rebuild or rediscovery, update:

```text
docs/llm-implementation-brief.md
docs/plan.md
docs/2026-07-03-boat-discovery-and-decoder-inventory.md
```

if paths, services, devices, decoders, or known gaps changed.
