# 2026-07-03 pi5nvme incident and picanm status

## Incident summary

During validation of the pi5 raw-stream Signal K path, a manual start of `boat-raw-n2k-import.service` was run on `pi5nvme`.

That service runs `node scripts/import-raw-n2k.mjs`, which decompresses raw candump logs, runs canboat `analyzerjs`, and bulk inserts decoded rows into PostgreSQL. This is a high CPU / memory / disk I/O / database workload and should not have been run on the live Pi 5 without explicit approval and resource limits.

Observed sequence after serial recovery and journal inspection:

1. `pi5nvme` raw receiver and Signal K raw fanout had been working.
2. `boat-raw-n2k-import.service` had also run automatically at `11:49:44` and imported one file successfully: `can0-20260630T103825Z.candump.log.gz`, `774194` decoded rows, `43.981s` CPU.
3. Manual importer start at `12:05:18` imported `can0-20260630T234436Z.candump.log.gz`, `771532` decoded rows, and completed successfully at `12:06:34`, consuming `46.358s` CPU.
4. Follow-up Postgres row-count checks then ran. The last recorded entry in boot `4261dfdf7bc24cb5a477fbe68d044ea2` is a `sudo -u postgres psql` count/max query starting at `12:07:11`; there is no matching close entry.
5. Boot `4261dfdf7bc24cb5a477fbe68d044ea2` ends abruptly after that with no clean shutdown markers, no OOM log, no thermal log, and no under-voltage log. This is consistent with a hard hang/reset/power/thermal event where the kernel had no chance to persist a final cause.
6. The next boot, `0fe7413170ad40fc85878d51c68e9a7a`, started with a bad clock (`09:17`) and only stepped to correct time at `16:52:39`. This made the outage timeline confusing.
7. At serial recovery time, `masterbus-signalk.service` was restart-looping because no MasterBus USB Link was visible. Signal K logged repeated `ECONNREFUSED 127.0.0.1:3009`.
8. A manual serial `sudo reboot` at `16:56:55` caused the clean shutdown/reboot into current boot `9f4c1b0625d44785b3c1d8af584dfaee`.

Current best diagnosis: the live host likely hard-hung or reset shortly after the import/backfill plus repeated Postgres count/max checks. The importer completed, but it substantially increased database size and cache/I/O pressure; the final recorded operation was a database count/max query, not the importer process itself. There is no evidence of a Linux OOM kill or clean thermal shutdown in the journal.

Current state after reboot: `pi5nvme` is reachable by SSH, temperature is normal (`47.2'C` at check), throttling state is `0x0`, memory/disk are healthy, raw receiver and Signal K are active, and importer service/timer are inactive/disabled. The repo safeguards below are not yet deployed to `/etc/systemd/system` on `pi5nvme`.

The MasterBus USB Link is not currently visible in `lsusb`; only USB root hubs were listed. `masterbus-signalk.service` was restart-looping every 5 seconds with `no MasterBus USB Link found`, so it was stopped for the current boot only. It remains enabled for future boots unless changed separately.

## Mandatory next actions on pi5nvme

Completed after serial access:

```bash
sudo systemctl stop boat-raw-n2k-import.service
sudo systemctl disable --now boat-raw-n2k-import.timer
```

Importer service/timer are currently inactive/disabled.

Before any further implementation or import/backfill work:

1. Deploy the repo's importer safety hardening to `pi5nvme`:
   - guarded importer service with `ConditionPathExists=/etc/boat-data-platform/allow-raw-n2k-import`;
   - disabled/non-persistent timer;
   - script-level `ALLOW_RAW_N2K_IMPORT=1` approval guard;
   - systemd CPU/memory/IO limits.
2. Stop or disable `masterbus-signalk.service` until the MasterBus USB Link is visible again, or adjust its restart policy to avoid a 5-second failure loop.
3. Do not restart importers, run backfills, run analyzer jobs, or run broad database aggregate checks on the live host until resource limits are deployed and an explicit import window is approved.

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
