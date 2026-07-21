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

with a `13.25 V` threshold and debounce. Starboard-only and both-off are physically verified; port-only and both-running remain required.

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

The native batch converter/importer emitted alternator, battery, inverter/charger and solar typed rows from a 257-event live sample with zero skips. Repeated import into disposable PostgreSQL staging was idempotent at 69 alternator, 42 battery, 45 inverter/charger and 30 solar rows. The first approved bounded native batch was imported into live `boatdata` on 2026-07-21: one 2,893,597-byte settled file produced 2,937 alternator, 2,124 battery, 1,482 inverter/charger and 2,376 solar typed rows with zero skips. The pre-change schema backup is `/home/jack/boat-masterbus-schema-backup-20260721T073938Z`; the immediate pre-batch backup is `/home/jack/boat-masterbus-prebatch-20260721T151944Z.sql`. Mapped Signal K JSONL is fallback evidence only and its separate logger is not part of normal deployment.

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

The first native live batch, seven-PGN staging gate and engine-history deployment are complete. Continue in this order:

1. Deploy the repository-controlled Grafana provisioning/dashboard set and validate its bounded electrical and engine-history queries against the first live MasterBus batch.
2. Complete port-only and both-running physical commissioning when safe. Do not present runtime as trusted operational/logbook history until these observations agree with the typed-derived transitions.
3. Evaluate logbook integration only after engine state/runtime is trustworthy.
4. Use the first dashboard to decide whether ongoing MasterBus imports provide enough value to justify a schedule. Approve each additional settled-file batch separately; do not turn the importer into an unattended live writer yet.
5. Define a named navigation-history consumer before approving any live N2K import. Start with only the seven parity-gated Rust PGNs; parity-gate every additional PGN before inclusion.

Before every live schema change or typed import, compare deployed functions, grants, columns and constraints with committed SQL. Take a bounded pre-change snapshot, verify a settled source checksum/size/line count and later active file, run a no-write conversion, then verify immutable source provenance, expected typed counts, zero skips, zero staging rows, idempotence, disk and service health after import.

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

## 2026-07-21 implementation and staging evidence

The repository now contains migration `011_masterbus_engine_history_v1.sql`, which deterministically rebuilds durable engine transitions and runtime intervals from typed native alternator samples only. It uses the deployed 13.25 V strict threshold, 10-second start debounce and 30-second stop debounce, suppresses duplicate samples through the typed primary key, treats gaps over 120 seconds as unknown/data-gap boundaries, leaves sparse open intervals open, and retains raw log/line provenance. It does not read Signal K engine-state output. Indexed consumer views cover engine runtime summaries, recent electrical history and provenance.

A first useful repository-controlled Grafana dashboard/provisioning set is present under `infra/pi5nvme/grafana/`. It has not yet been deployed to the live host; the first typed MasterBus batch is now available for dashboard validation.

### New executable engine-history verification — 2026-07-21

This is newly rerun evidence from the current repository, distinct from the inherited bounded native and N2K staging records below. `npm run test:engine-history:integration` passed against PostgreSQL 17.10 in a disposable database created through the local Unix socket and dropped with `DROP DATABASE ... WITH (FORCE)` in cleanup. TimescaleDB was not present and was not required. The test applied a minimum MasterBus inventory/device/alternator/battery schema plus `011_masterbus_engine_history_v1.sql`, then rebuilt deterministic fixtures covering threshold equality/strictness, both debounce boundaries, chatter, duplicate/sparse same-key samples, nulls, exact and over-limit gaps, source-file boundaries, closed/data-gap/open intervals, provenance, port/starboard isolation, invalid parameters and repeated delete/rebuild. It asserted 7 transition rows, 4 interval rows, 2 summary rows and 230 seconds of completed runtime; the open interval was excluded. The latest run took 255 ms measured inside the test, peaked at 60,468 KiB Node RSS and reported a disposable database size of 8,197,811 bytes. The temporary database was removed successfully.

The migration now records source labels and raw line numbers on transition and runtime interval provenance, locks the typed alternator source during a bounded rebuild, adds time indexes used by recent-electrical consumers, and guards optional-role grants. The migration was deployed to live PostgreSQL on 2026-07-21 after a schema-only backup. Its initial empty-source rebuild produced no rows; after the first approved native batch, rebuild produced one provenance-backed open starboard interval and no port transition.

A focused audit of the older canboatjs typed slices confirmed that PGNs `129540` and `129285` key nested children by source-list position (`satellite_index`/`waypoint_index`) within raw file, message and timestamp. Repeated PRNs or waypoint ids therefore remain distinct and ordered; empty lists now emit no invented child row. AIS `129039`, `129809` and `129810` have synthetic converter/schema/merge coverage but the cited bounded real sample contained zero rows, so they are not representative-real-data validated. Do not use or Rust-port these older slices without an identified consumer and the required representative/parity gate.

### Completed disposable staging gates

- Settled native source: `/srv/boat/masterbus/native-events/masterbus-native-20260721T070000Z.jsonl`, copied only after the writer rotated to `masterbus-native-20260721T080000Z.jsonl`; SHA-256 `846e2088af460a974e6be8e340ea84e29e3dcb75767dde11858a2952361b0347`, 2,893,597 bytes, 11,418 events, `2026-07-21T07:26:31.291Z`–`07:59:59.643Z`.
- Native converter counts: 3,545 alternator, 3,338 battery, 1,938 inverter/charger and 2,597 solar event rows; zero skips. Merged typed counts after same-timestamp sparse coalescing: 2,937, 2,124, 1,482 and 2,376 respectively.
- Native runs: first import, duplicate import and delete/rebuild import. The duplicate reused one inventory row and identical typed counts. Derived rows and inventory were explicitly deleted to zero; staging rows were zero after each merge; normalized typed TSV exports matched exactly after rebuild. Limits were 5,000,000 input bytes, 20,000 lines, 120 seconds, 256 MiB RSS/JS heap planning, 200,000,000 workspace bytes and 1,000,000,000 free disk bytes. Observed elapsed times were 656/646/669 ms, peak RSS 67,736–68,408 KiB, workspace 4,076,872 bytes and free disk about 883 GB.
- Native-derived engine evidence: 2,937 alternator samples (port 1,025; starboard 1,912) produced one open starboard `started` transition at `2026-07-21T07:26:44.298Z`; port produced no start transition. This agrees with the available starboard-only physical evidence, but is not full physical commissioning.

### First bounded live MasterBus batch — executed and verified

- Settled source: `/srv/boat/masterbus/native-events/masterbus-native-20260721T070000Z.jsonl`; SHA-256 `846e2088af460a974e6be8e340ea84e29e3dcb75767dde11858a2952361b0347`; 2,893,597 bytes; 11,418 events; `2026-07-21T07:26:31.291Z`–`07:59:59.643Z`. The active `080000Z` file is excluded.
- Expected typed tables/rows from staging: `masterbus_alternator_samples_v1` 2,937; `masterbus_battery_samples_v1` 2,124; `masterbus_inverter_charger_samples_v1` 1,482; `masterbus_solar_samples_v1` 2,376. Expected skips: 0. One `masterbus_log_files_v1` inventory row.
- Scope: one PostgreSQL transaction containing inventory upsert, COPY to four disposable stages and `masterbus_merge_staged_log_v1`; stage tables must be empty on success. Runtime limit 120 seconds per converter/psql process; input limit 5 MB; line limit 20,000; memory planning limit 256 MiB; workspace limit 200 MB; minimum free disk 1 GB. Verify live filesystem use remains below the 75/85/90% guard thresholds before approval.
- Rollback: before approval, snapshot the empty-schema state; on failure let the transaction roll back; after an approved rollback, delete only rows with the batch inventory id and then its inventory row in a bounded transaction, followed by the same indexed count/provenance checks. Do not delete source logs.
- Post-import verification passed: status `imported`, checksum/size/11,418-line count/timestamps exact, four expected typed counts, zero stage rows, zero skips, native source labels, disk 38%, and no change to live Signal K/MasterBus/raw acquisition health. A stale deployed merge function initially replaced source line count with 8,919 typed source lines; the current committed `008_masterbus_v1_merge.sql` was redeployed and an idempotent retry restored and preserved the correct 11,418 source-event count. Missing staging-table `DELETE` privileges were also corrected live and in `006_masterbus_v1.sql`.

### Remaining gates

- The first native MasterBus batch is imported into live `pi5nvme` PostgreSQL. No N2K batch has been imported live; additional batches remain separately approval-gated.
- The engine migration is deployed and rebuilt from the imported typed alternator evidence. Grafana provisioning remains repository-only pending deployment review.
- Port-only and both-running remain deferred physical observations. Both-off was verified at nighttime with both sense-voltage and field-current inputs at 0 and both derived states `stopped`. Do not describe runtime as trusted operational/logbook history until the remaining observations are recorded.

Read-only live verification on `pi5nvme` confirmed direct `raw_file_id/message_index` schema columns and zero rows in `masterbus_log_files_v1`, `masterbus_alternator_samples_v1`, and N2K raw inventory. The bounded health run at `2026-07-21T08:21:02Z` passed 27/27 checks with picanm, raw receiver, Signal K and MasterBus active; Signal K freshness was 96/104 raw-feed paths and 43/43 MasterBus paths. No live writer or schema mutation was performed.

A subsequent read-only operational check confirmed that the three NVMe/PCIe mitigation arguments from the 2026-07-04 storage incident remain active, the MasterBus USB Link (`1a64:0000`) is present, the current boot has no known NVMe reset/I/O/ext4 error signatures, and the obsolete `n2k_decoded_messages` relation is absent. The bounded health check now reports these hardware/storage conditions explicitly. An executable regression test verifies that `--pi5-host` reaches both the underlying shell health check and its generated Signal K URL.
