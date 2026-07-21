# Two-engine live state

## Purpose

Provide current port and starboard engine state in Signal K from MasterBus alternator evidence.

This component belongs to the existing live Signal K path. Historical engine events and runtime belong to the new typed PostgreSQL path and will be derived from typed MasterBus history.

## Live inputs

```text
electrical.alternators.alpha-port.senseVoltage
electrical.alternators.alpha-stbd.senseVoltage
```

Optional diagnostic inputs:

```text
electrical.alternators.alpha-port.fieldCurrent
electrical.alternators.alpha-stbd.fieldCurrent
electrical.alternators.alpha-port.alternatorVoltage
electrical.alternators.alpha-stbd.alternatorVoltage
```

Do not use house battery current as the primary engine signal because solar, inverter and other loads affect it.

## Live outputs

```text
propulsion.port.state
propulsion.starboard.state
```

Signal K values:

```text
started
stopped
unusable
```

The deployed implementation is:

```text
infra/pi5nvme/signalk-plugins/signalk-two-engine-state/
```

## Rule

```text
started when senseVoltage > 13.25 V after debounce
stopped when senseVoltage <= 13.25 V after debounce
```

The threshold is supported by the local Mastervolt charging specifications. Start and stop debounce are configurable. Add hysteresis only if physical observations show threshold chatter.

Current hyphenated input names are boat-specific deployed Signal K paths. New mappings should use schema-safe alphanumeric identifiers.

## Safety

- Read-only observation.
- No NMEA 2000 transmission.
- No MasterBus writes.
- No engine or charging control.

## Deferred physical commissioning

Physical combinations are a commissioning checklist, not a blocker for implementation handoff. Starboard-only was verified on 2026-07-21 at approximately 1500 RPM: starboard sense voltage was about 13.7 V, field current about 3.0 A, alternator voltage about 13.6–13.7 V and the output was `started`; port sense voltage was 0 V and its output was `stopped`. Complete the remaining observations when those engine states are safely available, before using derived runtime as trusted operational/logbook history.

| Port engine | Starboard engine | Expected outputs | Status |
|---|---|---|---|
| Off | Off | stopped / stopped | required |
| On | Off | started / stopped | required |
| Off | On | stopped / started | verified 2026-07-21 |
| On | On | started / started | required |

For each transition record:

- physical engine state;
- `senseVoltage`;
- `fieldCurrent`;
- emitted Signal K state;
- transition/debounce timing.

## Historical end state

Do not persist engine history by mirroring the Signal K output.

Instead:

```text
native decoded MasterBus field-event log captured before Signal K mapping
  -> typed alternator history
  -> typed engine start/stop events
  -> runtime derived from event intervals
  -> Grafana and logbook/history consumers
```

A live `propulsion.*.runTime` value may be published into Signal K if a live application needs it, but PostgreSQL typed intervals remain the historical owner.

## Acceptance criteria

- Both live Signal K paths are fresh and source-attributed to the repo plugin.
- All four physical engine combinations produce the expected state.
- Debounce suppresses short threshold crossings.
- Plugin restart does not emit false transitions.
- Typed history loaded from native pre-Signal-K MasterBus events can independently reproduce the same transitions.
- Tests pass and standard health checks remain healthy.

## Historical implementation status — 2026-07-21

Migration `infra/pi5nvme/sql/011_masterbus_engine_history_v1.sql` now owns durable historical transitions and runtime. The rebuild function reads only `masterbus_alternator_samples_v1` for `alpha-port` and `alpha-stbd`; it never reads the live Signal K output. It uses the deployed strict `13.25 V` threshold, 10-second start debounce and 30-second stop debounce. Samples are ordered deterministically by timestamp and raw provenance. Same-key duplicate timestamps are already coalesced by the typed primary key. A gap over 120 seconds closes a running interval as `data_gap` at the last known evidence and resets state to unknown; it never infers a stop from missing data. Unresolved running intervals remain open and are excluded from completed-runtime totals. Consumers use indexed transition/runtime tables and bounded views.

On the settled native staging file, 1,025 port and 1,912 starboard alternator samples produced one open starboard `started` event at `2026-07-21T07:26:44.298Z` and no port start event. This agrees with the available physical starboard-only observation (`alpha-stbd` approximately 13.7–13.8 V and derived state `started`, port sense 0 V). It is typed native evidence and not mirrored Signal K history.

A disposable SQL regression sequence covered threshold equality, start/stop debounce, threshold chatter, a long heartbeat gap and an open/closed runtime boundary; it produced the expected start/stop/start/data-gap sequence with raw-line provenance. The migration is implemented and tested in disposable staging only. Both-off, port-only and both-running physical commissioning remain required, and runtime must not yet be presented as trusted operational/logbook history.
