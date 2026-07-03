# Decoding and PostgreSQL status — 2026-07-03

## Current PostgreSQL vs Signal K status

PostgreSQL/TimescaleDB is no longer just an empty schema.

Live Signal K collector:

```text
service: boat-signalk-collector.service
source:  ws://127.0.0.1:3001/signalk/v1/stream?subscribe=none
target:  boatdata.signal_k_measurements
```

Raw NMEA 2000 importer:

```text
service: boat-raw-n2k-import.service
timer:   boat-raw-n2k-import.timer
source:  /srv/boat/raw-n2k/*.candump.log.gz
target:  boatdata.n2k_decoded_messages
```

Current observed database state after initial startup/import:

```text
signal_k_measurements: ~52k rows, 112 distinct Signal K paths
n2k_decoded_messages:  ~545k rows, 56 distinct PGNs
raw_n2k_log_files:     1 processed file so far
```

The raw importer intentionally backfills gradually, one compressed log file per run, because one hourly compressed file can expand to hundreds of thousands of decoded PGN rows.

## Important distinction

Signal K and PostgreSQL now contain different but complementary data:

- Signal K is the live current-state model plus deltas.
- `signal_k_measurements` stores live Signal K path/value history from the fat Signal K server.
- `n2k_decoded_messages` stores decoded raw NMEA 2000/canboat messages from archived candump logs.
- Raw candump `.gz` files remain the source of truth for future reprocessing.

## Available decoders/tooling

### NMEA 2000 / CAN

Installed via Signal K/canboatjs:

```text
@canboat/canboatjs 3.20.0
canboat PGN database: 543 PGNs
```

Useful tools:

```text
node /usr/lib/node_modules/signalk-server/node_modules/@canboat/canboatjs/dist/bin/analyzerjs.js
node /usr/lib/node_modules/signalk-server/node_modules/@canboat/canboatjs/dist/bin/candumpjs.js
node /usr/lib/node_modules/signalk-server/node_modules/@canboat/canboatjs/dist/bin/to-pgn.js
```

The raw importer uses `analyzerjs` with:

```text
--show-non-matches --include-raw-data
```

so partially decoded / proprietary PGNs are still preserved as JSON rows.

### Mastervolt MasterBus

Installed tools:

```text
masterbus-tui
masterbus-signalk
masterbus-set-field
```

Current Signal K mapping from MasterBus is useful but partial. The upstream `masterbus-signalk` mapper currently maps these classes:

- `BAT` battery monitor fields
- `CMR` CombiMaster inverter/charger fields

It does not yet map all solar/alternator/EasyView fields into Signal K paths, even though it discovers the devices.

## Extra NMEA 2000 decodes beyond the visible Signal K tree

A fresh canboat analysis shows several PGNs that are decoded by canboat but not necessarily surfaced as normal Signal K paths.

Examples:

```text
127252  Heave
65350   Simnet: Magnetic Field
65341   Simnet: Autopilot Angle
130821  Navico: ASCII Data
129539  GNSS DOPs
129283  Cross Track Error
126996  Product Information
126993  Heartbeat
```

These are good candidates for custom extraction or dashboards from `n2k_decoded_messages`.

## Interesting proprietary / semi-proprietary areas

### Navico / B&G / Simrad

Observed proprietary-ish PGNs include:

```text
65313   Navico: Proprietary
65317   Navico: Proprietary 2
65341   Simnet: Autopilot Angle
65350   Simnet: Magnetic Field
130821  Navico ASCII Data
130822  Navico/BEP proprietary traffic
130860  Simnet AP Unknown 4
```

`130821` is especially interesting. `analyzerjs` decodes it as a comma-separated ASCII payload, for example a long message of sailing/autopilot/performance-looking numeric values. Signal K does not currently expose those fields as named paths.

### CZone / BEP

Observed traffic includes switch-bank state and proprietary control/status frames:

```text
127501  Binary Switch Bank Status
65280   manufacturer proprietary frame, likely CZone/BEP related in current samples
130821/130822 proprietary frames in the BEP/Navico range depending on decoder match
```

Signal K exposes the binary switch bank states, but not necessarily all CZone/BEP semantics.

## Current gaps

1. PostgreSQL history is now flowing, but backfill is incomplete.
2. `n2k_decoded_messages` has only started importing archived logs.
3. Navico ASCII / Simnet proprietary data is decoded as raw fields, not yet converted into stable Signal K paths.
4. MasterBus solar/alternator/EasyView groups are discovered but not yet mapped into Signal K by `masterbus-signalk`.
5. Grafana dashboards still need to be built on top of the new tables.

## Next useful decoder work

- Build SQL views for common Signal K paths.
- Build a PGN/source/device inventory view over `n2k_decoded_messages`.
- Add a focused parser for `130821` Navico ASCII messages once enough samples are stored.
- Extend or wrap `masterbus-signalk` to map useful solar/alternator fields after inspecting them with `masterbus-tui` or a field-dump tool.
