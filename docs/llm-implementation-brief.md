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
repo docs/scripts/sql/systemd
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
  can0 + raw logs + raw forwarder + minimal Signal K on :3000

pi5nvme:
  fat Signal K on :3001
  MasterBus USB via masterbus-signalk
  PostgreSQL/TimescaleDB
  Grafana
  raw log mirror/importers/collectors
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
  raw archive receiver
  primary Signal K
  MasterBus USB
  TimescaleDB/Postgres
  Grafana
  import/inventory/rebuild tooling
```

## Do next

1. Deploy the `pi5nvme` raw stream receiver and health scripts from `infra/pi5nvme/`.
2. Verify edge timestamps and clock sync on both hosts.
3. Capture forwarded raw candump lines into files on `pi5nvme`.
4. Capture a MasterBus snapshot/export on `pi5nvme`.
5. Prove canboatjs/analyzerjs decodes the received stream.
6. Prove pi5 Signal K can consume the raw stream or document the bridge needed.
7. Run old and new feeds in parallel.
8. Compare PGNs, Signal K paths, timestamps, and key values.
9. Disable `picanm` Signal K only after the go/no-go checklist passes.

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
