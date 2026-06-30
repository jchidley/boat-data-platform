# Mastervolt MasterBus tooling — 2026-06-30

`pi5nvme` has been prepared to read a Mastervolt MasterBus system via a Mastervolt USB Interface / MasterBus USB Link.

## Why USB, not NMEA 2000?

The NMEA 2000 bus currently does not show obvious Mastervolt traffic:

- Mastervolt NMEA manufacturer code `355` was not seen in recent N2K address claims.
- Common electrical PGNs such as `127506`, `127507`, `127508`, and `127505` were not obvious in current decoded traffic.

So the likely path is direct MasterBus access via the Mastervolt USB interface.

## Installed tools

Source/tooling:

```text
https://github.com/keesverruijt/masterbus
/home/jack/src/masterbus
```

Installed binaries:

```text
/usr/local/bin/masterbus-tui
/usr/local/bin/masterbus-signalk
/usr/local/bin/masterbus-set-field
```

These came from the `masterbus-tools` Rust crate.

## System configuration

MasterBus config:

```text
/etc/default/masterbus/config.ini
```

Current transport is forced to USB:

```ini
device_type = usb
device_name =
cache_dir = /var/lib/masterbus
```

The initial config deliberately leaves `heartbeat_master` commented out so that the tooling starts as passively as possible and uses the existing Mastervolt system master if present. If discovery is poor or there is no existing master, review before enabling:

```ini
heartbeat_master = 000001
```

Signal K sidecar env:

```text
/etc/default/masterbus-signalk/config
```

Current sidecar listen address:

```text
0.0.0.0:3009
```

Systemd unit installed but intentionally disabled until the USB interface is connected and discovery is verified:

```text
/etc/systemd/system/masterbus-signalk.service
```

Udev rule installed for Mastervolt USB vendor id `1a64`:

```text
/etc/udev/rules.d/70-mastervolt-masterbus.rules
```

This should allow the `jack` user to inspect the bus with `masterbus-tui` via hidraw/plugdev access after the device is plugged in.

## Signal K integration

The fat Signal K server on `pi5nvme:3001` now has an input provider for the MasterBus Signal K sidecar:

```text
masterbus-signalk on localhost:3009 → pi5nvme Signal K on :3001
```

So once `masterbus-signalk` is running and publishing deltas, Mastervolt values should appear in:

```text
http://pi5nvme:3001/signalk/v1/api/vessels/self
```

## After plugging in the USB interface

Check USB detection:

```bash
lsusb | grep -i '1a64\|master'
dmesg | tail -50
ls -l /dev/hidraw*
```

Run interactive discovery first:

```bash
masterbus-tui
```

If that can see devices, start the sidecar:

```bash
sudo systemctl start masterbus-signalk.service
systemctl status masterbus-signalk.service
```

Watch its TCP JSON stream directly:

```bash
nc localhost 3009
```

Then check Signal K:

```bash
curl http://pi5nvme:3001/signalk/v1/api/vessels/self
curl http://pi5nvme:3001/signalk/v1/api/sources
```

If everything is stable, enable on boot:

```bash
sudo systemctl enable masterbus-signalk.service
```

## Safety note

`masterbus-tui` and `masterbus-set-field` can edit/write MasterBus fields. Use them read-only unless deliberately making a configuration change.
