# signalk-two-engine-state

Repo-controlled Signal K server plugin that derives twin-engine state from MasterBus alternator sense-voltage paths.

Default inputs:

- `electrical.alternators.alpha-port.senseVoltage`
- `electrical.alternators.alpha-stbd.senseVoltage`

Default outputs:

- `propulsion.port.state`
- `propulsion.starboard.state`

The outputs are canonical Signal K propulsion state strings: `started` or `stopped`. The Signal K schema also allows `unusable`, but this plugin does not emit it for transient stale data.

Defaults:

- threshold: `13.25 V`

The threshold is based on Mastervolt's published 12 V charging guidance at 25 °C: wet lead-acid float `13.25 V`, lithium float `13.5 V`, AGM/gel float `13.8 V`, and absorption `14.25 V`. The plugin uses the lower charging-voltage value, `13.25 V`, so `senseVoltage` must look like a charging voltage rather than merely a live sense wire.
- start debounce: `10 s`
- stop debounce: `30 s`

The current hyphenated alternator input paths are compatibility paths from the boat-specific MasterBus mapping. Do not use hyphenated instance ids for new mappings; prefer schema-safe aliases such as `alphaPort` / `alphaStbd` when a migration is planned.
