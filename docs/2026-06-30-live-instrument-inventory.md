# Live instrument inventory — 2026-06-30

This is a point-in-time inventory from the currently powered/connected NMEA 2000 segment. It is not yet a complete inventory of the whole boat.

## Decoded Signal K paths currently visible

- `navigation.position`
- `navigation.datetime`
- `navigation.speedOverGround`
- `navigation.courseOverGroundTrue`
- `navigation.headingMagnetic`
- `navigation.magneticVariation`
- `navigation.rateOfTurn`
- `navigation.attitude`
- `navigation.speedThroughWater`
- `navigation.speedThroughWaterReferenceType`
- `navigation.log`
- `navigation.trip.log`
- `navigation.gnss.*`
- `environment.depth.belowTransducer`
- `environment.depth.belowKeel`
- `environment.depth.transducerToKeel`
- `environment.water.temperature`
- `environment.wind.speedApparent`
- `environment.wind.angleApparent`
- `environment.outside.pressure`
- `steering.rudderAngle`

## Functional systems visible

### Navigation / GNSS / AIS

Visible PGNs include:

- `129025` Position Rapid Update
- `129026` COG/SOG Rapid Update
- `129029` GNSS Position Data
- `129539` GNSS DOPs
- `129540` GNSS Satellites in View
- `126992` System Time
- `129038` AIS Class A Position Report
- `129039` AIS Class B Position Report
- `129794` AIS Class A Static/Voyage Data
- `129809` / `129810` AIS Class B static data

This indicates live GPS/GNSS and AIS-related traffic are visible on this segment.

### Heading / motion / compass

Visible PGNs include:

- `127250` Vessel Heading
- `127251` Rate of Turn
- `127252` Heave
- `127257` Attitude
- `127258` Magnetic Variation

### Wind

Visible PGN:

- `130306` Wind Data

Signal K paths:

- `environment.wind.speedApparent`
- `environment.wind.angleApparent`

### Depth / speed / water temperature / log

Visible PGNs include:

- `128259` Speed, Water Referenced
- `128267` Water Depth
- `128275` Distance Log
- `130310` Environmental Parameters
- `130311` Environmental Parameters
- `130316` Temperature Extended Range

Signal K paths include depth below transducer/keel, water temperature, speed through water, log, and trip log.

### Steering / autopilot-related

Visible PGNs include:

- `127237` Heading/Track Control
- `127245` Rudder
- `127501` Binary Switch Bank Status

Signal K currently exposes at least:

- `steering.rudderAngle`

The presence of `127237` suggests autopilot/heading-control traffic is present, but this setup remains observational only.

## Source-address summary from a 30-second raw sample

Source addresses seen:

```text
0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x16,
0x23, 0x64
```

Known manufacturer codes from address claims / earlier samples:

| Code | Manufacturer |
|---:|---|
| 135 | Airmar |
| 275 | Navico |
| 381 | B & G |
| 504 | Vesper Marine Ltd |
| 1857 | Simrad |
| 999 | Signal K |

`0x64` / 100 is the Signal K/canboat gateway identity on `picanm`.

## Systems not yet obvious in decoded data

The current visible set does not yet clearly show:

- engine data, e.g. `127488`, `127489`
- battery/DC electrical status, e.g. `127506`, `127507`, `127508`
- tank/fluid levels, e.g. `127505`
- inverter/charger data
- alarms/alerts beyond ordinary navigation/instrument data

These may be absent, powered down, on another network segment, or not decoded by Signal K/canboat yet.

## Safety note

Autopilot/steering-related traffic is visible. Do not enable any NMEA 2000 transmit/command bridge without a separate review.
