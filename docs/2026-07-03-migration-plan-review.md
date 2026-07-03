# Migration plan review — 2026-07-03

This file preserves the review notes for `2026-07-03-edge-backend-migration-plan.md`. Use it as rationale, not as the current task list.

## Verdict

The architecture is sound: make `picanm` a raw acquisition edge and make `pi5nvme` the application/data host. It matches the hardware limits, keeps the data-fidelity path separate from Signal K convenience, and preserves a rollback path.

Implement incrementally. The minimum successful version is:

```text
picanm raw candump logs + pi5 raw mirror + pi5 Signal K + Timescale collector
```

Justify everything beyond that with a concrete query, dashboard, reliability need, or debugging workflow.

## Strong points

- Correct separation of concerns: Pi 3 A+ collects and forwards; Pi 5 decodes, stores, displays, and experiments.
- Raw logs remain the source of truth, so decoder changes can be replayed later.
- Signal K is a convenience/application layer, not the only history.
- TimescaleDB/Postgres is the queryable long-term store, not Signal K plugin state.
- Migration is incremental: keep current `picanm` Signal K until the new raw path is proven.
- Validation covers important boat data domains and system health.
- Rollback is clear: re-enable `picanm` Signal K and keep mirroring raw logs.
- LLM/tooling support is useful when implemented as compact SQL views/summaries, not raw-log scanning.

## Weaknesses

- The plan adds moving parts: raw logger, forwarder, receiver, importer, Signal K bridge, collectors, summaries, dashboards.
- The plan can drift into data-warehouse work before raw acquisition is proven.
- Old and new Signal K feeds can create confusing duplicates unless source labels are clear.
- Pi 5 becomes the main dependency for apps, decoding, history, Grafana, MasterBus integration, and summaries.
- Postgres schema design can become over-complex if every possible device/domain is modelled too early.
- LLM-friendly summaries are trustworthy only when they link back to raw files, decoded rows, and timestamps.

## Gaps

1. Raw stream transport is not chosen.
2. Logger command/timestamp behaviour is not verified.
3. Overlap period needs clear source labels to avoid duplicate Signal K confusion.
4. Forwarding must not replace the local `picanm` spool.
5. Clock health needs an explicit test.
6. Derived rows need decoder/importer versions.
7. Experimental retention is defined; long-term off-boat backup/deletion policy is not.
8. Signal K raw-input mechanism is unproven.
9. MasterBus placement depends on physical wiring.
10. Security/access control is not covered beyond “keep it on trusted boat LAN”.

## YAGNI review

Do now:

- raw candump logging on `picanm`
- local spool on `picanm`
- raw mirror/receiver on `pi5nvme`
- service/path/port/credential-location/rebuild documentation
- checksums/manifests for raw files
- basic MasterBus discovery/config snapshot retention
- pi5 Signal K as the only heavy Signal K host
- TimescaleDB storage for Signal K measurements and decoded N2K messages, treated as rebuildable derived data
- raw file manifest table
- simple device/PGN inventory query or view
- basic freshness/data-quality dashboard

Defer until needed:

- full JSONL duplicate of every raw CAN frame
- complex per-domain schemas
- hourly generated markdown summaries
- automated LLM narrative generation
- GPS/PPS timing
- CANPico replacement
- proprietary PGN parsers without a known useful value
- moving MasterBus to `picanm` unless wiring requires it
- alerting frameworks beyond freshness checks

Rule:

> Keep the raw acquisition path simple and complete first. Add derived formats, summaries, and special schemas only when they answer a question we are actually asking or replace a manual debugging step we are actually doing.

## Feasibility spike before decommissioning

Before disabling Signal K on `picanm`, prove this path:

```text
picanm raw sample/log
  → pi5 raw receiver
  → canboatjs/analyzerjs decode
  → pi5 Signal K ingestion test
  → compare against existing picanm Signal K feed
```

Required evidence:

- decoded PGN coverage is at least as good as today
- key Signal K paths are present on `pi5nvme`
- source labels distinguish old feed from new raw feed
- edge timestamps survive the full path

## Preferred first transport

Use the simplest observable transport first:

```text
picanm candump-format text stream
  → TCP or SSH-forwarded line receiver on pi5nvme
  → append-only raw segment files
  → existing importer/analyzer tooling
```

Prove this before trying a socket-level bridge. A candump-compatible stream is easy to inspect, archive, replay, and compare with existing files.

If Signal K cannot directly consume that stream, keep the stream as the raw-fidelity path and add a small `pi5nvme` bridge process that converts it into the format canboatjs/Signal K requires.

## Go/no-go checklist for disabling `picanm` Signal K

Disable `picanm` Signal K only when all are true:

- `picanm` raw logger has continuous files with valid edge timestamps.
- `pi5nvme` receives live raw frames and archives them.
- Missed-forwarder periods recover from mirrored spool files.
- pi5 Signal K receives N2K data without depending on `picanm:3000`.
- TimescaleDB rows continue increasing for Signal K and decoded N2K data.
- Key values match between old and new feeds during overlap.
- `picanm` CPU/RAM improves or at least does not degrade.
- CAN errors/drops do not increase.
- Rollback command and config are documented.
