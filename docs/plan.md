# Boat data platform plan

## Target architecture

```text
NMEA 2000 backbone
    ↓
PiCAN-M HAT on picanm / Pi 3 A+
    ↓
picanm raw acquisition edge
    ├─ can0 at 250 kbit/s
    ├─ accurate edge timestamping
    ├─ compact raw candump logs/spool in /var/log/n2k/
    └─ lightweight raw CAN forwarding to pi5nvme
          ↓ raw stream / rsync fallback
pi5nvme data platform
    ├─ primary/fat Signal K server
    ├─ NMEA 2000 decoding via canboatjs/analyzerjs/Signal K
    ├─ MasterBus/Mastervolt USB integration
    ├─ PostgreSQL + TimescaleDB
    ├─ Grafana dashboards
    ├─ Signal K web apps/plugins
    └─ replay/import/inventory tooling
          ↓
iPad / iPhone / Android / Windows Surface / WSL clients
```

Detailed migration plan: [2026-07-03 edge/backend migration plan](2026-07-03-edge-backend-migration-plan.md).

Current boat/device/decoder inventory: [2026-07-03 boat discovery and decoder inventory](2026-07-03-boat-discovery-and-decoder-inventory.md).

Rebuild runbook: [rebuild from source material](rebuild-from-source-material.md).

## Design principles

1. Keep `picanm` simple and robust.
2. Keep collecting on `picanm` when `pi5nvme` is off.
3. Treat raw NMEA 2000 logs as the source of truth for N2K replay and reprocessing.
4. Preserve a MasterBus discovery/config snapshot trail; MasterBus cannot be rebuilt from N2K raw logs.
5. Timestamp frames as close to acquisition as possible on `picanm`.
6. Run heavier plugins, dashboards, databases, and experiments on `pi5nvme`.
7. Start read-only. Treat NMEA 2000 transmission as a separate safety-critical project.
8. Prefer reproducible scripts and committed configuration over one-off manual changes.

## picanm responsibilities

Steady-state target:

- Maintain `can0` at 250 kbit/s.
- Write edge-timestamped raw candump logs to `/var/log/n2k`.
- Rotate/compress logs safely.
- Forward a live raw CAN/candump stream to `pi5nvme`.
- Keep a local spool so collection survives `pi5nvme` outages.
- Expose only health/diagnostic information.
- Avoid Signal K apps, plugin experiments, databases, Grafana, or analysis jobs.

Current transition state:

- `picanm` runs raw logger/forwarder services from `infra/picanm/`.
- `picanm` forwards live candump-format frames to `pi5nvme.local:20200`; `.local` mDNS is used because bare `pi5nvme` resolves IPv6-first on the Starlink LAN while the receiver is currently IPv4-only.
- `picanm` still runs a minimal Signal K server on port `3000`.
- The migration plan is to make pi5 Signal K consume the raw stream, compare it with the old `picanm:3000` feed, then disable Signal K on `picanm` after validation.

## pi5nvme responsibilities

- Mirror raw logs from `picanm:/var/log/n2k/` to `/srv/boat/raw-n2k/`.
- Receive the live raw CAN stream from `picanm` on TCP `20200`, write `/srv/boat/raw-n2k/live/`, and expose a read-only localhost candump fanout on TCP `20201` for Signal K/canboat.
- Run the primary Signal K server on port `3001`.
- Decode NMEA 2000 data on the Pi 5 via Signal K/canboat `n2k-ip-gateway-canboatjs` using candump3 input from `127.0.0.1:20201`, not on the Pi 3 A+.
- Run MasterBus/Mastervolt USB tooling and publish it into Signal K.
- Preserve MasterBus discovery/config snapshots when devices or mappings change.
- Store normalized Signal K values in TimescaleDB.
- Store decoded raw N2K PGN history in TimescaleDB, but only during approved/resource-limited import windows; decoded backfill is disabled by default after the 2026-07-03 pi5 incident.
- Run Grafana and Signal K applications/plugins.
- Run inventory, replay, decoder comparison, and analysis tooling.

## Database layers

Use PostgreSQL with TimescaleDB on `pi5nvme`.

### Signal K normalized values

```text
boatdata.signal_k_measurements
```

Purpose: app-friendly historical path/value data from Signal K.

### Decoded N2K messages

```text
boatdata.n2k_decoded_messages
```

Purpose: decoded PGN-level history from raw candump logs/streams.

### Raw file/import inventory

```text
boatdata.raw_n2k_log_files
```

Purpose: track mirrored raw files, import status, first/last timestamps, checksums, and errors.

### MasterBus snapshots

```text
boatdata.masterbus_snapshots
```

Purpose: track MasterBus/Mastervolt discovery/config snapshots, because MasterBus cannot be rebuilt from N2K raw logs.

Future option: add a raw CAN frame hypertable if direct SQL access to every raw frame is useful.

## Grafana priorities

Build health/freshness dashboards before presentation dashboards:

- latest raw frame received from `picanm`
- latest mirrored raw log age
- CAN RX errors/drops
- picanm disk, memory, and clock offset
- Signal K path freshness
- Timescale collector freshness
- raw importer backlog/status, without running importer/backfill during live validation

Boat/instrument dashboards:

- GPS track and GNSS quality
- wind speed/angle history
- depth and water temperature
- heading vs COG
- SOG vs STW
- rudder angle
- AIS activity
- electrical/MasterBus state of charge and inverter/charger status

## Completed work

- PostgreSQL 15 installed on `pi5nvme`.
- TimescaleDB installed and enabled in the `boatdata` database.
- Initial Signal K hypertable created.
- Grafana installed and provisioned with a Boat TimescaleDB datasource.
- Raw-log mirror timer installed to pull completed logs from `picanm` into `/srv/boat/raw-n2k`.
- Fat Signal K server installed on `pi5nvme:3001`.
- Fat Signal K currently consumes `picanm:3000` as a remote Signal K provider.
- Initial Signal K webapps installed on `pi5nvme`: KIP, Freeboard-SK, Instrumentpanel, App Dock.
- MasterBus USB tooling installed on `pi5nvme`; `masterbus-signalk` is active and feeding Signal K vessel paths.
- Signal K WebSocket collector installed and writing to TimescaleDB.
- Raw N2K log decoder/importer installed and guarded; decoded PGN backfill is disabled by default and must run only in an approved, resource-limited import window.
- N2K inventory tooling added.
- Committed and deployed `picanm` raw edge services: `can0-nmea2000`, `n2k-raw-logger`, and `n2k-raw-forwarder`.
- Committed and deployed `pi5nvme` raw receiver service: `boat-n2k-raw-receiver` on TCP `20200`.
- Verified forwarded raw candump lines are captured under `/srv/boat/raw-n2k/live/`.
- Verified `analyzerjs` decodes a received live-stream sample: 2000 raw lines produced 1238 decoded JSON messages.
- Captured a MasterBus snapshot under `/srv/boat/masterbus/20260703T105249Z` with `/srv/boat/masterbus/latest` updated.
- Determined and deployed the Signal K/canboat raw input method: `providers/simple` → `type: NMEA2000` → `subOptions.type: n2k-ip-gateway-canboatjs` with `format: candump3` connected to `127.0.0.1:20201`.
- Replaced the Pi 5 raw receiver implementation with a Node receiver/fanout: picanm publishes to `pi5nvme.local:20200`; pi5 archives valid candump lines and broadcasts them read-only to local subscribers on `127.0.0.1:20201`.
- Enabled the new `picanm-raw-candump-fanout` Signal K provider while keeping the old `picanm-signalk-ws` provider enabled for overlap.
- Verified Signal K sources include both the old N2K feed (`can0-nmea2000`) and the new raw feed (`picanm-raw-candump-fanout`). Latest low-impact check: `picanm-raw-candump-fanout` had 22 N2K sources / 38 PGNs; `can0-nmea2000` had 16 N2K sources / 27 PGNs.
- Verified Timescale Signal K rows increased during the overlap check.
- Verified MasterBus vessel paths are present in Signal K with `$source: "masterbus"` (15 electrical battery/charger/inverter paths in the latest low-impact check). Note: `/signalk/v1/api/sources` may show an empty `masterbus` metadata object even while vessel paths are live.
- Recovered from the 2026-07-03 `pi5nvme` incident: importer service/timer are inactive/disabled, repo safeguards are deployed, and picanm raw forwarding is reconnected via `pi5nvme.local`.

## Near-term next steps

1. Compare old and new feeds in parallel: path/PGN coverage, timestamps, source metadata, and key values.
2. Keep MasterBus path validation in the overlap check using `/signalk/v1/api/vessels/self`, not only `/signalk/v1/api/sources`.
3. Plan decoded N2K import/backfill separately as an approved, resource-limited maintenance window; do not use importer/backfill as a casual live validation step.
4. Disable Signal K on `picanm` only after the go/no-go checklist passes.
