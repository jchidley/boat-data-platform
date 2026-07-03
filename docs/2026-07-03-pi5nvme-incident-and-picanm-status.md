# 2026-07-03 pi5nvme incident and picanm status

## Incident summary

During validation of the pi5 raw-stream Signal K path, a manual start of `boat-raw-n2k-import.service` was run on `pi5nvme`.

That service runs `node scripts/import-raw-n2k.mjs`, which decompresses raw candump logs, runs canboat `analyzerjs`, and bulk inserts decoded rows into PostgreSQL. This is a high CPU / memory / disk I/O / database workload and should not have been run on the live Pi 5 without explicit approval and resource limits.

Observed sequence:

1. `pi5nvme` raw receiver and Signal K raw fanout had been working.
2. Manual importer start inserted hundreds of thousands of decoded rows.
3. `pi5nvme` became hot to the touch.
4. Signal K, raw receiver, and PostgreSQL ports became unreachable.
5. SSH first failed during pre-auth/key exchange, then the host became unreachable from the network.

Likely failure class: host overload / thermal or power-related failure triggered by the manual raw importer/backfill workload. Exact root cause is not yet proven.

## Mandatory next action when pi5nvme is reachable

Do incident investigation before any further implementation.

First protective action:

```bash
sudo systemctl stop boat-raw-n2k-import.service
sudo systemctl disable --now boat-raw-n2k-import.timer
```

Then collect low-impact diagnostics only:

```bash
uptime
vcgencmd measure_temp
vcgencmd get_throttled
free -h
df -h
last -x | head -40
systemctl --failed
journalctl -b -1 -p warning..alert --no-pager | tail -200
journalctl -b -p warning..alert --no-pager | tail -200
journalctl -u boat-raw-n2k-import -u postgresql -u ssh -u signalk-pi5nvme -u boat-n2k-raw-receiver --since "2026-07-03 12:00" --no-pager
dmesg -T | grep -Ei 'oom|killed|out of memory|under-voltage|undervoltage|thrott|thermal|nvme|ext4|reset|error|i/o'
```

Do not restart importers, run backfills, or run analyzer jobs until the incident is understood.

## Required safeguards now added in repo

The repo has been hardened so raw import/backfill is no longer an automatic live-host workload:

- `infra/pi5nvme/install-pi5nvme.sh` installs the importer units but does **not** enable `boat-raw-n2k-import.timer` by default.
- `infra/pi5nvme/systemd/boat-raw-n2k-import.service` is gated by `ConditionPathExists=/etc/boat-data-platform/allow-raw-n2k-import`.
- `scripts/import-raw-n2k.mjs` refuses to run unless `ALLOW_RAW_N2K_IMPORT=1` is set or `--yes-really-import` is passed.
- importer service has conservative resource controls:
  - `CPUQuota=50%`
  - `MemoryMax=768M`
  - `Nice=10`
  - `IOSchedulingClass=idle`
  - `IOSchedulingPriority=7`
  - `TasksMax=64`
  - `TimeoutStartSec=20min`
- importer timer cadence was relaxed and made non-persistent; it should still remain disabled unless explicitly approved.

Before any importer/backfill is run on `pi5nvme`, still require explicit approval and an import window. Prefer offline/backfill-window processing, not during live validation.

## picanm status after pi5nvme outage

Checked at `2026-07-03T12:23:34+01:00`.

`picanm` is stable and preserving raw N2K source material:

- uptime: 58 minutes
- load average: `0.57, 0.59, 0.70`
- temperature: `52.6'C`
- throttled: `0x80000` (historical throttling bit set, not necessarily currently throttled)
- memory: `415Mi total`, `134Mi available`, `60Mi swap used`
- disk: `/` and `/var/log/n2k` have about `24G` free, `13%` used
- `can0`: `UP`, `ERROR-ACTIVE`, 250 kbit/s
- CAN counters at check time: `RX packets 1192105`, `RX errors 7`, `RX dropped 73`, `bus-off 0`
- active services:
  - `can0-nmea2000`
  - `n2k-raw-logger`
  - `n2k-raw-forwarder`
  - `signalk`
- active raw log:
  - `/var/log/n2k/can0-20260703T110000Z.candump.log.tmp`
  - about `499415` lines at check time
- completed raw segment present:
  - `/var/log/n2k/can0-20260703T100000Z.candump.log.gz`

`n2k-raw-forwarder` is retrying `pi5nvme:20200`, as expected while `pi5nvme` is offline. Local raw logging is independent of forwarding and continues.

After the outage, the deployed `picanm` forwarder retry interval was reduced from 5 seconds to 30 seconds by setting `RETRY_SEC=30` in `n2k-raw-forwarder.service`. This reduces log spam and connection churn while `pi5nvme` is down. The raw logger, CAN service, and picanm Signal K were not restarted for this change.
