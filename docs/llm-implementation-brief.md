# LLM implementation brief

Use this file before changing code or services.

## Mission

Turn `picanm` into a raw NMEA 2000 acquisition edge. Run decoding, Signal K, MasterBus, TimescaleDB/Postgres, Grafana, and analysis on `pi5nvme`.

## Source material

Preserve these first:

```text
picanm:/var/log/n2k/        raw NMEA 2000 candump spool
pi5nvme:/srv/boat/raw-n2k/  mirrored/received raw NMEA 2000 archive
pi5nvme:/srv/boat/masterbus/ MasterBus discovery/config/snapshots
repo: docs/, scripts/, SQL migrations, systemd units, config templates
```

Treat these as derived and rebuildable while experimental:

```text
Signal K state/cache
TimescaleDB decoded rows
Signal K measurement rows
inventories/summaries/views
Grafana dashboards
optional sidecar files
```

## Current architecture

```text
picanm:
  can0 + raw candump logger + raw forwarder connected to pi5nvme:20200 + minimal Signal K on :3000

pi5nvme:
  fat Signal K on :3001 fed by picanm Signal K during transition
  MasterBus USB via masterbus-signalk
  PostgreSQL/TimescaleDB
  Grafana
  raw log mirror/importers/collectors
  live raw candump receiver on :20200 writing /srv/boat/raw-n2k/live/
```

## Target architecture

```text
picanm:
  can0
  raw candump logger
  raw candump forwarder
  health checks only
  no Signal K after validation

pi5nvme:
  raw archive receiver active on TCP 20200
  primary Signal K
  MasterBus USB
  TimescaleDB/Postgres
  Grafana
  import/inventory/rebuild tooling
```

## Proven in latest implementation slice

- `picanm` raw logger/forwarder services are deployed and active.
- `pi5nvme` raw receiver is deployed and active on TCP `20200`.
- Live raw candump lines are being written under `/srv/boat/raw-n2k/live/`.
- `analyzerjs` decoded a received live-stream sample.
- MasterBus snapshot capture ran under `/srv/boat/masterbus/`.

## Do next

1. Determine the exact Signal K/canboat input method for consuming the raw stream on `pi5nvme`.
2. Configure pi5 Signal K to consume that raw stream without using `picanm:3000` as the N2K source.
3. Run old and new feeds in parallel.
4. Compare PGNs, Signal K paths, timestamps, and key values.
5. Disable `picanm` Signal K only after the go/no-go checklist passes.

## Do not do yet

- Do not replace `picanm` with CANPico.
- Do not move MasterBus to `picanm` unless wiring forces it.
- Do not build full JSONL copies of every raw frame.
- Do not design complex per-domain schemas.
- Do not write proprietary PGN parsers without a concrete use case.
- Do not enable NMEA 2000 transmit/control.
- Do not make Signal K or TimescaleDB the source of truth for N2K.

## Go/no-go for disabling `picanm` Signal K

All must pass:

- `picanm` writes continuous raw candump logs with edge timestamps.
- `pi5nvme` receives and archives live raw frames.
- Missed forwarder periods recover from mirrored spool files.
- pi5 Signal K receives N2K data without `picanm:3000`.
- TimescaleDB Signal K and decoded N2K row counts increase.
- Key values match during overlap: position, COG/SOG, heading, wind, depth, STW, rudder, AIS.
- MasterBus paths remain present on pi5 Signal K.
- CAN errors/drops do not increase.
- Rollback is documented and tested.

## Read for detail

- `docs/plan.md`
- `docs/2026-07-03-edge-backend-migration-plan.md`
- `docs/rebuild-from-source-material.md`
- `docs/2026-07-03-boat-discovery-and-decoder-inventory.md`
