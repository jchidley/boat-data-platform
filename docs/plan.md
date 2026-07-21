# Boat data platform plan

## End state

The platform has two processing paths fed from preserved source data:

```text
                         +-> Signal K -> live apps and current boat state
NMEA 2000 -> raw archive|
                         `-> typed PostgreSQL -> Grafana, history apps and analysis

                         +-> Signal K -> live apps and current electrical state
MasterBus -> replay log |
                         `-> typed PostgreSQL -> Grafana, history apps and analysis
```

### Path 1: live Signal K

This path already exists.

```text
picanm can0
  -> edge-timestamped candump logging
  -> live raw forwarding to pi5nvme
  -> localhost raw fanout
  -> Signal K/canboat

MasterBus USB
  -> masterbus-signalk
  -> Signal K
```

Signal K owns:

- current normalized boat state;
- live REST/WebSocket APIs;
- KIP, Freeboard and other live applications;
- current derived state such as `propulsion.port.state` and `propulsion.starboard.state`.

Signal K is not a historical database.

### Path 2: typed PostgreSQL history

This is the path being completed.

```text
compressed raw candump files
  -> offline/staging canboat conversion
  -> PGN-shaped typed rows
  -> PostgreSQL COPY
  -> typed N2K tables

MasterBus USB/native decoder
  -> append-only native decoded field-event log
  -> typed conversion
  -> PostgreSQL COPY
  -> typed electrical tables
```

PostgreSQL owns:

- selected typed N2K history;
- selected typed MasterBus history;
- durable engine transitions and runtime derived from typed electrical history;
- health, provenance and import status;
- views and aggregates for Grafana, logbook/history applications and custom analysis.

Each historical fact has one owner. PostgreSQL does not receive a general mirror of Signal K.

## Source material

Preserve continuously:

```text
picanm:/var/log/n2k/          N2K edge spool
pi5nvme:/srv/boat/raw-n2k/    mirrored N2K archive
pi5nvme:/srv/boat/masterbus/  MasterBus replay logs, snapshots and schema/config
repo                           code, SQL, service definitions and documentation
```

Raw N2K candump files are authoritative and replayable. PostgreSQL is selected, queryable derived history.

MasterBus mapped Signal K JSONL is only an interim fallback and captures only mapped fields. The required end state captures native decoded field events directly from the existing Mastervolt/MasterBus source before Signal K mapping, preserves them in an append-only replay log, and loads selected values into typed PostgreSQL. Signal K continues to receive the same live data independently; it is not the historical source. Do not make PostgreSQL the only sink: the native replay log is required for outage tolerance and rebuildability.

## Host responsibilities

### `picanm`

- maintain `can0` at 250 kbit/s;
- timestamp and compress raw candump logs;
- retain a local spool during backend outages;
- forward the live stream to `pi5nvme.local:20200`;
- run no Signal K, database, apps or analysis.

### `pi5nvme`

- archive and fan out live raw N2K;
- run Signal K and MasterBus live integration;
- run PostgreSQL/TimescaleDB and Grafana;
- receive selected, validated typed history from staging;
- run bounded health and disk-pressure monitoring.

### Offline/staging host

- decode historical raw files;
- generate typed COPY inputs;
- validate counts, units, provenance and duplicates;
- measure storage before approving larger batches.

## Safety boundaries

- Receive-only on NMEA 2000 and MasterBus.
- No autopilot, switching or charging control.
- No broad historical conversion on live `pi5nvme`.
- No complete bus duplication in PostgreSQL without measured justification.
- Stop rebuildable writers before disk pressure threatens source acquisition.
- Add a PGN or metric to PostgreSQL only when it supports an identified query, dashboard, event or analysis need.

## Route to the end state

### 1. Preserve and monitor source acquisition

Done operationally; continue validating:

- picanm raw spool growth;
- live forwarding and pi5 archive growth;
- clock offset;
- CAN errors/drops;
- disk pressure.

### 2. Finish the typed N2K path

1. Keep research output disabled by default.
2. Use the measured typed-only model; do not retain complete decoded envelopes in PostgreSQL.
3. Carry `raw_file_id` and message position directly on typed rows for provenance.
4. Validate supported PGNs with bounded real samples.
5. Import only PGNs needed by current dashboards and analysis.
6. Prove idempotent restart and failure cleanup.
7. Run historical batches only on staging.

Current typed coverage includes navigation, heading, steering, speed, depth, distance, GNSS quality, route/waypoint, common AIS, wind and environmental PGNs. Add rarer PGNs only when needed.

#### Historical decoder migration

Keep the existing Signal K/canboatjs live path unchanged. The offline PostgreSQL path now has an incremental direct Rust converter under `tools/n2k-rust-importer/`. It embeds a pinned `canboat-core`, reads edge candump text itself, decodes in SI units and emits typed COPY TSV without analyzer JSON. Provenance is the one-based source candump line where the message begins, including fast packets.

Initial direct typed coverage is PGNs `127245`, `127250`, `128259`, `128267`, `129025`, `129026` and `130306`. On a bounded 10,000-line real sample, Rust and canboatjs produced identical row counts for all seven typed PGNs; Rust decoded 6,001 total messages versus 5,891 from canboatjs. The Rust wrapper imported twice idempotently into disposable PostgreSQL staging, retained 6,001 summary messages and emptied staging.

The migration gate is complete for the initial seven-PGN set. Three additional bounded real files matched per-PGN row counts and values within `2.85e-14`; malformed and incomplete packets and first-frame fast-packet timestamps have explicit tests. Rust-only decoded messages were generic PGN 65280 manufacturer-proprietary range records, which produce no selected typed rows. A disposable staging import was repeated idempotently, deleted with its dependent provenance, and rebuilt to identical counts.

Pin the `canboat-rs` revision and embedded schema version in `Cargo.lock`; retain canboatjs as the comparison oracle and fallback through the first validated limited import. Port an additional typed PGN only when a first historical consumer needs it, and apply the same bounded parity gate before inclusion.

### 3. Build the direct native MasterBus history path

1. Native capture is deployed inside `masterbus-signalk`, before Signal K mapping, so one process owns the USB interface. `masterbus-native-event-v1` records timestamp, native device/field identity, class/instance/group/name/unit and decoded value.
2. Selected useful native fields are appended under `/srv/boat/masterbus/native-events/`; unchanged values are suppressed with a 60-second heartbeat. Signal K emission remains independent. If a device absent at startup later appears, the bridge exits so systemd restarts full discovery and subscriptions.
3. The bounded native converter/importer supports typed alternator, battery, inverter/charger and solar tables with file/line provenance. A real 257-event sample covered all four domains with zero skips and repeated disposable staging import was idempotent.
4. Discovery-triggered systemd restart recovery and live native-log growth are verified. Hourly segmentation is implemented in the writer, and daily compression with 90-day retention is configuration-validated; monitor both operationally without blocking implementation. Prove settled-file delete/rebuild before approving a limited live PostgreSQL batch. The empty typed schema is deployed; no native batch has been loaded.
5. Keep mapped Signal K JSONL only as retained comparison/fallback evidence; its separate logger is removed from normal deployment.
6. Derive port/starboard engine transitions from typed native alternator evidence and runtime from durable transition intervals.

This path is receive-only. Do not write to MasterBus devices or add protocol control behavior.

### 4. Remove the Signal K history collector from the live host

Completed on 2026-07-21: the deployed service and obsolete derived objects were removed, health checks were updated, and live Signal K operation was verified unaffected.

The end state has no general Signal K-to-PostgreSQL telemetry path.

### 5. Build historical consumers

Build Grafana and other historical consumers from PostgreSQL views:

- acquisition and data freshness;
- GPS track and GNSS quality;
- heading, COG, SOG and STW;
- wind, depth and environmental history;
- AIS observations;
- alternator, battery, solar, inverter and charger history;
- engine starts, stops and runtime;
- logbook events.

Live-only apps continue to use Signal K.

## Immediate work order

1. Prove settled-native-file import/delete/rebuild, then approve the first bounded native batch into the deployed empty PostgreSQL schema.
2. Select and run the first explicitly bounded seven-PGN Rust staging import.
3. Implement durable engine transitions/runtime from typed native MasterBus alternator history.
4. Build Grafana health and first useful typed-history dashboards.
5. Evaluate logbook integration after engine state/runtime is trustworthy.

## Deferred physical commissioning

These observations depend on operating the engines and are not blockers for code handoff: both-off, port-only and both-running. Starboard-only is verified. Record the remaining combinations using [`two-engine-state-plugin-plan.md`](two-engine-state-plugin-plan.md) before declaring engine transitions/runtime trustworthy for operational logbook use.

## Done means

- source archives are continuous and replayable;
- Signal K provides current N2K and MasterBus state;
- PostgreSQL provides selected typed N2K and MasterBus history;
- historical facts are stored once;
- Grafana and history applications read PostgreSQL;
- only the live Signal K and typed PostgreSQL processing paths remain;
- PostgreSQL can be rebuilt from preserved source logs;
- disk/resource guards protect live acquisition.
