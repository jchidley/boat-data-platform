# Typed COPY/merge validation

## Purpose

Record the evidence that the typed N2K and MasterBus conversion paths work on bounded samples. This is validation evidence, not an operational backfill approval.

## Newly rerun executable engine-history validation — 2026-07-21

This section is newly rerun evidence from the repository state after commit `2833005`; the bounded native and N2K records elsewhere in this document are inherited evidence unless explicitly marked otherwise.

Exact command:

```bash
npm run test:engine-history:integration
```

The test created a uniquely named PostgreSQL database on the local Unix socket, applied a minimum disposable MasterBus schema (log inventory, device inventory, alternator samples and battery samples), then applied `infra/pi5nvme/sql/011_masterbus_engine_history_v1.sql`. It dropped the database with `DROP DATABASE ... WITH (FORCE)` from a `finally` cleanup path. PostgreSQL was 17.10; TimescaleDB was absent and not required. No live or remote database target is permitted by the test's connection guard.

Fixtures and assertions covered: strict `13.25 V` equality versus above-threshold evidence; 10-second start and 30-second stop debounce including exact boundaries; short threshold chatter; duplicate source events and sparse same-timestamp coalescing under the typed key; deterministic timestamp/raw-file/line ordering; null sense-voltage samples; exact 120-second and greater-than-120-second gaps while stopped and running; source-file boundaries; one normally stopped interval, one `data_gap` interval and one open interval; exclusion of open runtime from completed totals; port/starboard isolation; transition and interval source/file/line provenance; invalid parameters; repeated rebuild; and delete-derived-rows/rebuild recovery. The source inventory foreign key was also checked to reject deletion while provenance was referenced.

The test asserted exactly **7 transitions**, **4 runtime intervals**, **2 summary rows** and **230 completed runtime seconds**. The latest disposable run measured **336 ms**, peak Node RSS **60,144 KiB**, database size **8,197,811 bytes**, and reported TimescaleDB `false`. Cleanup removed the temporary database successfully. The final test-suite commit hash will be recorded here after the verification commit is created; no live migration, import or Grafana deployment was performed.

## N2K path validated

```text
candump sample
  -> canboat analyzer output
  -> PGN-shaped TSV
  -> unlogged staging tables
  -> n2k_merge_staged_file_v2(raw_file_id)
  -> typed tables, summaries and import status
```

Validated behavior:

- raw-file inventory creation/update;
- edge timestamp preservation;
- `COPY` into staging;
- set-based merge;
- duplicate handling by raw file/message position;
- file PGN/source summaries;
- imported/failed status updates;
- wrapper-generated bounded evidence;
- research output disabled by default.

Validated typed PGNs:

```text
127237 heading/track control
127245 rudder
127250 heading
127251 rate of turn
127257 attitude
127258 magnetic variation
127501 switch bank status
128259 speed through water
128267 water depth
128275 distance log
129025 position rapid update
129026 COG/SOG rapid update
129029 GNSS position
129038 AIS Class A position
129039 AIS Class B position
129284 navigation data
129285 route/waypoint data
129539 GNSS DOPs
129540 GNSS satellites
129794 AIS Class A static/voyage
129809 AIS Class B static part A
129810 AIS Class B static part B
130306 wind
130310 environmental parameters
130311 environmental parameters
130312 temperature
130314 pressure
130316 temperature extended
```

Tests included synthetic rows for all supported shapes and small real analyzer samples for representative navigation, steering, GNSS, AIS and environmental messages. Non-null depth and nested list rows for satellites/routes were explicitly checked.

## Direct Rust decoder validation

`tools/n2k-rust-importer/` embeds `canboat-core` revision `d0f7f24a41b1274f63b71f08703539554523858f` with CANboat schema `7.1.0`. It reads candump directly, uses one-based source-line provenance, decodes in SI units and emits typed TSV without analyzer JSON.

A 10,000-line real sample produced:

```text
Rust decoded messages:       6001
canboatjs decoded messages:  5891
Rust selected typed rows:    3002
research rows:                  0
malformed rows:                 0
```

Rust and canboatjs produced identical row counts for each implemented typed PGN: `127245`, `127250`, `128259`, `128267`, `129025`, `129026` and `130306`. Across the sample, corresponding numeric differences were below `3e-14`. Rust deliberately preserves the raw edge timestamp to microseconds and records the one-based source line, rather than canboatjs's decoded-record index and millisecond timestamp formatting.

The bounded wrapper imported the Rust output twice into disposable PostgreSQL without duplicates; frame staging emptied and summary count remained 6,001.

The remaining decoder gate was completed on 2026-07-21:

- malformed candump timestamps, CAN ids, payload lengths, payload bytes and separators are rejected without panic;
- an incomplete fast packet emits no message;
- a complete real PGN 129029 fast packet uses the first frame's source line and microsecond edge timestamp;
- three additional 10,000-line real samples from 03:00, 04:00 and 05:00 UTC produced identical per-PGN row counts for all seven direct typed shapes;
- 43,253 corresponding typed fields were compared, with a maximum numeric difference of `2.842170943040401e-14` and no text differences;
- Rust decoded 112, 109 and 111 more messages respectively. In each sample the entire difference was PGN 65280: the Rust schema emits the generic manufacturer-proprietary single-frame range record while canboatjs suppresses it. It produces no selected typed row and is harmless summary evidence, not a historical fact.

A disposable staging clone then imported the 05:00 sample twice, retaining 6,007 summarized messages and 3,013 selected typed rows without duplication. `TRUNCATE n2k_raw_files_v2 CASCADE` cleared the clone's import runs, summaries and typed provenance rows; reimport reproduced exactly 6,007 summarized messages and 3,013 typed rows, with frame staging empty.

The decoder acceptance gate is therefore complete for the initial seven-PGN set. JavaScript remains available as the oracle/fallback; additional typed PGNs still require the same bounded parity test before inclusion.

## Interim mapped-JSONL MasterBus converter validation

```text
MasterBus Signal K replay sample
  -> typed TSV
  -> unlogged staging tables
  -> masterbus_merge_staged_log_v1(log_file_id)
  -> typed electrical tables and import status
```

Validated typed tables:

```text
masterbus_alternator_samples_v1
masterbus_battery_samples_v1
masterbus_inverter_charger_samples_v1
masterbus_solar_samples_v1
```

Synthetic validation confirmed:

- source-log inventory/status handling;
- typed numeric and boolean conversion;
- duplicate-key coalescing;
- sparse update merging;
- alternator, battery, inverter/charger and solar rows.

A bounded real mapped Signal K JSONL validation completed on 2026-07-21. A 65-second capture contained 638 battery deltas from `battery-2` and `house-batt`; conversion emitted 638 typed staging rows with no skips, and merge coalesced them into 221 timestamp/device samples. Voltage, current, temperature, state-of-charge and time-remaining values were present. This validates typed conversion and merge behavior, not the end-state source path. Native decoded Mastervolt/MasterBus field-event capture before Signal K mapping must still be implemented and validated for battery, alternator, inverter/charger and solar data.

This validation found and fixed an inventory bug: merge previously replaced the source JSONL `line_count` with the number of coalesced typed rows. Source line count now remains immutable import provenance.

### Native MasterBus source validation

On 2026-07-21, native `masterbus-native-event-v1` capture was deployed inside `masterbus-signalk` before Signal K mapping. A live 257-event sample converted with zero skips into 82 alternator, 77 battery, 57 inverter/charger and 41 solar staging rows. Repeated merge into a disposable PostgreSQL clone remained idempotent at 69 alternator, 42 battery, 45 inverter/charger and 30 solar typed rows; lower merged counts reflect sparse same-timestamp/device coalescing. No batch was loaded into live PostgreSQL.

During a physical starboard-only run at approximately 1500 RPM, Signal K reported `alpha-stbd.senseVoltage` around 13.79 V, field current around 3.02 A, alternator voltage around 13.72 V and the derived starboard engine state `started`. Port sense voltage was 0 V. The observation also exposed a startup-only discovery failure; restarting the bridge recovered both Alpha paths, and the deployed bridge now requests a systemd restart if a previously absent device later appears.

## Current limitations

- Validation samples are deliberately small.
- No broad historical import has been approved.
- The 2026-07-21 bounded real-data comparison selected typed-only direct provenance: 20 MB versus 55 MB for envelope-plus-typed, a 63.1% reduction across 118,149 decoded envelopes and 109,768 typed rows.
- Both the older mapped Signal K sample and the native pre-mapping field-event sample have converter evidence. Hourly segmentation and daily compression/90-day retention are implementation/configuration validated and remain routine monitoring; settled-file delete/rebuild remains the batch-acceptance gate.
- Each newly supported PGN needs a bounded representative sample and test fixture.
- The cited AIS sample had real rows for `129038` and `129794`, but zero rows for `129039`, `129809` and `129810`. Those three have synthetic converter/schema/merge coverage only and must not be described as representative-real-data validated.
- Nested `129540` satellite and `129285` waypoint children are keyed by source-list position within `(time, raw_file_id, message_index)`, not by PRN or waypoint id. This preserves order and repeated identities across idempotent merges. Empty lists emit zero child rows rather than an invalid/invented null-index row.

## Reproduce safely

Run repository tests:

```bash
npm test
```

For converter-only N2K validation, use `--dry-run` and `--sample-lines`.

Do not run a complete-file import on live `pi5nvme`. Follow [`2026-07-04-backfill-strategy.md`](2026-07-04-backfill-strategy.md) for staging limits.

## Acceptance for the next stage

Before expanding historical volume:

1. tests pass;
2. the implemented typed-only model continues to preserve direct provenance and idempotence;
3. representative real alternator, inverter/charger and solar logs pass typed merge validation;
4. duplicate import remains idempotent;
5. row counts and representative values match source decoder output;
6. resource use stays within declared limits;
7. no live Signal K, MasterBus or raw acquisition service is affected.

## 2026-07-21 settled native-file delete/rebuild gate

Source was the settled, rotated file `/srv/boat/masterbus/native-events/masterbus-native-20260721T070000Z.jsonl`, copied from `pi5nvme` only after the active `080000Z` file appeared. The local staging copy was 2,893,597 bytes, SHA-256 `846e2088af460a974e6be8e340ea84e29e3dcb75767dde11858a2952361b0347`, 11,418 lines/events, first event `2026-07-21T07:26:31.291Z`, last event `2026-07-21T07:59:59.643Z`. The converter emitted 3,545 alternator, 3,338 battery, 1,938 inverter/charger and 2,597 solar rows with zero skips. Merge coalesced these into 2,937, 2,124, 1,482 and 2,376 typed samples respectively.

The first import and second identical import reused inventory id 1 and produced identical typed counts; stage tables were empty after each merge. The four typed tables were exported without inventory ids, then all typed rows and inventory were deleted from disposable staging. Counts for logs, typed tables and staging were all zero. Re-import created inventory id 3 and produced the same counts; normalized exports matched exactly. This proves idempotence and exact reconstruction for the settled file. A forced disposable `psql` failure left only one retryable `staged` inventory row and zero typed/staging rows; that row was then removed safely before the final validation state. Limits were 5 MB input, 20,000 lines, 120 seconds per child process, 256 MiB memory planning/RSS guard, 200 MB workspace and 1 GB minimum free disk. Observed imports took 656, 646 and 669 ms; peak RSS was 67,736–68,408 KiB, workspace 4,076,872 bytes and free disk was approximately 883 GB.

## 2026-07-21 seven-PGN Rust staging batch

Source was settled mirrored picanm data `/srv/boat/raw-n2k/can0-20260713T070000Z.candump.log.gz`, copied locally as `/tmp/can0-20260713T070000Z.candump.log.gz`. Compressed source SHA-256 is `6a89f1e923f6285ba27c5a65e804f25298323f6f8ddacda991bfb2bf29dc2deb`, size 14,401,497 bytes, 1,395,606 lines, edge range `(1783925992.757488)` to `(1783929596.202725)`. The bounded sample was the first 10,000 settled lines, 509,000 prepared bytes, edge range `(1783925992.757488)`–`(1783926024.290631)`.

The Rust decoder was `canboat-core` revision `d0f7f24a41b1274f63b71f08703539554523858f`, embedded schema `7.1.0`; repository source checksums were `Cargo.lock` `19ec192e09e0e3a7b248520a5dcb800f3bb6b756806b91fc5885dc0288b4b557`, `Cargo.toml` `a363c78dca4922f3833ac8f55adc0fdcf7bf09d9bedcb7c27598a697d32bd715`, `src/main.rs` `94aad5dc847c5048bb4cfec05aecc34f32f994a1dbc47b504dcfb565864650bf`. Research mode was `none`. Each import decoded 5,752 frames, 2,810 typed rows, zero research rows and zero malformed rows; merged selected typed rows were 498 (129025), 204 (129026), 552 (127250), 1,094 (127245), 131 (128259), 77 (128267) and 254 (130306), total 2,810. Null rates for the selected representative required fields were 0% except rudder position 10.969% and water-depth below-transducer 100% (the latter reflects this sample's decoded availability, not a conversion error).

The Rust batch was imported twice with no count change. `n2k_frames_stage_v2` and `n2k_research_fields_v2` were empty after merge. Disposable staging was cleared with `TRUNCATE n2k_raw_files_v2 CASCADE`, which removed typed rows, file/source summaries and import runs; all were verified zero, then the batch was rebuilt. Per-table normalized row counts and MD5 hashes matched exactly: 129025 498 `bd933a34c62d84f87d308a07a31a4f28`; 129026 204 `d7d10aab84cdf5ee55f56770c0455a55`; 127250 552 `177bc7e93fe38de30a5f306340a16253`; 127245 1,094 `27542f02870355f78319aa3799149dd2`; 128259 131 `e6acd18a3903cdb1dfa0950f8ce7f776`; 128267 77 `5911fd1bf177825193358389c71bcefe`; 130306 254 `096cbf01edad2b0f42c531ab6d5a4107`. Resource limits were 20 MB source, 10,000 sample lines, 120 seconds, 512 MiB memory planning, 1 GB workspace and 1 GB free disk. The final source-provenance run took 331 ms, peak RSS was 72,052 KiB, workspace was 1,035,722 bytes and free disk was approximately 883 GB. The measured database-size run grew from 38,295,219 to 40,228,531 bytes (1,933,312 bytes). The inventory row now records the compressed source size/checksum, while `preparedSizeBytes` was 509,000.

The local staging clone initially contained the obsolete frame-linked schema and no TimescaleDB extension. The documented reset migration `004a_reset_n2k_typed_provenance.sql` was applied; a temporary staging-only SQL copy omitted only `CREATE EXTENSION timescaledb` and `create_hypertable` calls. No production SQL or live host was changed.
