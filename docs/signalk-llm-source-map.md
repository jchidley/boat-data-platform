# Signal K local source map for LLM/AI agents

Date: 2026-07-04

Purpose: point LLM/AI agents at the local Signal K / NMEA 2000 reference tarballs and unpacked source, so they use local material before web searches or git clones.

## Source locations

Tarballs downloaded with `npm pack`:

```text
~/src/boat-study/signalk/tarballs/
```

Unpacked source:

```text
~/src/boat-study/signalk/unpacked/
```

Minimal shallow/sparse git sources:

```text
~/src/boat-study/signalk/git-repos/
```

Manifests:

```text
~/src/boat-study/signalk/manifests/npm-download-plan-20260704.tsv
~/src/boat-study/signalk/manifests/npm-download-results-20260704.tsv
~/src/boat-study/signalk/manifests/unpacked-results-20260704.tsv
~/src/boat-study/signalk/manifests/canboat-rs-minimal-clone-20260706.tsv
```

Compressed npm tarball total before DB study add-on: about `12 MB`.

Unpacked npm total: about `39 MB`.

Additional `canboat-rs` sparse clone working-tree total: about `4 MB`.

## Unpacked package map

| Purpose | Local path |
|---|---|
| Signal K schema/spec paths/units | `~/src/boat-study/signalk/unpacked/signalk-signalk-schema-1.8.2` |
| Signal K plugin/server API | `~/src/boat-study/signalk/unpacked/signalk-server-api-2.30.0` |
| NMEA 2000 to Signal K mapping | `~/src/boat-study/signalk/unpacked/signalk-n2k-signalk-4.6.0` |
| canboatjs NMEA 2000 decoder | `~/src/boat-study/signalk/unpacked/canboat-canboatjs-3.20.0` |
| canboat JSON PGN definitions | `~/src/boat-study/signalk/unpacked/canboat-pgns-6.0.2` |
| TypeScript PGN definitions/utilities | `~/src/boat-study/signalk/unpacked/canboat-ts-pgns-1.11.18` |
| NMEA 0183 to Signal K mapping | `~/src/boat-study/signalk/unpacked/signalk-nmea0183-signalk-3.20.1` |
| Full Signal K server implementation | `~/src/boat-study/signalk/unpacked/signalk-server-2.30.0` |
| Derived-data plugin example | `~/src/boat-study/signalk/unpacked/signalk-derived-data-1.45.0` |
| Automatic logbook plugin/app | `~/src/boat-study/signalk/unpacked/meri-imperiumi-signalk-logbook-0.9.5` |
| Rust canboat implementation, selected source only | `~/src/boat-study/signalk/git-repos/canboat-rs-minimal` |

## `canboat-rs` local source

`canboat-rs` is a Rust sister project to canboat/canboatjs:

- upstream: <https://github.com/canboat/canboat-rs>
- local path: `~/src/boat-study/signalk/git-repos/canboat-rs-minimal`
- branch: `main`
- local commit: `18723ebc7750828fced868b1c490d17f401c7118`
- vendored canboat PGN database ref (`crates/canboat-core/data/CANBOAT_REF`): `182e008ba47ea7fbc1136300dfae46a22f4802fc`
- clone method: `--depth 1 --single-branch --filter=blob:none --sparse`
- sparse checkout: README/LICENSE/workspace metadata plus selected crates:
  - `crates/canboat-core/**`
  - `crates/canboat-schema/**`
  - `crates/analyzer/**`
  - `crates/candump2analyzer/**`
  - `crates/canboat-pipeline/**`
  - `crates/canboat-tui/**`

Use `canboat-rs` to study the newer Rust decoder architecture:

- `canboat-core`: sans-I/O PGN database, reassembly, decoder, encoder, output formatters;
- `crates/canboat-core/data/canboat.json`: vendored canboat PGN database;
- `crates/canboat-core/data/CANBOAT_REF`: upstream canboat commit for the vendored database;
- `analyzer`: canboat-compatible analyzer implementation;
- `candump2analyzer`: conversion from candump-like logs into analyzer formats;
- `canboat-pipeline`: integrated device/log decode and TCP fan-out pipeline;
- `canboat-tui`: interactive/log inspection tool.

## Agent rules

1. Use the unpacked local source first.
2. Do not clone upstream repos unless explicitly asked.
3. Do not run `npm install` inside these source directories unless explicitly asked.
4. Do not modify `/srv/boat/signalk` while studying source.
5. Treat `/srv/boat/signalk` and `/etc/default/masterbus-signalk` only as live deployment/config references.
6. Preserve receive-only behavior: no CAN transmit, autopilot control, or broad automation without explicit approval.
7. For NMEA 2000 identifiers, inspect canboat definitions before concluding data is unknown.

## How to use the sources

### To propose or validate Signal K paths

Read:

```text
~/src/boat-study/signalk/unpacked/signalk-signalk-schema-1.8.2
```

Then answer:

- Is there a canonical path?
- What units are expected?
- What value type is expected?
- Is the path under the right branch, e.g. `navigation`, `electrical`, `propulsion`, `environment`, `notifications`?

### To understand plugin implementation

Read:

```text
~/src/boat-study/signalk/unpacked/signalk-server-api-2.30.0
~/src/boat-study/signalk/unpacked/signalk-derived-data-1.45.0
```

Then, if needed, inspect:

```text
~/src/boat-study/signalk/unpacked/signalk-server-2.30.0
```

### To understand NMEA 2000 decoding

Read in this order:

```text
~/src/boat-study/signalk/unpacked/canboat-pgns-6.0.2
~/src/boat-study/signalk/unpacked/canboat-ts-pgns-1.11.18
~/src/boat-study/signalk/unpacked/canboat-canboatjs-3.20.0
~/src/boat-study/signalk/git-repos/canboat-rs-minimal
~/src/boat-study/signalk/unpacked/signalk-n2k-signalk-4.6.0
```

Then answer:

- Is the PGN defined in the canboat PGN database?
- Is the definition present in both npm `@canboat/pgns` and the `canboat-rs` vendored `canboat.json`?
- Is it decoded by canboatjs?
- Is it decoded by canboat-rs `canboat-core` / `analyzer`?
- Is it mapped by n2k-signalk?
- If not, is it standard-unknown, proprietary, or only missing from Signal K mapping?

### To study Signal K database/history providers

Read:

```text
~/src/boat-study/signalk/unpacked/signalk-to-influxdb2-2.1.3
~/src/boat-study/signalk/unpacked/signalk-questdb-1.5.1
~/src/boat-study/signalk/unpacked/signalk-parquet-0.7.41
~/src/boat-study/signalk/unpacked/signalk-database-0.2.0
```

Then answer:

- Does this plugin implement Signal K History API?
- What database/storage engine does it require?
- Does it store raw, sampled, aggregated, typed, string, position, or all values?
- How does it filter paths/sources/contexts?
- Does it add another service/container/database?
- Is it compatible with this repo's PostgreSQL/TimescaleDB architecture, or only useful as a reference?

### To study logbook integration

Read:

```text
~/src/boat-study/signalk/unpacked/meri-imperiumi-signalk-logbook-0.9.5
```

Use it only after typed engine transitions and runtime are trustworthy. PostgreSQL remains the historical owner.

## Current known bus-data questions

For this boat, prioritize these questions:

1. Can native decoded MasterBus field events provide a replay source for typed PostgreSQL history?
2. Can typed alternator history reproduce the deployed live `propulsion.*.state` transitions?
3. Unknown/proprietary NMEA 2000 PGNs seen in live sources:

```text
65313, 65317, 65350, 130821, 130822, 130824, 130860
```

4. For each PGN, determine whether canboat already has definitions and whether n2k-signalk maps them.

## Useful grep commands

```bash
rg -n "propulsion|alternator|electrical|battery|runTime|state" ~/src/boat-study/signalk/unpacked/signalk-signalk-schema-1.8.2
rg -n "127488|127489|127505|127506|127508|130824|130822|65313|65317" ~/src/boat-study/signalk/unpacked/canboat-pgns-6.0.2 ~/src/boat-study/signalk/unpacked/canboat-ts-pgns-1.11.18 ~/src/boat-study/signalk/unpacked/canboat-canboatjs-3.20.0 ~/src/boat-study/signalk/git-repos/canboat-rs-minimal ~/src/boat-study/signalk/unpacked/signalk-n2k-signalk-4.6.0
rg -n "handleMessage|delta|subscribe|plugin" ~/src/boat-study/signalk/unpacked/signalk-server-api-2.30.0 ~/src/boat-study/signalk/unpacked/signalk-derived-data-1.45.0
```
