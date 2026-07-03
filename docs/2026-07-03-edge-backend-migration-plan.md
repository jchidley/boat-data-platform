# Migration plan: picanm as raw CAN edge, pi5nvme as data/backend host

## Goal

Move to the architecture agreed in the 2026-07-03 discussion:

```text
NMEA 2000 backbone
  ↓
picanm / Raspberry Pi 3 A+
  - SocketCAN can0 only
  - accurate edge timestamping
  - local raw CAN spool/logging
  - lightweight raw forwarding to pi5nvme
  - no heavy Signal K apps/plugins/databases
  ↓
network
  ↓
pi5nvme / Raspberry Pi 5 NVMe
  - primary Signal K server
  - NMEA 2000 decoding
  - MasterBus/Mastervolt integration
  - PostgreSQL + TimescaleDB
  - Grafana
  - Signal K apps/plugins
  - import/replay/analysis tooling
```

The Pi 3 A+ should be boring, reliable acquisition infrastructure. The Pi 5 should do everything that is CPU/RAM/storage heavy.

Related inventory document: [2026-07-03 boat discovery and decoder inventory](2026-07-03-boat-discovery-and-decoder-inventory.md).

Rebuild runbook: [rebuild from source material](rebuild-from-source-material.md).

## Pi 5 data ownership model

`pi5nvme` should hold four distinct classes of data:

```text
pi5nvme
  ├─ raw NMEA 2000 CAN archive
  │   └─ immutable candump-compatible files copied/received from picanm
  ├─ MasterBus native capture/config archive
  │   └─ Mastervolt USB discovery output, mapping/config, and periodic field snapshots if available
  ├─ Signal K runtime data
  │   └─ Signal K config, plugin state, current vessel state/cache, apps
  └─ PostgreSQL/TimescaleDB
      └─ queryable history, inventories, summaries, data quality, LLM/tooling views
```

Roles:

- **Raw NMEA 2000 CAN archive** is the byte-for-byte fidelity source of truth for N2K.
- **MasterBus native archive/config** is the best available source material for Mastervolt/MasterBus discovery, because MasterBus data cannot be rebuilt from NMEA 2000 candump logs.
- **Signal K** is the live marine application/convenience layer, not the historical source of truth.
- **PostgreSQL/TimescaleDB** is the queryable historical and analytical store for everything else: Signal K deltas, decoded N2K messages, MasterBus values, file manifests, inventories, examples, summaries, and data-quality observations.

Because this is a new experimental system, the engineering priority is:

```text
1. document what exists and how to rebuild it
2. retain raw NMEA 2000 CAN data clearly and durably
3. retain enough MasterBus native/config data to rediscover the Mastervolt system
4. make derived layers rebuildable from raw/source material where possible
```

Derived stores are allowed to be disposable. Signal K state, Timescale decoded rows, summaries, inventories, and dashboards can be deleted and rebuilt if the raw candump archive, MasterBus config/snapshots, and repo documentation are intact. This should keep the design simple and avoid premature hardening of experimental derived layers.

## Current state before migration

### picanm

Currently:

- owns the PiCAN-M / `can0` NMEA 2000 interface
- runs raw `candump` logging under `/var/log/n2k/`
- runs `n2k-raw-forwarder.service`, which will connect when `pi5nvme` exposes the raw receiver
- runs a minimal Signal K server on port `3000`
- is memory constrained but working

### pi5nvme

Currently:

- runs the fat Signal K server on port `3001`
- consumes `picanm:3000` as an upstream Signal K provider
- runs MasterBus USB integration through `masterbus-signalk`
- runs PostgreSQL/TimescaleDB
- runs Grafana
- mirrors raw N2K logs from `picanm:/var/log/n2k/` to `/srv/boat/raw-n2k/`
- stores Signal K deltas in `boatdata.signal_k_measurements`
- imports decoded raw N2K messages into `boatdata.n2k_decoded_messages`

## Target data flows

### Raw high-fidelity path

```text
picanm can0
  → edge timestamped candump-format records
  → local compressed spool in /var/log/n2k/
  → live raw stream to pi5nvme
  → pi5nvme raw archive / TimescaleDB import
```

This is the source-of-truth path. It must keep working even if Signal K or Grafana is down.

### Convenience/live application path

```text
picanm raw CAN stream
  → pi5nvme decoder / canboatjs / Signal K
  → pi5nvme Signal K paths
  → Signal K apps, Grafana, collectors, Postgres
```

Signal K becomes a consumer of raw acquisition rather than the authoritative acquisition layer.

### MasterBus path

Preferred path:

```text
Mastervolt USB on pi5nvme
  → masterbus-signalk
  → pi5nvme Signal K
  → TimescaleDB collector
```

Keep MasterBus on the Pi 5 by default because `masterbus-signalk`, debugging HID/USB permissions, Signal K integration, and database collection are all easier on the larger host.

Possible fallback path:

```text
Mastervolt USB on picanm
  → minimal masterbus forwarder or masterbus-signalk
  → pi5nvme Signal K / TimescaleDB
```

This could be useful if the MasterBus USB interface is physically closer to the Pi 3 A+ or if wiring/power layout makes it impractical to keep the Pi 5 near MasterBus. It is not the preferred default because `picanm` is RAM constrained and should remain a raw acquisition edge. If used, keep it minimal and forward data to `pi5nvme`; do not run MasterBus dashboards, databases, or experimental plugins on `picanm`.

## Hardware notes and alternatives

### Raspberry Pi 3 A+

Current preferred NMEA 2000 edge node.

Reasons:

- already working with PiCAN-M and SocketCAN
- supports Linux services, SSH, rsync, chrony/NTP, log rotation, and health checks
- can run `candump`/SocketCAN tooling directly
- easy to make boring and maintainable once Signal K is removed

### Raspberry Pi Zero 2 W

Possible but not a clear upgrade.

It may reduce size/power slightly, but it keeps similar RAM constraints and does not improve the architecture materially. Use only if packaging/power constraints require it.

### CANPico v2 with Pico WH

Do not treat this as the immediate replacement for `picanm`.

It is attractive for:

- very low power CAN listening
- deterministic microcontroller behaviour
- receive-only operation by disabling transmit
- high-resolution CAN timestamps
- lab/debug use as a USB CAN tool or secondary CAN tap

But it would replace a Linux acquisition node with custom embedded firmware. It does not naturally provide the operational pieces this project currently depends on:

- SocketCAN
- `systemd`
- SSH administration
- rsync/spool mirroring
- normal filesystem log rotation/compression
- chrony/NTP-style host observability
- direct compatibility with the current canboat/Signal K/Linux tooling

Timestamp caveat: CANPico can provide very fine relative frame timing, but the project also needs reliable absolute time alignment with `pi5nvme` and Postgres. A Pi running SocketCAN plus chrony is likely simpler and sufficient for the main boat history use case.

Recommended use for CANPico, if bought:

```text
CANPico = experimental/secondary CAN probe, USB CAN frontend, or future ultra-low-power logger
```

Not the production edge replacement until a custom firmware/forwarding/spooling story is proven.

## Timestamping requirements

Store at least three times where possible:

1. `edge_time`: when `picanm` observed the CAN frame.
2. `backend_received_time`: when `pi5nvme` received/imported it.
3. `db_inserted_time`: when Postgres inserted it.

For raw N2K fidelity, `edge_time` is the important one.

### Clock sync

- Install/enable `chrony` or equivalent on both devices.
- Make `picanm` sync to `pi5nvme` and/or normal network NTP.
- Record clock source/offset periodically on `picanm` for diagnostics.
- Later enhancement: if GPS/PPS is available, use it for better absolute time.

### Raw log and inspection formats

Use candump log format with absolute timestamps as the canonical source-of-truth format, e.g. records shaped like:

```text
(1783070123.123456) can0 09F8027F#1122334455667788
```

The exact service command should be verified on `picanm`, but the requirement is:

- one raw frame per line
- absolute timestamp included by the edge node
- interface name included
- CAN ID and payload retained without lossy translation
- hourly or size-based rotation
- compression after rotation

For AI/LLM and general tooling inspection, prefer compact SQL tables/views on `pi5nvme`. Optional sidecar files may be generated from SQL for sharing or offline inspection, but they are derived and rebuildable, not a required source of truth:

```text
/srv/boat/raw-n2k/
  can0-YYYYMMDDTHH0000Z.candump.log.gz      # canonical raw copy
  can0-YYYYMMDDTHH0000Z.manifest.json       # optional derived segment metadata
  can0-YYYYMMDDTHH0000Z.inventory.json      # optional derived PGN/source summary
  can0-YYYYMMDDTHH0000Z.sample.jsonl        # optional bounded decoded sample
  can0-YYYYMMDDTHH0000Z.summary.md          # optional human/LLM-readable summary
```

The raw candump file remains authoritative. SQL inventories/views are the normal inspection interface. Sidecars are for quick sharing, offline inspection, and explanation.

Suggested sidecar contents if generated:

- `manifest.json`: host, interface, segment start/end, frame count, byte count, checksum, logger version, compression, clock status, CAN error counters.
- `inventory.json`: PGNs, source addresses, manufacturers if known, first/last seen times, message counts/rates, decode status, unknown/proprietary PGNs.
- `sample.jsonl`: small bounded decoded examples per PGN/source, with raw CAN ID, payload, edge timestamp, decoded PGN JSON, and Signal K path if known.
- `summary.md`: concise text summary suitable for humans and LLMs: new devices, missing expected devices, noisy PGNs, stale sensors, notable proprietary data, and import status.

Keep these files small enough for tools and LLM context windows. Do not duplicate whole logs into JSONL unless there is a specific need; full-fidelity N2K history is the raw candump archive.

AI/tooling query paths should be:

1. compact SQL summaries/views for quick explanation;
2. SQL inventory tables/views for structured device/PGN discovery;
3. bounded decode examples for representative payloads;
4. detailed Timescale hypertables for historical queries;
5. raw candump only for forensic replay or decoder debugging.

## Canonical paths and retention

### Canonical paths

Use stable paths so the system is easy to inspect and rebuild:

```text
picanm:
  /var/log/n2k/                         # local raw N2K spool

pi5nvme:
  /srv/boat/raw-n2k/                    # mirrored/received raw N2K archive
  /srv/boat/masterbus/                  # MasterBus discovery/config/snapshot archive
  /srv/boat/signalk/                    # Signal K server config/state
  /etc/boat-data-platform/              # local env files/secrets references
```

Preferred raw N2K filename pattern:

```text
can0-YYYYMMDDTHH0000Z.candump.log.gz
```

Prefer UTC in filenames and timestamps.

### Retention policy for the experimental phase

Raw/source material is the priority:

- `picanm` keeps local raw N2K logs until disk pressure requires cleanup.
- `pi5nvme` keeps mirrored raw N2K logs indefinitely while the system is experimental.
- Do not delete a `picanm` raw log until it is present on `pi5nvme` and has a matching checksum or equivalent integrity record.
- Preserve MasterBus mapping/config/discovery snapshots whenever devices are rediscovered, mappings change, or tooling is upgraded.
- Signal K state, Timescale decoded rows, inventories, summaries, and dashboards are derived and may be rebuilt.

If disk pressure forces deletion, delete derived data before raw/source material.

## Phase 1 — make picanm edge services explicit

Create/verify these committed `picanm` services from `infra/picanm/`:

```text
can0-nmea2000.service
n2k-raw-logger.service
n2k-raw-forwarder.service
```

Responsibilities:

### `can0-nmea2000.service`

- configure `can0` at 250 kbit/s
- bring interface up after boot
- expose health via `ip -details -statistics link show can0`

### `n2k-raw-logger.service`

- writes edge-timestamped raw CAN logs to `/var/log/n2k/`
- rotates safely, preferably hourly
- compresses completed files
- never depends on `pi5nvme` being online

### `n2k-raw-forwarder.service`

- streams the same raw candump-format data to `pi5nvme`
- reconnects automatically
- failure does not stop local logging
- should be simple: no decoding, database writes, or plugins

Possible implementations to evaluate:

1. TCP line stream from `candump`/SocketCAN to a listener on `pi5nvme`.
2. `socketcand`/SocketCAN-over-TCP if Signal K/canboat tooling consumes it cleanly.
3. A tiny Node or shell forwarder that tails the active raw stream and reconnects.

Choose the implementation that is easiest to supervise and replay. Preserve candump-compatible text so the same stream can feed importers and Signal K/canboat tooling.

## Phase 2 — make pi5nvme the only heavy Signal K host

On `pi5nvme`:

- keep `signalk-pi5nvme.service` as the primary Signal K server
- configure its NMEA 2000 input to consume the raw stream from `picanm`, not `picanm`'s Signal K server
- keep MasterBus integration feeding this same Signal K instance
- keep webapps/plugins on `pi5nvme`

During migration, run both feeds temporarily:

```text
old: picanm Signal K → pi5nvme Signal K
new: picanm raw stream → pi5nvme Signal K
```

Then compare path counts, key values, source metadata, and decoded PGNs. Disable the old feed only after the raw-stream path is proven equivalent or better.

## Phase 3 — database ingestion model

Keep raw candump files as the byte-for-byte source of truth, but ingest enough structured summaries into Timescale/Postgres that humans, scripts, and LLM agents can inspect the boat without reading huge log files.

Use two classes of tables:

1. **fidelity/history tables**: detailed time-series data for replay and analysis.
2. **LLM/tooling-friendly tables/views**: compact summaries, inventories, examples, and plain-English notes.

### 1. Raw/import metadata

Track every raw N2K file/stream segment:

```text
boatdata.raw_n2k_log_files
```

Should include:

- file id
- hostname/source, e.g. `picanm`
- interface, e.g. `can0`
- filename/path
- first/last edge timestamp
- byte size
- frame count
- sha256 or similar checksum
- logger version
- importer version
- clock status/offset if known
- CAN error counters at start/end if known
- processed status
- error summary
- created/updated timestamps

This is the SQL equivalent of the planned `manifest.json` sidecar.

Also track MasterBus source snapshots/config separately:

```text
boatdata.masterbus_snapshots
```

Initial version can be simple and rebuildable:

- snapshot time
- hostname/device path
- tool/version
- raw discovery/config JSON or text
- mapped device names/groups
- field count
- error summary

This prevents the docs from pretending that MasterBus history can be reconstructed from NMEA 2000 raw CAN logs.

### 2. Decoded N2K messages

Continue using:

```text
boatdata.n2k_decoded_messages
```

This table is for decoded PGN-level history from raw logs/streams.

It should retain:

- edge timestamp
- backend/import timestamp
- raw file id / segment id
- interface
- CAN ID
- PGN
- source/destination/priority
- raw payload
- decoded JSON
- decoder name/version

### 3. Normalized Signal K measurements

Continue using:

```text
boatdata.signal_k_measurements
```

This table is for app-friendly Signal K path/value history.

It should retain:

- Signal K timestamp if supplied
- backend received timestamp
- context/path
- source
- value JSON/double/text
- source labels enough to connect back to N2K or MasterBus where possible

### 4. LLM/tooling-friendly inventory tables

Add compact summary tables or materialized views that are safe to query directly from an agent:

```text
boatdata.n2k_pgn_inventory
boatdata.n2k_source_inventory
boatdata.n2k_decode_examples
boatdata.boat_data_summaries
boatdata.data_quality_observations
```

Suggested contents:

#### `boatdata.n2k_pgn_inventory`

One row per PGN per time bucket or import segment:

- segment/file id
- PGN
- PGN name/description
- message count
- first/last seen edge time
- source address count
- approximate rate
- decode status: `decoded`, `partially_decoded`, `unknown`, `proprietary`
- whether it maps to known Signal K paths
- example decoded fields as bounded JSONB

#### `boatdata.n2k_source_inventory`

One row per observed N2K source address per segment or latest state:

- source address
- manufacturer if known
- device class/function if known
- product information if seen
- address claim NAME if seen
- first/last seen
- PGNs emitted
- likely role, e.g. `GNSS`, `wind`, `depth`, `chartplotter`, `autopilot`, `AIS`
- confidence score / notes

#### `boatdata.n2k_decode_examples`

Bounded examples for LLM/tool inspection:

- PGN
- source address
- edge timestamp
- raw CAN ID
- raw payload hex
- decoded JSON
- corresponding Signal K path if known
- sample reason, e.g. `first_seen`, `latest`, `representative`, `unknown_pgn`

This table prevents agents from needing to scan millions of raw messages to understand what a PGN looks like.

#### `boatdata.boat_data_summaries`

Optional plain-English or markdown summaries generated only when useful:

- summary scope: `day`, `session`, `manual_inventory`, or another explicit scope
- start/end time
- markdown summary
- notable new devices/PGNs
- missing expected devices
- importer/decoder versions
- generated_at

Do not generate hourly prose by default. Prefer compact SQL views unless a narrative summary replaces a real manual inspection step.

#### `boatdata.data_quality_observations`

Machine-readable observations and warnings:

- observation time/scope
- severity: `info`, `warning`, `error`
- category: `clock`, `can_errors`, `missing_data`, `stale_sensor`, `decoder_gap`, `masterbus`, `signalk`, `postgres`
- affected source/path/PGN
- message
- evidence JSONB
- suggested action

### 5. LLM-safe SQL views

Expose small views for common inspection tasks:

```text
boatdata.v_latest_boat_state
boatdata.v_recent_data_quality
boatdata.v_known_devices
boatdata.v_pgn_catalog_seen
boatdata.v_signalk_path_catalog
boatdata.v_unknown_or_proprietary_pgns
```

These views should be intentionally compact and indexed so an agent can answer questions like:

- what devices are on the boat?
- what PGNs are currently visible?
- what Signal K paths exist?
- what data is stale?
- what is decoded in raw N2K but missing from Signal K?
- what changed since the last outing?

Do not make LLMs query the full hypertables by default. Prefer summary tables/views, then drill into detailed time-series only when needed.

## Phase 4 — validation before removing picanm Signal K

Run an overlap period of at least one normal boating/session sample.

Check:

- picanm CPU/RAM before/after disabling Signal K
- CAN RX errors/drops before/after
- raw log continuity
- pi5 Signal K path count
- key navigation paths:
  - position
  - COG/SOG
  - heading
  - wind
  - depth
  - speed through water
  - rudder
  - AIS
  - autopilot state/target if available
- MasterBus paths still present
- Postgres row counts increasing
- Grafana dashboards still populated

Only then disable `picanm` Signal K.

## Phase 5 — decommission heavy work from picanm

Once validated:

```bash
sudo systemctl disable --now signalk.service
```

Or leave it installed but disabled as a break-glass fallback.

`picanm` steady-state should be:

```text
active:
  can0-nmea2000.service
  n2k-raw-logger.service
  n2k-raw-forwarder.service

inactive/disabled:
  signalk.service
  Signal K apps/plugins
  database services
  Grafana
```

## Phase 6 — health/freshness checks

Add minimal health checks on `pi5nvme` for:

- last raw frame received from `picanm`
- age of latest mirrored raw log
- CAN bus RX drops/errors from `picanm`
- picanm clock offset
- picanm disk free
- picanm memory
- Signal K path freshness
- Postgres collector freshness
- raw importer backlog

Grafana should show freshness first. Defer alerting frameworks and fancy dashboards until a real need appears.

## Phase 7 — optional improvements

- GPS/PPS time source for `picanm` or `pi5nvme`.
- Store raw CAN frames directly in a hypertable, not only decoded messages.
- Parse Navico ASCII PGN `130821` into useful fields.
- Extend MasterBus mappings beyond the currently mapped Signal K paths.
- Build replay tools to feed historical raw candump files into Signal K/canboat for decoder regression testing.
- Add retention/compression policies for raw/decoded/normalized tables.

## Rollback plan

If raw-stream decoding on `pi5nvme` is unreliable:

1. keep `picanm` raw logging active
2. re-enable `picanm` Signal K
3. point `pi5nvme` back to `picanm:3000`
4. continue mirroring raw logs for later replay

This preserves current functionality while keeping the raw source-of-truth intact.

## Immediate next implementation tasks

1. Deploy updated `infra/pi5nvme/install-pi5nvme.sh` on `pi5nvme`.
2. Verify raw stream capture into files on `pi5nvme` without touching Signal K.
3. Capture a MasterBus snapshot/export on `pi5nvme`.
4. Prove exactly how pi5 Signal K/canboat will consume the raw stream.
5. Configure pi5 Signal K/canboat input from that raw stream.
6. Run old and new paths in parallel and compare.
7. Disable `picanm` Signal K only after validation.

## Review notes

Plan review, gaps, YAGNI decisions, and go/no-go rationale are preserved in [migration plan review](archive/2026-07-03-migration-plan-review.md).
