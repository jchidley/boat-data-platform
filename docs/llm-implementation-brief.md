# LLM implementation brief

Use this file for deployed state and the next task. Use [`plan.md`](plan.md) for the end state and [`postgresql-storage-plan.md`](postgresql-storage-plan.md) for historical-storage rules.

## End-state rule

There are two processing paths:

```text
preserved source -> Signal K -> current state and live apps
preserved source -> typed PostgreSQL -> Grafana, history apps and analysis
```

Do not create a third general Signal K-to-PostgreSQL telemetry path. The collector and obsolete tables have been removed from both the repository schema and the live host. [`postgresql-end-state-migration.md`](postgresql-end-state-migration.md) was applied successfully on 2026-07-21; no import or backfill was run.

## Deployed live path

### `picanm`

- `can0` at 250 kbit/s;
- edge-timestamped compressed candump logging under `/var/log/n2k/`;
- local spool during backend outages;
- live forwarding to `pi5nvme.local:20200`;
- no Signal K, Node.js, database, apps or analysis.

### `pi5nvme`

- raw receiver/archive under `/srv/boat/raw-n2k/live/`;
- localhost fanout on `127.0.0.1:20201`;
- Signal K on port `3001`, decoding the raw fanout with canboat;
- MasterBus USB integration on port `3009` feeding Signal K;
- PostgreSQL/TimescaleDB and Grafana;
- KIP, Freeboard-SK and InstrumentPanel;
- repo-controlled `signalk-two-engine-state` plugin.

The engine-state plugin currently uses:

```text
electrical.alternators.alpha-port.senseVoltage
electrical.alternators.alpha-stbd.senseVoltage
```

and emits:

```text
propulsion.port.state
propulsion.starboard.state
```

with a `13.25 V` threshold and debounce. Physical verification of all engine combinations remains required.

## New typed historical path

Repo support exists for:

```text
raw candump
  -> pinned direct Rust/canboat-core decoder (canboatjs fallback)
  -> PGN-shaped TSV
  -> PostgreSQL COPY staging
  -> typed PGN tables and summaries
```

Supported typed PGNs include navigation, heading, rudder, rate of turn, attitude, magnetic variation, switch bank, speed, depth, distance log, route/waypoints, GNSS quality, common AIS, wind and environmental data.

The typed tables now carry `raw_file_id` and `message_index` directly. File/source/PGN summaries are built from disposable envelope staging; no persistent frame-envelope table remains. This schema was validated twice on a 200,000-frame real sample and deployed empty to `pi5nvme` on 2026-07-21 without an import or backfill.

Current safeguards:

- research output defaults to `none`;
- selected research requires explicit PGNs;
- complete-file conversion requires explicit permission;
- input size and process runtime are bounded by default;
- broad historical work runs offline/staging, not on live `pi5nvme`.

Native decoded Mastervolt/MasterBus event capture was deployed on 2026-07-21 inside the single `masterbus-signalk` USB owner. It logs selected mapped-native fields before Signal K path conversion under `/srv/boat/masterbus/native-events/`, suppressing unchanged values except for a 60-second heartbeat. A startup-discovery fault that hid alternator paths was recovered; the bridge now exits for systemd restart when a device absent at startup later appears.

The native batch converter/importer emitted alternator, battery, inverter/charger and solar typed rows from a 257-event live sample with zero skips. Repeated import into disposable PostgreSQL staging was idempotent at 69 alternator, 42 battery, 45 inverter/charger and 30 solar rows. The empty MasterBus typed schema and merge function were deployed to live `boatdata` on 2026-07-21; all typed tables and file inventory remain empty, and no native batch was imported. The pre-change schema backup is `/home/jack/boat-masterbus-schema-backup-20260721T073938Z`. Mapped Signal K JSONL is fallback evidence only and its separate logger is not part of normal deployment.

## Source material

Preserve:

```text
picanm:/var/log/n2k/
pi5nvme:/srv/boat/raw-n2k/
pi5nvme:/srv/boat/masterbus/
repo code, SQL, services and documentation
```

Raw candump is authoritative for N2K. MasterBus snapshots and replay logs must be preserved independently because MasterBus is not in the N2K archive.

## Safety

- Receive-only on NMEA 2000 and MasterBus.
- No autopilot, switching or charging control.
- No broad conversion/backfill on live `pi5nvme`.
- No broad database aggregates on the live host.
- Use short timeouts and bounded queries.
- Keep raw acquisition independent from derived writers.
- Use `pi5nvme-ip` / `picanm-ip` or `.local` mDNS; bare Starlink hostnames can resolve badly from WSL.

## Immediate task

Complete the new typed historical path in this order:

1. Complete native MasterBus operational validation. Device-discovery restart recovery and live file growth are verified. Still observe an hourly file boundary, daily logrotate compression/retention and a settled-file delete/rebuild; then approve a bounded native typed batch for live PostgreSQL. The schema is deployed empty and no batch has been loaded.
2. Select and run the first explicitly bounded seven-PGN staging import. The direct Rust decoder gate is complete for PGNs `127245`, `127250`, `128259`, `128267`, `129025`, `129026` and `130306`; parity-gate any additional PGN before inclusion.
3. Implement typed engine transition/runtime history from native MasterBus alternator evidence and verify all four physical engine combinations.
4. Point health/Grafana queries at typed tables and build the first historical dashboards.
5. Evaluate logbook integration after engine state/runtime is trustworthy.

## Do not do

- Do not add another database.
- Do not store every bus field merely because it can be decoded.
- Do not retain complete frame envelopes without measured value.
- Do not write proprietary decoders without a concrete missing-data use case.
- Do not add new Signal K apps until the typed historical path and engine semantics are stable.
- Do not change the working live Signal K path while building PostgreSQL history.

## Local references

- Signal K/canboat source map: [`signalk-llm-source-map.md`](signalk-llm-source-map.md)
- Storage implementation: [`postgresql-storage-plan.md`](postgresql-storage-plan.md)
- Deployed-object cleanup: [`postgresql-end-state-migration.md`](postgresql-end-state-migration.md)
- Historical import limits: [`2026-07-04-backfill-strategy.md`](2026-07-04-backfill-strategy.md)
- Device inventory: [`2026-07-03-boat-discovery-and-decoder-inventory.md`](2026-07-03-boat-discovery-and-decoder-inventory.md)
- Engine-state design: [`two-engine-state-plugin-plan.md`](two-engine-state-plugin-plan.md)
- Resource safety: [`2026-07-03-pi5nvme-incident-and-picanm-status.md`](2026-07-03-pi5nvme-incident-and-picanm-status.md)
