# MasterBus live status — 2026-06-30

After moving `pi5nvme` and plugging in the Mastervolt USB interface, the interface was detected successfully.

## USB detection

```text
Bus 003 Device 002: ID 1a64:0000 Mastervolt MasterBus Link
/dev/hidraw0 owned by root:plugdev
```

## Service status

`masterbus-signalk.service` is now running and enabled on boot.

```text
masterbus-signalk: listening on 0.0.0.0:3009
connected, heartbeat_master=None
```

The service is still configured without `heartbeat_master`, so it is using the existing MasterBus system master and is not asserting itself as the bus master.

## MasterBus devices discovered

The sidecar saw 8 MasterBus devices:

```text
0x4FF08C
0x4FF08E
0x313BAF
0x51CBE6
0x1B6164
0x302388
0x33ABF4
0x33AC6A
```

The generated mapping identified these logical devices/groups:

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

The mapping was changed from the default minimal mode to publish all monitoring groups:

```text
/etc/default/masterbus-signalk/mapping.ini
```

A backup of the original generated mapping was kept beside it.

## Signal K paths currently produced from MasterBus

MasterBus data now appears in the fat Signal K server on `pi5nvme:3001`, source `$source = masterbus`.

Current mapped paths include:

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

Example observed values:

```text
house-batt SOC             ~94.65%
battery-2 SOC              ~96.26%
combimaster inverter AC    ~120 V, 60 Hz
combimaster inverter power ~160–170 W
combimaster DC voltage     ~13.3 V
combimaster DC current     about -14 to -15 A
charger AC input           0 V / 0 A at time of sample
```

## Notes

The sidecar reported `streaming 94 of 94 fields from 8 device(s)`, but only fields with known Signal K mappings appear as Signal K paths. The TUI can be used for the fuller MasterBus-native view.

Use read-only unless deliberately changing settings:

```bash
masterbus-tui
```

Direct Signal K stream test:

```bash
nc localhost 3009
```

Fat Signal K API:

```bash
curl http://pi5nvme:3001/signalk/v1/api/vessels/self
```
