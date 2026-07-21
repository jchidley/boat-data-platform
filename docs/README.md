# Documentation map

Use these docs as the current source of truth. Document roles are intentionally separated:

- `plan.md`: stable target architecture and ownership boundaries;
- `llm-implementation-brief.md`: deployed state and next operational tasks;
- thematic plans: detailed implementation design;
- dated documents: evidence and incident history, not competing current plans.

## Read first

1. [`plan.md`](plan.md) — end state and shortest route to it.
2. [`llm-implementation-brief.md`](llm-implementation-brief.md) — deployed state and immediate operational task.
3. [`postgresql-storage-plan.md`](postgresql-storage-plan.md) — implementation rules for the new typed historical path.
4. [`postgresql-end-state-migration.md`](postgresql-end-state-migration.md) — one-time removal of deployed objects outside the end state.
5. [`2026-07-03-boat-discovery-and-decoder-inventory.md`](2026-07-03-boat-discovery-and-decoder-inventory.md) — devices, available data and decoder gaps.
6. [`2026-07-03-pi5nvme-incident-and-picanm-status.md`](2026-07-03-pi5nvme-incident-and-picanm-status.md) — resource-safety limits for live-host work.

Read other documents only when their specific subject is needed.

## Current rules

- Treat raw NMEA 2000 candump logs as the source of truth for N2K.
- Treat MasterBus discovery/config snapshots and append-only `masterbus-native-event-v1` logs as the source material for Mastervolt/MasterBus. Native decoded events are captured inside the single USB-owning bridge before Signal K mapping. Mapped Signal K JSONL is retained comparison/fallback evidence only.
- The project is experimental, but work is directed at the documented end state rather than maintaining transitional designs.
- Signal K owns current normalized state; PostgreSQL owns selected typed history and durable events. Signal K and the historical importer decode the same authoritative raw N2K format for different purposes. Do not build a complete Signal K mirror or duplicate every raw bus message in PostgreSQL without measured justification.
- PostgreSQL has controlled inputs for distinct domains—typed N2K, typed MasterBus, derived events, and health—but each historical fact has exactly one owner. Grafana and other historical consumers read PostgreSQL; normal operation does not replay SQL history into Signal K.
- Keep `picanm` boring: collect, timestamp, log, forward. Signal K, Node.js, and npm are removed from `picanm`.
- Keep heavy services on `pi5nvme`: Signal K, MasterBus tooling, Postgres/TimescaleDB, Grafana, imports, analysis.
- Do not enable NMEA 2000 transmit/control without a separate safety review.
- Run historical N2K conversion/import only offline or on staging with explicit resource limits.

## Update order

When implementation changes, update docs in this order:

1. `llm-implementation-brief.md`
2. `plan.md`
3. the relevant runbook or inventory doc
4. historical notes only when they need stale-status clarification

## Reference documents

- [`2026-07-04-manuals-relevance-review.md`](2026-07-04-manuals-relevance-review.md) — boat and equipment facts from local manuals.
- [`2026-07-04-static-pgn-capability-matrix.md`](2026-07-04-static-pgn-capability-matrix.md) — observed and supported PGNs.
- [`2026-07-04-source-attribution-inventory.md`](2026-07-04-source-attribution-inventory.md) — current device/source attribution.
- [`signalk-llm-source-map.md`](signalk-llm-source-map.md) — local Signal K and canboat source references.

Keep current architecture in `plan.md`, deployed status in `llm-implementation-brief.md`, and detailed facts only in the relevant reference or runbook.
