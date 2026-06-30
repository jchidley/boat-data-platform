# Boat data platform plan

## Architecture

```text
NMEA 2000 backbone
    ↓
PiCAN-M HAT on picanm
    ↓
picanm bare-bones gateway
    ├─ can0 at 250 kbit/s
    ├─ minimal Signal K server
    └─ compact raw candump logs
          ↓ live API / rsync
pi5nvme data platform
    ├─ raw log mirror
    ├─ second/fat Signal K instance if useful
    ├─ custom collectors and analysis code
    ├─ PostgreSQL + TimescaleDB
    └─ Grafana dashboards
          ↓
iPad / iPhone / Android / Windows Surface / WSL clients
```

## Design principles

1. `picanm` must stay simple and robust.
2. `picanm` should keep collecting even when `pi5nvme` is off.
3. Raw NMEA 2000 logs are the source of truth for replay and reprocessing.
4. Heavier plugins, dashboards, databases, and experiments belong on `pi5nvme`.
5. Start read-only. Treat NMEA 2000 transmission as a separate safety-critical project.
6. Prefer reproducible scripts and committed configuration over one-off manual changes.

## picanm responsibilities

- Maintain `can0` at 250 kbit/s.
- Run minimal Signal K for live decoded output.
- Write compact raw candump logs to `/var/log/n2k`.
- Expose Signal K API/WebSocket on port 3000.
- Avoid heavy analysis, databases, GUI tools, or plugin experiments.

## pi5nvme responsibilities

### Phase 1 — mirror and inspect

- Create local archive directory, e.g. `/srv/boat/raw-n2k`.
- Periodically pull completed raw log files from `picanm`:

```bash
rsync -av --ignore-existing picanm:/var/log/n2k/ /srv/boat/raw-n2k/
```

- Write a small inventory tool to summarize:
  - source addresses
  - PGNs seen
  - first/last seen
  - message rates
  - address claims / NAME fields
  - unknown/proprietary PGNs

### Phase 2 — live collector

- Connect to:

```text
ws://picanm:3000/signalk/v1/stream
```

- Store Signal K deltas into PostgreSQL/TimescaleDB.
- Keep the collector idempotent and tolerant of `picanm` or `pi5nvme` restarts.

### Phase 3 — TimescaleDB schema

Use PostgreSQL with the TimescaleDB extension.

Initial generic table:

```sql
CREATE TABLE signal_k_measurements (
  time timestamptz NOT NULL,
  path text NOT NULL,
  source text,
  pgn integer,
  value_double double precision,
  value_text text,
  value_json jsonb
);

SELECT create_hypertable('signal_k_measurements', 'time');

CREATE INDEX ON signal_k_measurements (path, time DESC);
CREATE INDEX ON signal_k_measurements (source, time DESC);
CREATE INDEX ON signal_k_measurements (pgn, time DESC);
```

Rationale: Signal K paths evolve over time. A generic path/value table lets us start quickly without over-modelling the boat.

Later, add derived/materialized tables for common domains:

- navigation track
- wind
- depth
- GNSS quality
- heading and attitude
- electrical systems
- engine systems
- alarms/events

### Phase 4 — Grafana

Install Grafana on `pi5nvme` and connect it to PostgreSQL/TimescaleDB.

Initial dashboards:

- Current boat state
- GPS track and GNSS quality
- Wind speed/angle history
- Depth and water temperature
- Heading vs COG
- SOG vs STW
- Rudder angle
- CAN bus/source activity
- Data freshness / stale sensors

### Phase 5 — second Signal K on pi5nvme

Optionally run a second, heavier Signal K instance on `pi5nvme`.

Potential uses:

- plugin experiments
- dashboards that are too heavy for `picanm`
- data exports
- integrations with OpenCPN or other clients

Important: avoid feedback loops. Do not bridge data back to `picanm`/NMEA 2000 unless deliberately designed.

### Phase 6 — OpenCPN and client apps

Potential clients:

- Windows Surface running OpenCPN
- iPad/iPhone/Android browser dashboards
- OpenCPN mobile where useful
- Signal K web apps such as KIP / Freeboard-SK

Feed clients from `pi5nvme` where possible; use `picanm` directly only for minimal live access.

## Open questions

- Which NMEA 2000 devices correspond to the observed source addresses?
- Which boat systems are not on the currently connected N2K segment?
- Should raw logs be mirrored only, or also decoded batch-wise into TimescaleDB?
- Which Signal K plugins are worth running on `pi5nvme`?
- What is the desired long-term storage retention and compression policy on `pi5nvme`?
- Should `picanm` publish raw logs over HTTP, or is rsync over SSH enough?
- Do we need alerts/notifications, and if so where should they run?

## Completed pi5nvme base work

- PostgreSQL 15 installed on `pi5nvme`.
- TimescaleDB installed and enabled in the `boatdata` database.
- Initial `signal_k_measurements` hypertable created.
- Grafana installed and provisioned with a `Boat TimescaleDB` datasource.
- Raw-log mirror timer installed to pull completed logs from `picanm` into `/srv/boat/raw-n2k`.
- Fat Signal K server installed on `pi5nvme:3001`.
- Fat Signal K consumes `picanm:3000` as a remote Signal K provider.
- Initial Signal K webapps installed on `pi5nvme`: KIP, Freeboard-SK, Instrumentpanel, App Dock.

## Near-term next steps

1. Write a small Signal K WebSocket collector.
2. Store decoded Signal K values in TimescaleDB.
3. Build the first Grafana dashboard.
4. Build a device/PGN inventory report from raw logs.
5. Add batch import/replay tooling for mirrored raw candump logs.
