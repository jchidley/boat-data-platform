# picanm setup summary — 2026-06-30

This file records the current boat data setup and the decisions made so far.

## Goal

Build a reliable boat-data system around the NMEA 2000 network:

- `picanm`: bare-bones NMEA 2000 gateway and raw logger.
- `pi5nvme`: heavier processing, dashboards, databases, plugins, and custom analysis.
- Tablets/phones/laptops: clients for dashboards, OpenCPN, Signal K web apps, and monitoring.

The current boat connection is only a subset of the full boat systems. Treat the observed data as "currently visible on this NMEA 2000 segment", not a complete vessel inventory.

## Hardware in use

### picanm

- Raspberry Pi 3 Model A Plus Rev 1.0
- Raspberry Pi OS / Debian 13 `trixie`, arm64
- PiCAN-M HAT installed
- Hostname: `picanm`
- IP observed: `192.168.1.235`
- Role: minimal NMEA 2000 collector/gateway

### pi5nvme

- Larger Raspberry Pi with NVMe storage
- Reachable as `ssh jack@pi5nvme`
- Role: heavier services and analysis; may be up or down independently of `picanm`

## picanm configuration performed

### CAN / PiCAN-M

Enabled the PiCAN-M MCP2515 CAN controller via `/boot/firmware/config.txt`:

```ini
dtparam=spi=on
dtoverlay=mcp2515-can0,oscillator=16000000,interrupt=25,spimaxfrequency=1000000
```

Installed:

- `can-utils`
- `python3-can`

Created systemd service:

```text
/etc/systemd/system/can0-nmea2000.service
```

Purpose:

```bash
ip link set can0 up type can bitrate 250000 restart-ms 100
```

`250000` is the standard NMEA 2000 bitrate.

Verified:

- `can0` exists
- MCP2515 initializes successfully
- `can0` is `ERROR-ACTIVE`
- live NMEA 2000 traffic is present

### Minimal Signal K on picanm

Installed:

- Node.js 24 from NodeSource
- `signalk-server`

Created:

```text
/etc/systemd/system/signalk.service
/home/jack/.signalk/settings.json
```

Signal K is configured to read NMEA 2000 from `can0` using canboatjs.

Access URLs:

```text
http://picanm:3000
http://192.168.1.235:3000
http://picanm:3000/signalk/v1/api/
ws://picanm:3000/signalk/v1/stream
```

Decision: keep this Signal K instance minimal. Do not load it with databases, dashboards, OpenCPN, or heavy plugins.

### Compact raw NMEA 2000 logger

Created:

```text
/usr/local/bin/n2k-raw-logger
/etc/systemd/system/n2k-raw-logger.service
/var/log/n2k/
```

The logger runs:

```bash
candump -L can0 | gzip -1
```

It writes hourly compressed files:

```text
/var/log/n2k/can0-YYYYMMDDTHHMMSSZ.candump.log.gz
```

Important properties:

- compact gzip-compressed candump logs
- `candump -L` format is replayable and easy to parse later
- no local retention limit by default
- if `pi5nvme` is down, `picanm` still records raw traffic locally

A 30-second sample compressed to about 64 KiB, roughly estimating ~180 MiB/day for the currently observed traffic rate. This will vary with actual bus load.

## Data currently decoded by Signal K

Examples observed from `http://picanm:3000/signalk/v1/api/vessels/self`:

```text
steering.rudderAngle
navigation.position
navigation.datetime
navigation.headingMagnetic
navigation.rateOfTurn
navigation.attitude
navigation.speedOverGround
navigation.courseOverGroundTrue
navigation.speedThroughWater
navigation.speedThroughWaterReferenceType
navigation.log
navigation.trip.log
navigation.gnss.satellites
navigation.gnss.type
navigation.gnss.methodQuality
navigation.gnss.horizontalDilution
navigation.gnss.positionDilution
environment.wind.speedApparent
environment.wind.angleApparent
environment.depth.belowTransducer
environment.depth.transducerToKeel
environment.depth.belowKeel
environment.water.temperature
environment.outside.pressure
```

This suggests that the currently visible NMEA 2000 subset includes at least:

- GNSS / GPS
- heading / rate of turn / attitude source
- wind source
- depth / speed-through-water / water temperature source
- rudder angle / steering-related source
- environmental pressure source

Not yet confirmed in the visible subset:

- engine data
- fuel/tank data
- battery/charging/inverter data
- AIS
- autopilot command/control state
- alarms
- route/waypoint state

## Network/device observations

A raw CAN sample showed source addresses:

```text
0x01, 0x03, 0x0A, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x16, 0x23
```

Several address claims were seen. Manufacturer codes and function/class values were extracted, but friendly product names were not fully mapped yet.

## Safety decisions

For now this system is observational.

Avoid until deliberately designed and reviewed:

- sending navigation data back onto NMEA 2000
- autopilot commands
- AIS spoofing
- GPS/heading/depth spoofing
- arbitrary PGN injection
- high-rate rebroadcasts onto the N2K bus

Signal K/canboat does claim an address and may send minimal NMEA 2000 identity/request frames. It is not being used to send control/navigation commands.

## Operational commands

Check picanm services:

```bash
systemctl status can0-nmea2000.service
systemctl status signalk.service
systemctl status n2k-raw-logger.service
```

Check CAN state:

```bash
ip -details -statistics link show can0
```

Watch raw NMEA 2000:

```bash
candump can0
```

Watch decoded sample:

```bash
/usr/lib/node_modules/signalk-server/node_modules/.bin/candumpjs can0
```

Check Signal K API:

```bash
curl http://picanm:3000/signalk/v1/api/vessels/self
```
