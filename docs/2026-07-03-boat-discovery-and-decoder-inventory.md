# Boat discovery and decoder inventory — 2026-07-03

This document records what has been discovered about the boat so far: visible networks, devices/systems, available decoders, and known decoding gaps.

It is a point-in-time inventory, not an architecture plan. Current ownership and storage rules are defined in [`plan.md`](plan.md) and [`plan.md`](plan.md). Treat raw NMEA 2000 candump logs as authoritative N2K source material and MasterBus discovery/config plus the best available replay log as MasterBus source material.

## Architecture context

Current discovery sources:

```text
NMEA 2000 / PiCAN-M / picanm
  → authoritative raw candump logs
  → live raw fanout to Signal K for current state
  → offline/staging decode of the same raw format for selected typed PostgreSQL history

Mastervolt MasterBus USB / pi5nvme
  → masterbus-signalk → Signal K current state
  → replay/native event source → selected typed MasterBus PostgreSQL history

PostgreSQL typed history/events
  → Grafana, logbook/history consumers, reports and custom APIs
```

Raw N2K candump files remain authoritative for NMEA 2000 reprocessing. MasterBus needs its own lightweight snapshot/export/log trail; Signal K mappings alone are partial.

## Visible NMEA 2000 systems

The NMEA 2000 segment currently shows these functional areas.

### Navigation / GNSS / time

Observed/decoded PGNs include:

- `126992` System Time
- `129025` Position Rapid Update
- `129026` COG/SOG Rapid Update
- `129029` GNSS Position Data
- `129539` GNSS DOPs
- `129540` GNSS Satellites in View

Visible Signal K paths include:

- `navigation.position`
- `navigation.datetime`
- `navigation.speedOverGround`
- `navigation.courseOverGroundTrue`
- `navigation.gnss.*`

### AIS

Observed/decoded PGNs include:

- `129038` AIS Class A Position Report
- `129039` AIS Class B Position Report
- `129794` AIS Class A Static/Voyage Data
- `129809` AIS Class B static data part A
- `129810` AIS Class B static data part B

Likely visible system: Vesper Marine AIS or related AIS gateway.

### Heading / compass / motion

Observed/decoded PGNs include:

- `127250` Vessel Heading
- `127251` Rate of Turn
- `127252` Heave
- `127257` Attitude
- `127258` Magnetic Variation
- `65350` Simnet Magnetic Field

Visible Signal K paths include:

- `navigation.headingMagnetic`
- `navigation.rateOfTurn`
- `navigation.attitude`
- `navigation.magneticVariation`

### Wind

Observed/decoded PGN:

- `130306` Wind Data

Visible Signal K paths include:

- `environment.wind.speedApparent`
- `environment.wind.angleApparent`

### Depth / speed / water temperature / log

Observed/decoded PGNs include:

- `128259` Speed, Water Referenced
- `128267` Water Depth
- `128275` Distance Log
- `130310` Environmental Parameters
- `130311` Environmental Parameters
- `130316` Temperature Extended Range

Visible Signal K paths include:

- `environment.depth.belowTransducer`
- `environment.depth.belowKeel`
- `environment.depth.transducerToKeel`
- `environment.water.temperature`
- `navigation.speedThroughWater`
- `navigation.speedThroughWaterReferenceType`
- `navigation.log`
- `navigation.trip.log`

### Steering / autopilot / control-related traffic

Observed/decoded PGNs include:

- `127237` Heading/Track Control
- `127245` Rudder
- `127501` Binary Switch Bank Status
- `65341` Simnet Autopilot Angle
- `130860` Simnet AP Unknown 4

Visible Signal K paths include:

- `steering.rudderAngle`

Important safety note: autopilot/heading-control-related traffic is visible. This system should remain receive-only unless NMEA 2000 transmit/control is designed and reviewed separately.

### Chartplotter / B&G / Navico / Simrad

B&G/Navico/Simrad-style traffic is visible.

Known/likely manufacturer codes observed from address claims and samples:

| Code | Manufacturer |
|---:|---|
| 275 | Navico |
| 381 | B & G |
| 1857 | Simrad |

Observed proprietary or semi-proprietary PGNs include:

- `65313` Navico proprietary
- `65317` Navico proprietary 2
- `65341` Simnet Autopilot Angle
- `65350` Simnet Magnetic Field
- `130821` Navico ASCII Data
- `130822` Navico/BEP proprietary traffic
- `130824` Navico/SimNet proprietary traffic, seen in earlier samples
- `130860` Simnet AP Unknown 4

`130821` is especially interesting: canboat/analyzerjs decodes it as a comma-separated ASCII payload. It may contain B&G/Navico sailing, performance, or autopilot data that is not currently mapped into normal Signal K paths.

Radar note: the B&G chartplotter/radar exists, but raw radar data is not expected on NMEA 2000. Radar is likely Ethernet/IP to the chartplotter. NMEA 2000 shows chartplotter/navigation/control traffic, not radar imagery.

### CZone / BEP / switching

Observed data includes:

- `127501` Binary Switch Bank Status
- likely CZone/BEP/Navico proprietary traffic around `65280`, `130821`, `130822`

Signal K exposes some switch-bank state but not full CZone/BEP semantics.

## Visible Mastervolt / MasterBus systems

MasterBus is visible via the Mastervolt USB interface attached to `pi5nvme`.

USB device:

```text
ID 1a64:0000 Mastervolt MasterBus Link
/dev/hidraw0
```

MasterBus sidecar discovered 8 devices:

```text
aft-solars     — general, shunt
alpha-port     — alternator, battery, general, shunt
alpha-stbd     — alternator, battery, general, shunt
battery-2      — battery, relay
combimaster    — ac-in, ac-out, dc-in-out, general
easyview-5     — general, power-save, switches, widgets
fwd-solars     — general, shunt
house-batt     — battery, cluster, relay
```

Currently mapped Signal K paths include:

```text
electrical.batteries.battery-2.capacity.stateOfCharge
electrical.batteries.battery-2.capacity.timeRemaining
electrical.batteries.house-batt.capacity.stateOfCharge
electrical.batteries.house-batt.capacity.timeRemaining
electrical.chargers.combimaster.enabled
electrical.chargers.combimaster.acin.current
electrical.chargers.combimaster.acin.currentLimit
electrical.chargers.combimaster.acin.frequency
electrical.chargers.combimaster.acin.voltage
electrical.inverters.combimaster.enabled
electrical.inverters.combimaster.ac.frequency
electrical.inverters.combimaster.ac.power
electrical.inverters.combimaster.ac.voltage
electrical.inverters.combimaster.dc.current
electrical.inverters.combimaster.dc.voltage
```

The MasterBus driver reports many more native fields than are currently mapped to Signal K. Use `masterbus-tui` for the fuller native view.

## Systems not clearly visible yet

Not yet clearly seen as normal decoded NMEA 2000 data:

- engine data, e.g. `127488`, `127489`
- NMEA 2000 DC battery/electrical PGNs, e.g. `127506`, `127507`, `127508`
- tank/fluid levels, e.g. `127505`
- full CZone/BEP configuration semantics
- raw B&G radar data
- complete MasterBus solar/alternator/EasyView mapping into Signal K

Some of these may be absent, powered down, on another segment/network, proprietary, or visible only through MasterBus rather than NMEA 2000.

## Available decoders and tooling

### NMEA 2000 / CAN

Installed on `pi5nvme` via Signal K/canboatjs:

```text
@canboat/canboatjs 3.20.0
canboat PGN database: 543 PGNs
```

Useful tools:

```text
analyzerjs
candumpjs
to-pgn
```

Current importer uses `analyzerjs` with non-matches and raw data included, so unknown/proprietary frames are preserved in decoded-row JSON where possible.

### Signal K

Signal K is useful for normalized live paths and application integration. It exposes many standard values well:

- navigation position/time/COG/SOG
- heading/rate of turn/attitude
- wind
- depth/water temperature
- speed through water/log/trip
- rudder
- AIS
- selected MasterBus electrical values via `masterbus-signalk`

Signal K is not the source of truth; raw N2K files and MasterBus discovery/config snapshots are the material to rebuild from.

### MasterBus / Mastervolt

Installed on `pi5nvme`:

```text
masterbus-tui
masterbus-signalk
masterbus-set-field
```

Current Signal K mapping is useful but partial. Known mapped classes:

- `BAT` battery monitor fields
- `CMR` CombiMaster inverter/charger fields

Known not fully mapped:

- solar groups
- alternator groups
- EasyView groups/widgets/switches
- some relay/cluster/general fields

Documentation gap: keep a lightweight MasterBus snapshot/export whenever the system is rediscovered or mappings change. At minimum preserve the generated mapping/config and a text/JSON field dump from `masterbus-tui` or equivalent tooling.

## Decoder coverage summary

| Area | Data visible? | Decoder available? | Signal K mapping? | Notes |
|---|---:|---:|---:|---|
| GNSS/position/time | yes | yes | yes | Standard N2K coverage good |
| AIS | yes | yes | partial/yes | Raw AIS PGNs visible; app-level display depends on consumers |
| heading/rate/attitude | yes | yes | yes | Includes heave in raw decode; not all values may be prominent in Signal K |
| wind | yes | yes | yes | Apparent wind visible |
| depth/water temp/STW/log | yes | yes | yes | Standard instrument coverage good |
| rudder | yes | yes | yes | `steering.rudderAngle` visible |
| autopilot/control | yes | partial | partial | Observe only; do not transmit |
| B&G/Navico proprietary | yes | partial | partial/no | `130821` Navico ASCII needs investigation |
| CZone/BEP switching | yes | partial | partial | Binary switch state visible; full semantics missing |
| MasterBus batteries | yes | yes | yes | SOC/time remaining mapped |
| MasterBus CombiMaster | yes | yes | yes | inverter/charger AC/DC values mapped |
| MasterBus solar/alternators | yes | native driver sees fields | no/partial | needs mapping/wrapper if useful |
| engine | not clear | standard decoders exist | not visible | may be absent/off/other segment |
| tanks | not clear | standard decoders exist | not visible | may be absent/off/other segment |
| radar | chartplotter present | not via N2K | no | radar likely Ethernet/chartplotter-side |

## Known decoder gaps worth investigating later

Only investigate these when there is a concrete use case or query:

1. `130821` Navico ASCII payload parser.
2. Better mapping for `65341`, `65350`, `130860` Simnet/autopilot fields.
3. CZone/BEP proprietary switching/control semantics.
4. MasterBus solar and alternator field mapping into Signal K/Postgres.
5. Product-information/address-claim consolidation into a stable device inventory.
6. Detection of engine/tank data if those systems are later powered or connected.

## Documentation rule

When new devices, PGNs, or MasterBus fields are discovered:

1. preserve the raw/source data first: N2K candump for CAN, MasterBus snapshot/config for Mastervolt;
2. add/update SQL inventory rows or views;
3. update this document with the human-readable interpretation;
4. note whether the data is fully decoded, partially decoded, or unknown;
5. note whether it appears in Signal K or only in raw/decoded Postgres rows.
