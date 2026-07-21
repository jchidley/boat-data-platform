# Typed COPY/merge validation

## Purpose

Record the evidence that the typed N2K and MasterBus conversion paths work on bounded samples. This is validation evidence, not an operational backfill approval.

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

## Current limitations

- Validation samples are deliberately small.
- No broad historical import has been approved.
- The 2026-07-21 bounded real-data comparison selected typed-only direct provenance: 20 MB versus 55 MB for envelope-plus-typed, a 63.1% reduction across 118,149 decoded envelopes and 109,768 typed rows.
- The validated MasterBus sample is mapped Signal K JSONL, not the required native pre-mapping field-event source.
- Each newly supported PGN needs a bounded representative sample and test fixture.

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
