# pi5nvme incident diagnosis - 2026-07-03

## Summary

`pi5nvme` suffered an unclean crash/reboot immediately after a manually-started raw N2K import/backfill. The raw importer decoded and inserted a large batch into PostgreSQL, then the boot ended abruptly within about a minute. This matches the observed symptoms: SSH key exchange failures, other app ports disappearing, host becoming very hot, and later network/name-resolution failures.

The most likely root cause is resource/thermal/power stress from the raw importer + `analyzerjs` + PostgreSQL bulk insert on the live Pi 5. The logs do not contain a definitive OOM, thermal trip, undervoltage, or kernel panic line, probably because the failure was abrupt and the journal was unclean.

## Evidence

Diagnostics captured in:

- `docs/pi5nvme-incident-diagnostics-20260703T160633Z.log`
- `docs/pi5nvme-incident-targeted-20260703T160651Z.log`
- `docs/pi5nvme-incident-boot-minus-2-20260703T160718Z.log`
- `docs/pi5nvme-current-masterbus-import-unit-20260703T160740Z.log`

Key timeline from `journalctl --list-boots`:

```text
-2 4261dfdf... Fri 2026-07-03 09:17:01 BST -> Fri 2026-07-03 12:07:11 BST
-1 0fe74131... Fri 2026-07-03 09:17:08 BST -> Fri 2026-07-03 16:56:56 BST
 0 9f4c1b06... Fri 2026-07-03 16:57:12 BST -> current
```

Importer activity immediately before the unclean boot boundary:

```text
Jul 03 12:05:18 systemd[1]: Starting boat-raw-n2k-import.service
Jul 03 12:05:18 node[5175]: skipped ... earlier raw logs ...
Jul 03 12:06:34 node[5175]: imported /srv/boat/raw-n2k/can0-20260630T234436Z.candump.log.gz 771532
Jul 03 12:06:34 systemd[1]: Finished boat-raw-n2k-import.service
Jul 03 12:06:34 systemd[1]: boat-raw-n2k-import.service: Consumed 46.358s CPU time
```

The relevant boot then ends at about `12:07:11`. On the next boot, journald reports an unclean/corrupted journal:

```text
system.journal corrupted or uncleanly shut down, renaming and replacing
user-1000.journal corrupted or uncleanly shut down, renaming and replacing
```

This indicates the Pi did not go through a normal clean shutdown at the original failure point.

Later serial recovery actions are recorded separately:

```text
Jul 03 16:56:43 sudo systemctl stop boat-raw-n2k-import.service
Jul 03 16:56:43 sudo systemctl disable --now boat-raw-n2k-import.timer
Jul 03 16:56:55 sudo /usr/sbin/reboot
```

So the clean reboot at `16:56` was user/operator initiated after serial access, not the original incident.

## Current state after diagnosis

At diagnosis time:

- `boat-raw-n2k-import.service`: inactive
- `boat-raw-n2k-import.timer`: inactive/disabled
- `signalk-pi5nvme`: active
- `boat-n2k-raw-receiver`: active
- `postgresql`: active
- `ssh`: active
- temperature: ~46.6 C
- throttling status since current boot: `throttled=0x0`
- disk: `/` about 36% used, ~144 GiB available
- memory: ~3.0 GiB available

## Importer safeguard deployment

Update: after the initial diagnosis, the repository importer safeguards were deployed to `pi5nvme` without starting the importer.

Current deployed protections:

- `boat-raw-n2k-import.timer` disabled and inactive.
- `boat-raw-n2k-import.service` inactive.
- `/etc/boat-data-platform/allow-raw-n2k-import` absent.
- Service has `ConditionPathExists=/etc/boat-data-platform/allow-raw-n2k-import`.
- Service sets `ALLOW_RAW_N2K_IMPORT=1` only inside the gated unit.
- `scripts/import-raw-n2k.mjs` refuses direct execution unless `ALLOW_RAW_N2K_IMPORT=1` or `--yes-really-import` is explicitly supplied.
- Resource limits are deployed: `CPUQuota=50%`, `MemoryMax=768M`, `Nice=10`, idle I/O scheduling, `TasksMax=64`.
- Timer cadence is now conservative (`OnBootSec=30min`, `OnUnitActiveSec=6h`, `Persistent=false`) and remains disabled.

Guard dry-check on `pi5nvme` returned `rc=2` with:

```text
Refusing to run raw N2K import: set ALLOW_RAW_N2K_IMPORT=1 or pass --yes-really-import after confirming host resources and approval.
```

## MasterBus side issue

Current boot also shows `masterbus-signalk` repeatedly failing because no MasterBus USB Link is detected:

```text
masterbus-signalk: connect failed: connection error: no MasterBus USB Link found
```

`lsusb` did not show the MasterBus USB Link during the current check, although an earlier boot log did show:

```text
Mastervolt International B.V. MasterBus USB Link
```

This explains Signal K `ECONNREFUSED 127.0.0.1:3009` messages. It is probably unrelated to the raw importer crash, but should be checked physically or via USB after the incident is stable.

## Conclusion

Most probable root cause: manual raw N2K import/backfill created sustained CPU + disk I/O + PostgreSQL write load on the live Pi 5, causing thermal/power instability or a hard crash shortly after the import completed.

The evidence is strong by timing and symptoms, but not absolute because the crash was abrupt and no explicit OOM/thermal/undervoltage line was preserved.

## Recommended next safe actions

1. Keep `boat-raw-n2k-import.timer` disabled.
2. Do not manually start `boat-raw-n2k-import.service` until safeguards are deployed.
3. Deploy the repo's guarded/limited importer unit before any future import/backfill.
4. Keep backfill as a supervised maintenance task with resource limits, not an automatic live workload.
5. Investigate why the MasterBus USB Link is no longer detected, separately from the importer incident.
