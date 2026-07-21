# PostgreSQL storage plan

## Purpose

Define the current storage model for compact, rebuildable historical data without duplicating authoritative source material.

## Ownership

| Fact | Historical owner |
|---|---|
| Complete NMEA 2000 frames | Compressed edge-timestamped candump files |
| Selected decoded N2K values | PGN-shaped typed PostgreSQL tables |
| Complete replayable MasterBus decoded events | Append-only native field-event logs captured before Signal K mapping |
| Selected MasterBus values | Typed MasterBus PostgreSQL tables sourced directly from native field-event logs |
| Engine transitions and runtime | Typed PostgreSQL events derived from typed MasterBus history |
| Health and import evidence | Bounded metadata tables |

A historical fact has one owner. Signal K provides current state and does not provide the end-state historical feed to PostgreSQL.

## Data flow

```text
NMEA 2000 bus
  -> picanm raw acquisition
  -> compressed candump source archive
       |-> live fanout -> Signal K current state
       `-> offline/staging decoder -> selected typed PostgreSQL history

MasterBus USB
  |-> live mapper -> Signal K current state
  `-> replay/native event log -> selected typed PostgreSQL history

PostgreSQL
  -> Grafana
  -> logbook/history consumers
  -> reports and custom APIs
```

Normal operation does not replay PostgreSQL history into Signal K.

## Historical decoder policy

Signal K continues using its deployed canboatjs decoder for live state. The offline PostgreSQL path has a direct Rust implementation under `tools/n2k-rust-importer/`. It embeds a revision-pinned `canboat-core`, parses edge candump records, reassembles messages, decodes in SI units and emits COPY TSV directly. It does not emit or retain analyzer JSON.

Rust provenance is the one-based source candump line where the message begins; decoder output sequence numbers are never provenance. Current coverage is intentionally limited to seven typed PGNs and is selected with `--decoder rust` in the bounded wrapper. canboatjs remains the default comparison path until acceptance is complete.

Acceptance requires equivalent supported typed row counts, values within field resolution, explicit first-frame fast-packet timestamps, bounded malformed/incomplete-packet behavior, explained Rust-only decodes and a successful staging delete/rebuild. This gate is complete for the initial seven-PGN set; conversion evidence is recorded in [`2026-07-05-copy-merge-validation.md`](2026-07-05-copy-merge-validation.md). Record the pinned revision and embedded CANboat schema version in every later conversion evidence set.

## N2K storage

Raw candump files are complete and replayable. PostgreSQL stores only selected values that are useful for queries, dashboards, analysis or durable events.

Current typed flow:

```text
raw candump
  -> analyzer output used as a temporary conversion format
  -> PGN-shaped TSV
  -> unlogged PostgreSQL staging tables
  -> set-based merge
  -> typed PGN tables and summaries
```

Normal conversion uses:

- research mode `none` by default;
- `untyped` mode only for bounded investigation of PGNs without a typed converter;
- `selected` mode only for an explicit PGN list;
- explicit permission for full-file conversion;
- input-size and process-runtime limits.

The final model is typed-only provenance: each typed row carries `raw_file_id` and `message_index` directly. Complete frame envelopes remain in authoritative candump files and are not retained broadly in PostgreSQL.

A bounded 2026-07-21 staging measurement used 200,000 real CAN frames, producing 118,149 decoded envelopes and 109,768 typed rows. On plain PostgreSQL 17 with representative indexes, envelope-plus-typed used 55 MB and typed-only used 20 MB. Typed-only reduced measured storage by 63.1%. TimescaleDB chunk overhead and compression may change absolute sizes, but do not justify duplicating every decoded message already preserved in raw files.

The importer writes direct typed provenance. `n2k_frames_stage_v2` is disposable and exists only long enough to build file/source/PGN summaries; no persistent frame-envelope table exists.

## Signal K history collector removal

The general Signal K history collector is not part of the two-path design. [`postgresql-end-state-migration.md`](postgresql-end-state-migration.md) removed its repository and live-host service, derived table and other duplicate objects on 2026-07-21.

Typed MasterBus and engine-event history must come from the source replay path, not Signal K.

## MasterBus history

The historical source must be native decoded Mastervolt/MasterBus field events captured from the existing decoder before Signal K mapping. Mapped Signal K JSONL preserves only configured paths and is an interim comparison/fallback source, not the end-state PostgreSQL feed.

The native event log must be append-only, rotated and replayable. Each event must preserve enough information to reconstruct selected typed facts:

- source timestamp;
- stable device identity;
- native field/register identity;
- decoded value and unit;
- decoder and schema version;
- source file and replay position.

Preserve together:

- native field-event logs;
- discovery snapshots;
- configuration/schema caches;
- decoder/schema versions;
- retained mapped JSONL evidence and fallback tooling during migration;
- import checksums and status.

PostgreSQL consumes selected native events through typed staging and idempotent merge. It must not be the only sink because database downtime must not lose source evidence. Signal K continues as the independent live-state consumer and is not mirrored into PostgreSQL.

Do not add new hardware or undertake broad protocol reverse engineering unless the existing library cannot expose the required decoded events. Remain receive-only and do not add MasterBus writes or control.

## Disk and resource safety

The derived-storage guard checks the PostgreSQL filesystem every five minutes:

```text
75% used: warning
85% used: stop rebuildable PostgreSQL writers
90% used: critical/operator action
```

Raw acquisition on `picanm` is independent and must not be stopped by this guard.

Historical conversion remains offline/staging work. Any approved import must set limits for:

- source bytes and file count;
- process runtime;
- CPU and memory;
- temporary workspace;
- minimum free disk;
- transaction scope.

### Deployed-schema and import parity gate

Do not discover repository/live drift during COPY. Before every live schema change or typed batch:

- compare deployed function definitions, grants, columns and constraints with committed SQL;
- verify required staging `SELECT`/`INSERT`/`UPDATE`/`DELETE` and merge-function privileges using the actual ingest role;
- snapshot the bounded pre-change schema/data scope;
- prove the source is settled and record checksum, bytes, physical source-event lines and event-time range;
- run a no-write conversion under the approved limits;
- require expected converter counts and zero unexpected skips before COPY.

After import, require exact immutable inventory provenance, expected merged typed counts, correct source labels, zero residual staging rows, idempotent retry where specified, successful dependent-history rebuild and unchanged disk/acquisition health. Source-event line count is source provenance and must never be replaced by a typed, distinct or coalesced row count.

## Acceptance criteria

The storage design is complete when:

- raw N2K archives remain continuous, checksummed and replayable;
- selected typed N2K rows trace back to raw file and message position;
- normal conversion emits no research rows;
- typed rows carry direct raw-file/message provenance and complete frame envelopes are not retained;
- each retained historical fact has one documented owner;
- only the live Signal K and typed PostgreSQL processing paths remain;
- durable engine events and runtime are derived from typed MasterBus history;
- MasterBus history can be rebuilt from preserved native decoded field-event logs without depending on Signal K mappings;
- disk pressure stops rebuildable writers before source acquisition is endangered;
- PostgreSQL can be rebuilt from preserved source material and committed schema/tools.

## 2026-07-21 bounded batch evidence and engine layer

The settled native-file gate used the rotated `masterbus-native-20260721T070000Z.jsonl` file, never the active `080000Z` file. Its source checksum, line count, timestamps, converter counts, merged typed counts and resource limits are recorded in the implementation brief and validation document. Duplicate import remained idempotent, staging was empty after merge, explicit delete removed typed rows and inventory, and the rebuilt normalized typed exports matched byte-for-byte.

`011_masterbus_engine_history_v1.sql` adds the historical owner for engine transitions and runtime. It consumes `masterbus_alternator_samples_v1`, not Signal K. A running interval is closed only by typed stop evidence or a bounded data gap; missing data is not interpreted as an engine stop, and an unresolved interval remains open and is excluded from completed-runtime totals. Source labels and raw file/line provenance are retained for both observed transitions and interval endpoints. The rebuild takes a source SHARE lock before replacing derived rows; callers should use a bounded transaction because TRUNCATE takes ACCESS EXCLUSIVE locks on the derived tables. Optional-role grants are conditional, so disposable schemas need not pre-create Grafana/ingest roles. Recent-electrical source tables have time indexes to support the view's stable `now() - interval '24 hours'` predicate; dashboard queries add explicit time macros and row limits.

The committed executable disposable PostgreSQL regression test covers these semantics without requiring TimescaleDB. The migration was deployed live on 2026-07-21 and rebuilt from the first approved typed native batch, producing one provenance-backed open starboard interval. Grafana provisioning/dashboard are deployed with bounded queries and a stable datasource UID; Grafana 13 requires `jsonData.database: boatdata` as well as the top-level database field. The completed-runtime panel must remain empty while all intervals are open. Additional typed batches remain approval/prerequisite-gated.
