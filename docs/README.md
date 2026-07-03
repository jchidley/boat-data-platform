# Documentation map

Use these docs as the current source of truth.

## Read first

1. [`llm-implementation-brief.md`](llm-implementation-brief.md) — concise task brief for agents.
2. [`plan.md`](plan.md) — current target architecture, roles, and next steps.
3. [`2026-07-03-edge-backend-migration-plan.md`](2026-07-03-edge-backend-migration-plan.md) — migration details and go/no-go checks.
4. [`rebuild-from-source-material.md`](rebuild-from-source-material.md) — rebuild from raw N2K logs, MasterBus snapshots, and repo scripts.
5. [`2026-07-03-boat-discovery-and-decoder-inventory.md`](2026-07-03-boat-discovery-and-decoder-inventory.md) — discovered boat systems, available decoders, and gaps.

## Current rules

- Treat raw NMEA 2000 candump logs as the source of truth for N2K.
- Treat MasterBus discovery/config snapshots as the source material for Mastervolt/MasterBus.
- Treat Signal K, TimescaleDB rows, Grafana dashboards, inventories, and summaries as derived and rebuildable while the system is experimental.
- Keep `picanm` boring: collect, timestamp, log, forward.
- Keep heavy services on `pi5nvme`: Signal K, MasterBus tooling, Postgres/TimescaleDB, Grafana, imports, analysis.
- Do not enable NMEA 2000 transmit/control without a separate safety review.

## Update order

When implementation changes, update docs in this order:

1. `llm-implementation-brief.md`
2. `plan.md`
3. the relevant runbook or inventory doc
4. historical notes only when they need stale-status clarification

## Historical/status documents

These files record point-in-time setup or evidence. Do not use them as current plans if they conflict with the current docs above.

- `2026-06-30-picanm-setup-summary.md`
- `2026-06-30-pi5nvme-setup-summary.md`
- `2026-06-30-live-instrument-inventory.md`
- `2026-06-30-masterbus-tooling.md`
- `2026-06-30-masterbus-live.md`
- `2026-07-03-decoding-and-postgres-status.md`
- `2026-07-03-migration-plan-review.md`

When facts change, update the current docs first. Leave historical docs intact unless adding a stale-status note.
