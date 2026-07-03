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

## Safety gate after 2026-07-03 pi5nvme incident

Before any further `pi5nvme` implementation, investigate the overload/thermal incident documented in `docs/2026-07-03-pi5nvme-incident-and-picanm-status.md`.

Do not run importers, backfills, canboat/analyzer bulk jobs, database-heavy jobs, or service restarts on `pi5nvme` until the incident is understood and resource limits are in place.

`picanm` remains the safe active acquisition edge and is still writing raw N2K logs locally. While `pi5nvme` is unavailable, use `docs/picanm-offline-operations.md` and only run low-impact picanm health/spool checks.

## Proven in latest implementation slice

- `picanm` raw logger/forwarder services are deployed and active.
- `pi5nvme` raw receiver is deployed and active on TCP `20200`.
- Live raw candump lines are being written under `/srv/boat/raw-n2k/live/`.
- `analyzerjs` decoded a received live-stream sample.
- MasterBus snapshot capture ran under `/srv/boat/masterbus/`.
- Exact Signal K/canboat raw input method is proven: Signal K `providers/simple` with `type: "NMEA2000"`, `subOptions.type: "n2k-ip-gateway-canboatjs"`, `format: "candump3"`, connected to a read-only local fanout on `127.0.0.1:20201`.
- `pi5nvme` raw receiver now archives the picanm stream from TCP `20200` and fans the same candump lines to Signal K on localhost `20201`.
- pi5 Signal K has both feeds enabled for overlap: old `picanm:3000` Signal K and new raw candump/canboat feed.

## Do next

1. Compare old and new feeds in parallel: PGNs, Signal K paths, timestamps, and key values.
2. Confirm TimescaleDB decoded N2K import continues across completed raw segments from the new receiver.
3. Confirm MasterBus paths remain present while the raw N2K feed is active.
4. Disable `picanm` Signal K only after the go/no-go checklist passes.

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
