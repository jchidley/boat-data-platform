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

## Physical validation still required

Capture all four combinations:

| Port engine | Starboard engine | Expected outputs |
|---|---|---|
| Off | Off | stopped / stopped |
| On | Off | started / stopped |
| Off | On | stopped / started |
| On | On | started / started |

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
MasterBus replay/native events
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
- Typed MasterBus history can independently reproduce the same transitions.
- Tests pass and standard health checks remain healthy.
