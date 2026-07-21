# 2026-07-04 source-attribution inventory

Purpose: attribute current Signal K paths and current raw NMEA 2000 PGN source addresses before building dashboards that assume a device source.

This report is generated from saved low-impact Signal K API snapshots only:

- Sources snapshot: `observations/source-attribution/20260704T045312Z/signalk-sources.json`
- Vessel snapshot: `observations/source-attribution/20260704T045312Z/signalk-vessel-self.json`
- Snapshot directory: `observations/source-attribution/20260704T045312Z`

No raw import/backfill, analyzer bulk job, broad database aggregate, or NMEA 2000 transmit/control action was run.

## NMEA 2000 source-address inventory from Signal K /sources

| SA | Manufacturer | Class | Function | Instance | CAN name | PGNs seen in /sources |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | Navico | Internetwork device | 135 | 0 | c0328700227b5695 | 60928 |
| 1 | Navico | Steering and Control surfaces | 140 | 0 | c0508c002276828b | 59904, 60928 |
| 2 | Navico | Steering and Control surfaces | 140 | 0 | c0508c00227a9695 | 60928 |
| 3 | B & G | Steering and Control surfaces | 140 | 0 | c0508c002fbb155b | 59904, 60928 |
| 4 | Navico | Steering and Control surfaces | 150 | 0 | c0509600227d1695 | 59904, 60928, 65305, 127237, 127501, 130821, 130860 |
| 5 | B & G | Steering and Control surfaces | 140 | 0 | c0508c002fbbcb1c | 60928, 126993 |
| 6 | Navico | Steering and Control surfaces | 155 | 0 | c0509b0022709695 | 60928, 127245 |
| 7 | Navico | Steering and Control surfaces | 155 | 0 | c0509b002270d695 | 60928, 127245 |
| 8 | B & G | Navigation | 135 | 0 | c07887002fb80b1c | 60928, 65313, 65317, 126993 |
| 9 | B & G | Navigation | 135 | 0 | c07887002fb84b1c | 60928, 65313, 65317, 126993, 130310, 130311, 130312 |
| 10 |  |  |  |  |  | 59904, 65350, 126993, 127250, 127251, 127252, 127257 |
| 11 | B & G | Navigation | 145 | 0 | c07891002fb68b1c | 60928, 126992, 126993, 127258, 129025, 129026, 129029, 129539, 129540 |
| 12 | B & G | Navigation | 190 | 0 | c078be002fbb8b1c | 60928, 126993, 127258, 129284, 129285, 130824 |
| 13 | Simrad | Instrumentation/general systems | 190 | 0 | c0a0be00e8354b4d | 60928, 127245 |
| 14 | B & G | External Environment | 130 | 0 | c0aa82002fa0d5a6 | 60928, 126993, 130306 |
| 15 | B & G | Display | 130 | 0 | c0f082002fbe0dff | 60928, 126993, 127258, 130822 |
| 16 | B & G | Display | 130 | 0 | c0f082002fbe246f | 60928, 126993, 127258, 130822 |
| 17 | B & G | Display | 130 | 0 | c0f082002fbe24c9 | 60928, 126993, 127258, 130822 |
| 18 | B & G | Display | 130 | 0 | c0f082002fbf8b1c | 60928, 126993, 130822 |
| 22 | Vesper Marine Ltd | Navigation | 195 | 0 | c078c3003f0497df | 60928, 126993, 127250, 127258, 129025, 129026, 129029, 129038, 129539, 129540, 129794, 130310, 130311, 130314 |
| 35 | Airmar | Navigation | 136 | 0 | c078880010eb754a | 60928, 126993, 128259, 128267, 128275, 130310, 130311, 130316 |
| 100 | Signal K | Internetwork device | 130 | 0 | c03382007ced5770 | 126998 |

## Current Signal K path source summary

| Signal K source | N2K SA | Current path count | PGNs on current paths | Path groups |
| --- | --- | --- | --- | --- |
| picanm-raw-candump-fanout.4 | 4 | 58 | 65305, 127237, 127501 | electrical.switches, steering.autopilot |
| masterbus |  | 43 |  | electrical.alternators, electrical.batteries, electrical.chargers, electrical.inverters, electrical.solar |
| picanm-raw-candump-fanout.11 | 11 | 13 | 129025, 129026, 129029, 129540 | navigation.courseOverGroundTrue, navigation.datetime, navigation.gnss, navigation.position, navigation.speedOverGround |
| picanm-raw-candump-fanout.35 | 35 | 7 | 128259, 128267, 128275 | environment.depth, navigation.log, navigation.speedThroughWater, navigation.speedThroughWaterReferenceType, navigation.trip |
| picanm-raw-candump-fanout.12 | 12 | 5 | 129284, 129285 | navigation.courseRhumbline |
| picanm-raw-candump-fanout.10 | 10 | 3 | 127250, 127251, 127257 | navigation.attitude, navigation.headingMagnetic, navigation.rateOfTurn |
| picanm-raw-candump-fanout.14 | 14 | 2 | 130306 | environment.wind |
| signalk-two-engine-state.XX |  | 2 |  | propulsion.port, propulsion.starboard |
| picanm-raw-candump-fanout.13 | 13 | 1 | 127245 | steering.rudderAngle |
| picanm-raw-candump-fanout.15 | 15 | 1 | 127258 | navigation.magneticVariation |
| picanm-raw-candump-fanout.22 | 22 | 1 | 130314 | environment.outside |
| picanm-raw-candump-fanout.9 | 9 | 1 | 130311 | environment.water |
| signalk-server |  | 1 |  | notifications.server |

## High-value PGN attribution checks

### Engine / tanks / N2K electrical

| PGN | Current /sources owner(s) |
| --- | --- |
| 127488 | not present in /sources snapshot |
| 127489 | not present in /sources snapshot |
| 127505 | not present in /sources snapshot |
| 127506 | not present in /sources snapshot |
| 127507 | not present in /sources snapshot |
| 127508 | not present in /sources snapshot |
| 127509 | not present in /sources snapshot |

### Airmar / instrument data

| PGN | Current /sources owner(s) |
| --- | --- |
| 128259 | 35 Airmar Navigation |
| 128267 | 35 Airmar Navigation |
| 128275 | 35 Airmar Navigation |
| 130310 | 9 B & G Navigation; 22 Vesper Marine Ltd Navigation; 35 Airmar Navigation |
| 130311 | 9 B & G Navigation; 22 Vesper Marine Ltd Navigation; 35 Airmar Navigation |
| 130312 | 9 B & G Navigation |
| 130316 | 35 Airmar Navigation |

### Vesper / AIS / GNSS candidates

| PGN | Current /sources owner(s) |
| --- | --- |
| 129025 | 11 B & G Navigation; 22 Vesper Marine Ltd Navigation |
| 129026 | 11 B & G Navigation; 22 Vesper Marine Ltd Navigation |
| 129029 | 11 B & G Navigation; 22 Vesper Marine Ltd Navigation |
| 129038 | 22 Vesper Marine Ltd Navigation |
| 129039 | not present in /sources snapshot |
| 129040 | not present in /sources snapshot |
| 129041 | not present in /sources snapshot |
| 129794 | 22 Vesper Marine Ltd Navigation |
| 129798 | not present in /sources snapshot |
| 129801 | not present in /sources snapshot |
| 129802 | not present in /sources snapshot |
| 129809 | not present in /sources snapshot |
| 129810 | not present in /sources snapshot |

### B&G / Navico proprietary and autopilot candidates

| PGN | Current /sources owner(s) |
| --- | --- |
| 65313 | 8 B & G Navigation; 9 B & G Navigation |
| 65317 | 8 B & G Navigation; 9 B & G Navigation |
| 65350 | 10 |
| 127237 | 4 Navico Steering and Control surfaces |
| 127245 | 6 Navico Steering and Control surfaces; 7 Navico Steering and Control surfaces; 13 Simrad Instrumentation/general systems |
| 127501 | 4 Navico Steering and Control surfaces |
| 130821 | 4 Navico Steering and Control surfaces |
| 130822 | 15 B & G Display; 16 B & G Display; 17 B & G Display; 18 B & G Display |
| 130824 | 12 B & G Navigation |
| 130860 | 4 Navico Steering and Control surfaces |

## Current Signal K self-vessel path attribution

| Path | Signal K source | N2K SA | PGN | Current value summary |
| --- | --- | --- | --- | --- |
| electrical.alternators.alpha-port.alternatorTemperature | masterbus |  |  | 303.15 |
| electrical.alternators.alpha-port.alternatorVoltage | masterbus |  |  | 13.617716 |
| electrical.alternators.alpha-port.current | masterbus |  |  | -4.6757536 |
| electrical.alternators.alpha-port.fieldCurrent | masterbus |  |  | 0 |
| electrical.alternators.alpha-port.senseVoltage | masterbus |  |  | 0 |
| electrical.alternators.alpha-port.temperature | masterbus |  |  | 304.81667 |
| electrical.alternators.alpha-port.voltage | masterbus |  |  | 13.702152 |
| electrical.alternators.alpha-stbd.alternatorTemperature | masterbus |  |  | 324.15 |
| electrical.alternators.alpha-stbd.alternatorVoltage | masterbus |  |  | 13.662394 |
| electrical.alternators.alpha-stbd.current | masterbus |  |  | -3.2269604 |
| electrical.alternators.alpha-stbd.fieldCurrent | masterbus |  |  | 0 |
| electrical.alternators.alpha-stbd.senseVoltage | masterbus |  |  | 13.629444 |
| electrical.alternators.alpha-stbd.temperature | masterbus |  |  | 304.81667 |
| electrical.alternators.alpha-stbd.voltage | masterbus |  |  | 13.702152 |
| electrical.batteries.battery-2.capacity.stateOfCharge | masterbus |  |  | 1 |
| electrical.batteries.battery-2.capacity.timeRemaining | masterbus |  |  | -1 |
| electrical.batteries.battery-2.current | masterbus |  |  | -2.4009721 |
| electrical.batteries.battery-2.temperature | masterbus |  |  | 305.15 |
| electrical.batteries.battery-2.voltage | masterbus |  |  | 13.710573 |
| electrical.batteries.house-batt.capacity.stateOfCharge | masterbus |  |  | 1 |
| electrical.batteries.house-batt.capacity.timeRemaining | masterbus |  |  | -1 |
| electrical.batteries.house-batt.current | masterbus |  |  | -4.5836821 |
| electrical.batteries.house-batt.temperature | masterbus |  |  | 304.48333 |
| electrical.batteries.house-batt.voltage | masterbus |  |  | 13.702152 |
| electrical.chargers.combimaster.acin.current | masterbus |  |  | 0 |
| electrical.chargers.combimaster.acin.currentLimit | masterbus |  |  | 30 |
| electrical.chargers.combimaster.acin.frequency | masterbus |  |  | 0 |
| electrical.chargers.combimaster.acin.voltage | masterbus |  |  | 0 |
| electrical.chargers.combimaster.enabled | masterbus |  |  | true |
| electrical.inverters.combimaster.ac.frequency | masterbus |  |  | 60 |
| electrical.inverters.combimaster.ac.power | masterbus |  |  | 184 |
| electrical.inverters.combimaster.ac.voltage | masterbus |  |  | 119.6 |
| electrical.inverters.combimaster.dc.current | masterbus |  |  | -16 |
| electrical.inverters.combimaster.dc.voltage | masterbus |  |  | 13.650001 |
| electrical.inverters.combimaster.enabled | masterbus |  |  | true |
| electrical.solar.aft-solars.batteryVoltage | masterbus |  |  | 13.7 |
| electrical.solar.aft-solars.chargeCurrent | masterbus |  |  | 30 |
| electrical.solar.aft-solars.panelVoltage | masterbus |  |  | 37.350002 |
| electrical.solar.aft-solars.yieldTotal | masterbus |  |  | 2058105100 |
| electrical.solar.fwd-solars.batteryVoltage | masterbus |  |  | 13.7 |
| electrical.solar.fwd-solars.chargeCurrent | masterbus |  |  | 0.58000004 |
| electrical.solar.fwd-solars.panelVoltage | masterbus |  |  | 39.860001 |
| electrical.solar.fwd-solars.yieldTotal | masterbus |  |  | 1694611700 |
| electrical.switches.bank.0.1.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 1 |
| electrical.switches.bank.0.1.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 1 |
| electrical.switches.bank.0.10.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 10 |
| electrical.switches.bank.0.10.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.11.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 11 |
| electrical.switches.bank.0.11.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.12.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 12 |
| electrical.switches.bank.0.12.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.13.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 13 |
| electrical.switches.bank.0.13.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.14.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 14 |
| electrical.switches.bank.0.14.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.15.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 15 |
| electrical.switches.bank.0.15.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.16.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 16 |
| electrical.switches.bank.0.16.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.17.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 17 |
| electrical.switches.bank.0.17.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.18.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 18 |
| electrical.switches.bank.0.18.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.19.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 19 |
| electrical.switches.bank.0.19.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.2.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 2 |
| electrical.switches.bank.0.2.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.20.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 20 |
| electrical.switches.bank.0.20.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.21.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 21 |
| electrical.switches.bank.0.21.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.22.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 22 |
| electrical.switches.bank.0.22.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.23.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 23 |
| electrical.switches.bank.0.23.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.24.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 24 |
| electrical.switches.bank.0.24.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.25.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 25 |
| electrical.switches.bank.0.25.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.26.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 26 |
| electrical.switches.bank.0.26.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.27.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 27 |
| electrical.switches.bank.0.27.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.28.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 28 |
| electrical.switches.bank.0.28.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.3.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 3 |
| electrical.switches.bank.0.3.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.4.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 4 |
| electrical.switches.bank.0.4.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.5.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 5 |
| electrical.switches.bank.0.5.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.6.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 6 |
| electrical.switches.bank.0.6.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.7.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 7 |
| electrical.switches.bank.0.7.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.8.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 8 |
| electrical.switches.bank.0.8.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| electrical.switches.bank.0.9.order | picanm-raw-candump-fanout.4 | 4 | 127501 | 9 |
| electrical.switches.bank.0.9.state | picanm-raw-candump-fanout.4 | 4 | 127501 | 0 |
| environment.depth.belowKeel | picanm-raw-candump-fanout.35 | 35 | 128267 | 61.96 |
| environment.depth.belowTransducer | picanm-raw-candump-fanout.35 | 35 | 128267 | 62.66 |
| environment.depth.transducerToKeel | picanm-raw-candump-fanout.35 | 35 | 128267 | -0.7 |
| environment.outside.pressure | picanm-raw-candump-fanout.22 | 22 | 130314 | 100592.6 |
| environment.water.temperature | picanm-raw-candump-fanout.9 | 9 | 130311 | 302.49 |
| environment.wind.angleApparent | picanm-raw-candump-fanout.14 | 14 | 130306 | 2.7579 |
| environment.wind.speedApparent | picanm-raw-candump-fanout.14 | 14 | 130306 | 1.94 |
| navigation.attitude | picanm-raw-candump-fanout.10 | 10 | 127257 | {"yaw":null,"pitch":-0.0262,"roll":0.0067} |
| navigation.courseOverGroundTrue | picanm-raw-candump-fanout.11 | 11 | 129026 | 1.5707 |
| navigation.courseRhumbline.activeRoute.name | picanm-raw-candump-fanout.12 | 12 | 129285 | 0 |
| navigation.courseRhumbline.nextPoint.name | picanm-raw-candump-fanout.12 | 12 | 129285 | "" |
| navigation.courseRhumbline.nextPoint.position | picanm-raw-candump-fanout.12 | 12 | 129284 | {"longitude":null,"latitude":null} |
| navigation.courseRhumbline.previousPoint.name | picanm-raw-candump-fanout.12 | 12 | 129285 | "" |
| navigation.courseRhumbline.previousPoint.position | picanm-raw-candump-fanout.12 | 12 | 129285 | {} |
| navigation.datetime | picanm-raw-candump-fanout.11 | 11 | 129029 | "2026-07-04T04:53:11Z" |
| navigation.gnss.antennaAltitude | picanm-raw-candump-fanout.11 | 11 | 129029 | 23.530002 |
| navigation.gnss.geoidalSeparation | picanm-raw-candump-fanout.11 | 11 | 129029 | 30.6 |
| navigation.gnss.horizontalDilution | picanm-raw-candump-fanout.11 | 11 | 129029 | 0.6 |
| navigation.gnss.integrity | picanm-raw-candump-fanout.11 | 11 | 129029 | "no Integrity checking" |
| navigation.gnss.methodQuality | picanm-raw-candump-fanout.11 | 11 | 129029 | "GNSS Fix" |
| navigation.gnss.positionDilution | picanm-raw-candump-fanout.11 | 11 | 129029 | 1.1 |
| navigation.gnss.satellites | picanm-raw-candump-fanout.11 | 11 | 129029 | 12 |
| navigation.gnss.satellitesInView | picanm-raw-candump-fanout.11 | 11 | 129540 | {"count":12,"satellites":[{"id":6,"elevation":0.2094,"azimuth":2.3911,"SNR":37}, |
| navigation.gnss.type | picanm-raw-candump-fanout.11 | 11 | 129029 | "GPS" |
| navigation.headingMagnetic | picanm-raw-candump-fanout.10 | 10 | 127250 | 1.8252 |
| navigation.log | picanm-raw-candump-fanout.35 | 35 | 128275 | 7041960 |
| navigation.magneticVariation | picanm-raw-candump-fanout.15 | 15 | 127258 | -0.1121 |
| navigation.position | picanm-raw-candump-fanout.11 | 11 | 129025 | {"longitude":130.5075344,"latitude":27.58236} |
| navigation.rateOfTurn | picanm-raw-candump-fanout.10 | 10 | 127251 | -0.02837131 |
| navigation.speedOverGround | picanm-raw-candump-fanout.11 | 11 | 129026 | 3.4 |
| navigation.speedThroughWater | picanm-raw-candump-fanout.35 | 35 | 128259 | 2.46 |
| navigation.speedThroughWaterReferenceType | picanm-raw-candump-fanout.35 | 35 | 128259 | "Paddle wheel" |
| navigation.trip.log | picanm-raw-candump-fanout.35 | 35 | 128275 | 7041960 |
| notifications.server.newVersion | signalk-server |  |  | {"state":"normal","method":[],"message":"A new version (2.30.0) of the server is |
| propulsion.port.state | signalk-two-engine-state.XX |  |  | "stopped" |
| propulsion.starboard.state | signalk-two-engine-state.XX |  |  | "started" |
| steering.autopilot.state | picanm-raw-candump-fanout.4 | 4 | 65305 | "heading" |
| steering.autopilot.target.headingTrue | picanm-raw-candump-fanout.4 | 4 | 127237 | 1.6406 |
| steering.rudderAngle | picanm-raw-candump-fanout.13 | 13 | 127245 | -0.0179 |

## Conclusions

1. Current self-vessel electrical/house/Alpha alternator/solar/inverter data is from `masterbus`, not NMEA 2000 PGNs.
2. Current synthesized engine state is from `signalk-two-engine-state.XX`, not direct Yanmar PGNs.
3. No current /sources owner is present for direct engine PGNs `127488`/`127489`, tank PGN `127505`, or N2K DC/charger/battery/inverter PGNs `127506`-`127509`.
4. Airmar source address `35` currently owns depth/STW/log and related environmental PGNs: `128259`, `128267`, `128275`, `130310`, `130311`, and `130316`.
5. Vesper source address `22` is a strong AIS/GNSS candidate: it advertises AIS/GNSS PGNs including `129025`, `129026`, `129029`, `129038`, `129794`, plus heading/environmental PGNs.
6. B&G/Navico sources dominate navigation display, wind, GNSS, display, switch-bank, route/autopilot, and proprietary traffic. Source addresses `4`, `8`, `9`, `12`, `14`, `15`-`18` are especially relevant for dashboards that mention B&G/Zeus/Navico.
7. Proprietary PGNs remain read-only context. `130821` is sourced by Navico SA `4`; `130824` by B&G SA `12`; `130822` by B&G display SAs `15`-`18`; `65313`/`65317` by B&G navigation SAs `8` and `9`.
