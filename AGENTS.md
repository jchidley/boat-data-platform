# Boat data platform agent guide

## Start here

Before changing code, services, or plans, read:

1. [`docs/llm-implementation-brief.md`](docs/llm-implementation-brief.md) — current mission, safety gates, deployed state, and active task order.
2. [`docs/plan.md`](docs/plan.md) — architecture, responsibilities, database layers, app/plugin policy, and near-term plan.
3. [`docs/signalk-llm-source-map.md`](docs/signalk-llm-source-map.md) — local Signal K / canboat / plugin source map. Use these local sources before web searches or git clones.
4. [`docs/postgresql-storage-plan.md`](docs/postgresql-storage-plan.md) and [`docs/postgresql-end-state-migration.md`](docs/postgresql-end-state-migration.md) before database work.
5. [`docs/two-engine-state-plugin-plan.md`](docs/two-engine-state-plugin-plan.md) for live engine-state semantics.
6. [`docs/2026-07-03-pi5nvme-incident-and-picanm-status.md`](docs/2026-07-03-pi5nvme-incident-and-picanm-status.md) before any `pi5nvme` work.

## Current architecture constraints

- `picanm` is a raw NMEA 2000 acquisition edge only: no Signal K, Node.js, npm, apps, plugins, database, Grafana, or analysis jobs.
- `pi5nvme` runs Signal K, MasterBus, TimescaleDB/Postgres, Grafana, dashboards, and bounded experiments.
- Raw NMEA 2000 logs are the single authoritative N2K source. Signal K decodes the live raw fanout for current state; offline/staging decoding loads selected typed history into PostgreSQL.
- Use one historical owner per fact. Do not duplicate typed N2K/MasterBus values through generic Signal K history. PostgreSQL serves Grafana, logbook/history consumers, reports, and custom APIs; normal operation does not replay SQL history into Signal K.
- MasterBus discovery/config snapshots and replayable MasterBus logs must be preserved because they cannot be rebuilt from N2K raw logs. Current MasterBus JSONL logging is mapped Signal K data, not raw MasterBus traffic.
- Stay receive-only on NMEA 2000. Do not enable transmit/control/autopilot behaviour without explicit safety review and approval.
- Do not run importers, backfills, canboat/analyzer bulk jobs, broad DB aggregates, or other heavy jobs on `pi5nvme` without explicit approval and resource limits.

## Local source references for Signal K / canboat work

Use [`docs/signalk-llm-source-map.md`](docs/signalk-llm-source-map.md) for the complete map. Key references:

- Signal K schema: `/home/jack/src/boat-study/signalk/unpacked/signalk-signalk-schema-1.8.2`
- Signal K server API: `/home/jack/src/boat-study/signalk/unpacked/signalk-server-api-2.30.0`
- Full Signal K server: `/home/jack/src/boat-study/signalk/unpacked/signalk-server-2.30.0`
- NMEA 2000 to Signal K mapping: `/home/jack/src/boat-study/signalk/unpacked/signalk-n2k-signalk-4.6.0`
- canboat PGN definitions: `/home/jack/src/boat-study/signalk/unpacked/canboat-pgns-6.0.2`
- canboatjs decoder: `/home/jack/src/boat-study/signalk/unpacked/canboat-canboatjs-3.20.0`
- TypeScript PGN definitions/utilities: `/home/jack/src/boat-study/signalk/unpacked/canboat-ts-pgns-1.11.18`
- Logbook plugin: `/home/jack/src/boat-study/signalk/unpacked/meri-imperiumi-signalk-logbook-0.9.5`

## Active near-term order

1. The PostgreSQL cleanup, disk guard, first bounded native MasterBus batch and engine-history migration were deployed on 2026-07-21. Broad conversion remains staging-only; every additional live typed batch requires explicit approval and the deployed-schema parity gate in `docs/plan.md`.
2. The repository-controlled Grafana history dashboard is deployed. Next improve its empty/open-runtime UX and historical range so manual evidence does not age out after 24 hours. Grafana 13 requires `database: boatdata` both at datasource top level and under `jsonData`. Completed runtime correctly has no data while the sole starboard interval is open; do not infer a stop at file end.
3. Keep the deployed MasterBus input paths used by the live Signal K engine-state plugin:
   - `electrical.alternators.alpha-port.senseVoltage`
   - `electrical.alternators.alpha-stbd.senseVoltage`
4. Complete port-only and both-running physical commissioning. Starboard-only and both-off are verified. Runtime history is derived from typed MasterBus intervals, not a separate hour-meter plugin, and is not yet trusted for logbook use.
5. Evaluate logbook integration only after physical commissioning and typed runtime semantics are trustworthy.
6. Automate deployed-schema/grant parity, rollback-only ingest-role preflight and Grafana API/browser acceptance before scheduling more imports.
7. A later settled MasterBus file may close the open starboard interval, but select/validate it on staging and obtain separate approval before import. Decide whether additional imports warrant a schedule based on demonstrated consumer value.
8. Define a named navigation-history consumer before any live N2K import. Start with only the seven parity-gated Rust PGNs and use the static PGN capability/source-attribution inventories before expanding scope.
9. Use schema-safe alphanumeric instance ids for new Signal K mappings. Do not expand the current hyphenated boat-specific names.

## Operational notes

- Use `pi5nvme-ip` / `picanm-ip` SSH aliases or `.local` mDNS with short timeouts; bare Starlink hostnames can resolve badly from WSL.
- Local boat manuals live under `C:\Users\jackc\OneDrive\Share for Delivery to USA\Manuals`; copy selected files to WSL `/tmp` before text extraction/searching rather than indexing `/mnt/c` directly.
- Use `npm run collect:health -- --sample-sec 10` for standard low-impact validation when appropriate.
- Install/evaluate Signal K apps/plugins only on `pi5nvme`, at most one candidate at a time, with config/package snapshots first.
