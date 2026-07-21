# PostgreSQL storage plan

## Purpose

Define the current storage model for compact, rebuildable historical data without duplicating authoritative source material.

## Ownership

| Fact | Historical owner |
|---|---|
| Complete NMEA 2000 frames | Compressed edge-timestamped candump files |
| Selected decoded N2K values | PGN-shaped typed PostgreSQL tables |
| Selected MasterBus values | Typed MasterBus PostgreSQL tables sourced from the best replayable MasterBus log available |
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

Signal K continues using its deployed canboatjs decoder for live state. The offline PostgreSQL path may migrate to a pinned `canboat-rs` release after bounded dual-decoder validation. Rust must consume an adapter that preserves the original candump source-line position; decoder output sequence numbers are not raw provenance.

Acceptance requires equivalent supported typed row counts, understood numeric differences, SI units, explicit fast-packet timestamp semantics, bounded malformed/incomplete-packet behavior, and a successful staging delete/rebuild. Record the binary checksum and embedded CANboat schema version. Initially retain analyzer-compatible JSON between Rust and the existing typed converter; direct `canboat-core`-to-COPY integration is optional future optimisation.

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

Mapped Signal K JSONL preserves only fields mapped at capture time. Keep it as an interim replay source while investigating native decoded MasterBus field-event logging.

Preserve together:

- discovery snapshots;
- configuration/schema caches;
- mapping versions;
- rotated replay logs;
- import checksums and status.

Do not add new hardware or undertake broad protocol reverse engineering unless the existing library cannot provide the required field events.

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

## Acceptance criteria

The storage design is complete when:

- raw N2K archives remain continuous, checksummed and replayable;
- selected typed N2K rows trace back to raw file and message position;
- normal conversion emits no research rows;
- typed rows carry direct raw-file/message provenance and complete frame envelopes are not retained;
- each retained historical fact has one documented owner;
- only the live Signal K and typed PostgreSQL processing paths remain;
- durable engine events and runtime are derived from typed MasterBus history;
- MasterBus history can be replayed from preserved source logs, subject to documented mapping limits;
- disk pressure stops rebuildable writers before source acquisition is endangered;
- PostgreSQL can be rebuilt from preserved source material and committed schema/tools.
