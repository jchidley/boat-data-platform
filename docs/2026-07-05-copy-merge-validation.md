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

The bounded wrapper imported the Rust output twice into disposable PostgreSQL without duplicates; frame staging emptied and summary count remained 6,001. Rust is not yet the default because malformed/incomplete packet, Rust-only decode and additional-file comparisons still need broader fixtures.

## MasterBus path validated

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

A bounded real MasterBus replay-log validation completed on 2026-07-21. A 65-second capture contained 638 battery deltas from `battery-2` and `house-batt`; conversion emitted 638 typed staging rows with no skips, and merge coalesced them into 221 timestamp/device samples. Voltage, current, temperature, state-of-charge and time-remaining values were present. No alternator, inverter/charger or solar updates occurred during this stationary sample, so each still requires representative real-data validation.

This validation found and fixed an inventory bug: merge previously replaced the source JSONL `line_count` with the number of coalesced typed rows. Source line count now remains immutable import provenance.

## Current limitations

- Validation samples are deliberately small.
- No broad historical import has been approved.
- The 2026-07-21 bounded real-data comparison selected typed-only direct provenance: 20 MB versus 55 MB for envelope-plus-typed, a 63.1% reduction across 118,149 decoded envelopes and 109,768 typed rows.
- MasterBus replay currently contains mapped fields, not every native field.
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
