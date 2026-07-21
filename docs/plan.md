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

MasterBus replay/native event logs
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

MasterBus mapped JSONL is the current replay source but captures only mapped fields. The end state should use native decoded field events if the existing MasterBus library can expose them.

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
2. Decide typed-only versus envelope-plus-typed storage with a measured sample.
3. Carry `raw_file_id` and message position for provenance.
4. Validate supported PGNs with bounded real samples.
5. Import only PGNs needed by current dashboards and analysis.
6. Prove idempotent restart and failure cleanup.
7. Run historical batches only on staging.

Current typed coverage includes navigation, heading, steering, speed, depth, distance, GNSS quality, route/waypoint, common AIS, wind and environmental PGNs. Add rarer PGNs only when needed.

### 3. Finish the typed MasterBus path

1. Preserve current snapshots and mapped replay logs.
2. Validate replay into typed alternator, battery, inverter/charger and solar tables.
3. Investigate native decoded field-event logging.
4. Derive port/starboard engine transitions from typed alternator evidence.
5. Derive runtime from durable transition intervals.

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

1. Measure typed-only versus envelope-plus-typed N2K storage using a bounded staging sample.
2. Choose and document the final typed-table provenance model.
3. Validate MasterBus replay into typed tables.
4. Implement durable engine transitions/runtime from typed MasterBus history.
5. Build Grafana health and first useful typed-history dashboards.
6. Evaluate logbook integration after engine state/runtime is trustworthy.

## Done means

- source archives are continuous and replayable;
- Signal K provides current N2K and MasterBus state;
- PostgreSQL provides selected typed N2K and MasterBus history;
- historical facts are stored once;
- Grafana and history applications read PostgreSQL;
- only the live Signal K and typed PostgreSQL processing paths remain;
- PostgreSQL can be rebuilt from preserved source logs;
- disk/resource guards protect live acquisition.
