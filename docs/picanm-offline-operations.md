# picanm offline operations while pi5nvme is unavailable

Use this when `pi5nvme` is down or unreachable. Keep checks low-impact; `picanm` is the active raw NMEA 2000 acquisition edge.

## Safe status checks

```bash
check-picanm-health
check-raw-spool-space
systemctl is-active can0-nmea2000 n2k-raw-logger n2k-raw-forwarder signalk
journalctl -u n2k-raw-forwarder -n 30 --no-pager
```

Expected while `pi5nvme` is offline:

- `can0-nmea2000` active/exited successfully.
- `n2k-raw-logger` active/running.
- `n2k-raw-forwarder` active/running but retrying `pi5nvme.local:20200`.
- raw `.candump.log.tmp` grows under `/var/log/n2k/`.
- completed `.candump.log.gz` files remain under `/var/log/n2k/`.

## Do not do on picanm

Do not run decode/import/database/analyzer jobs on `picanm`.

Do not delete raw logs unless all are safely mirrored to `pi5nvme` and checksummed. While `pi5nvme` is down, assume `picanm:/var/log/n2k/` is the only current raw source of truth.

Do not stop `n2k-raw-logger` unless directed by a human.

## Disk monitoring

`check-raw-spool-space` reports disk use, completed segment count, active tmp segment count, and current live log tail.

Default thresholds:

- warning at 80% disk use or less than 2048 MiB free;
- critical at 90% disk use or less than 512 MiB free.

A timer is installed as:

```text
n2k-raw-spool-health.timer
n2k-raw-spool-health.service
```

It runs the disk/spool check periodically and logs output to the journal.

## Forwarder retry behaviour

The deployed forwarder uses mDNS `DEST_HOST=pi5nvme.local`. On the Starlink LAN, bare `pi5nvme` currently resolves to IPv6 addresses first, while the raw receiver listens on IPv4 `0.0.0.0:20200`. `pi5nvme.local` resolves via mDNS to IPv4 from `picanm` and avoids the Starlink DNS IPv6 preference.

While `pi5nvme` is offline, the raw forwarder retries every 30 seconds:

```text
n2k raw forwarder cannot connect to pi5nvme.local:20200; retrying in 30s
```

This is expected. Local raw logging is independent and continues.

## When pi5nvme returns

If this is a new outage, first check the Pi 5 incident notes before doing implementation. See:

```text
docs/2026-07-03-pi5nvme-incident-and-picanm-status.md
```

Once `pi5nvme` raw receiver is back, the forwarder should reconnect automatically via `pi5nvme.local:20200` and live files should resume under:

```text
pi5nvme:/srv/boat/raw-n2k/live/
```
