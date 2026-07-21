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

A bounded real MasterBus replay-log validation is still required.

## Current limitations

- Validation samples are deliberately small.
- No broad historical import has been approved.
- The final N2K provenance choice—typed-only versus envelope-plus-typed—still requires a measured storage/query comparison.
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
2. typed-only/envelope storage comparison is recorded;
3. a small real MasterBus replay log passes typed merge validation;
4. duplicate import remains idempotent;
5. row counts and representative values match source decoder output;
6. resource use stays within declared limits;
7. no live Signal K, MasterBus or raw acquisition service is affected.
