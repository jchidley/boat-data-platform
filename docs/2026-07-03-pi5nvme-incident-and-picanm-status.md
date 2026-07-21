# pi5nvme resource-safety gate and picanm status

## Purpose

Define operational limits after live-host storage and I/O incidents. This is a safety gate, not an architecture plan.

## 2026-07-04 NVMe/PCIe storage-path incident

The original live JSON-heavy N2K backfill generated severe PostgreSQL/WAL/index write amplification. During successive live imports the NVMe first disappeared from PCIe with `CSTS=0xffffffff`, reset failures and buffer I/O errors. A later import produced swap read errors, an aborted ext4 journal, a read-only root filesystem and a kernel panic. No classic undervoltage or throttling evidence was observed and a known-good Raspberry Pi PSU was in use, so the precise hardware cause was not proven; NVMe/HAT/ribbon/controller and PCIe power-state instability remained plausible.

The retained diagnostic mitigation is:

```text
nvme_core.default_ps_max_latency_us=0 pcie_aspm=off pcie_port_pm=off
```

These arguments disable NVMe APST, PCIe ASPM and PCIe port power management. They slightly increase idle power/heat and do not establish that the underlying storage path is fault-free. Do not remove them casually. The standard bounded health check verifies that they remain active and scans the current boot for the known NVMe reset/I/O/ext4 signatures. It also checks physical presence of the MasterBus USB Link (`1a64:0000`) separately from `masterbus-signalk` service state because the USB device also disappeared during incident recovery.

The architectural response is permanent: raw logs remain authoritative, the obsolete JSON-heavy table/importer is removed, and historical conversion runs on staging. Do not use a live boat-data import as an NVMe stress test.

## 2026-07-20 disk-pressure recurrence

The `pi5nvme` NVMe filesystem reached 100% use at 2026-07-20 07:06 UTC (08:06 BST). `boat-n2k-raw-receiver.service` then crash-looped on `ENOSPC` until cleanup freed space at 2026-07-21 00:24 UTC. The host did not reboot; Signal K, MasterBus, PostgreSQL and Grafana remained running. Independent raw acquisition continued on `picanm`, and mirroring resumed after the receiver recovered.

The apparent later SSH outage was a stale address: DHCP changed `pi5nvme` from `192.168.1.135` to `192.168.1.136`. The end-state cleanup and five-minute derived-storage guard were deployed and verified on 2026-07-21. Disk use after cleanup was 37%.

A later read-only check confirmed the three mitigation arguments active, the MasterBus USB Link present, zero matching storage-error signatures in the current boot journal, and no `n2k_decoded_messages` relation. These observations are current-state checks, not proof that the historical hardware fault is cured.

## Current rule

Do not run historical N2K conversion, backfills, broad analyzer jobs, or large PostgreSQL aggregates on live `pi5nvme`.

Historical conversion belongs on offline/staging infrastructure and must follow [`2026-07-04-backfill-strategy.md`](2026-07-04-backfill-strategy.md) and [`postgresql-storage-plan.md`](postgresql-storage-plan.md).

## Required safeguards

Any approved conversion run must have explicit limits for:

- source bytes and file count;
- process runtime;
- CPU and memory;
- temporary workspace;
- minimum free filesystem space;
- transaction scope;
- expected output tables and rows;
- cleanup after failure.

Avoid broad `count(*)`, unbounded time ranges and full-table scans on the live database. Use catalog estimates, bounded time windows and narrow indexed queries.

## pi5nvme responsibilities

Safe live services are:

- raw N2K receiver/archive and localhost fanout;
- Signal K current-state server;
- MasterBus live integration;
- PostgreSQL/TimescaleDB for bounded live writes and selected typed history;
- Grafana;
- health and disk-pressure monitoring.

The derived-storage guard must stop rebuildable writers before filesystem exhaustion without stopping raw acquisition.

## picanm responsibilities

`picanm` remains the independent acquisition edge:

- keep `can0` at 250 kbit/s;
- timestamp and write compressed raw candump segments;
- retain a local spool during backend outages;
- forward live raw data to `pi5nvme.local:20200` when reachable;
- run no Signal K, database, Node.js applications or analysis jobs.

If `pi5nvme` is unavailable, local raw collection continues. Use [`picanm-offline-operations.md`](picanm-offline-operations.md) for bounded checks.

## Connectivity caveat

Starlink/WSL hostname resolution can fail while the host is healthy. Use short timeouts and try, in order:

1. `pi5nvme.local` for Pi-to-Pi mDNS;
2. `pi5nvme-ip` for operator SSH from WSL;
3. the known IPv4 address.

Do not repeatedly retry an unresponsive host.

## Recovery priority

1. Preserve raw source material.
2. Restore raw acquisition and forwarding.
3. Restore Signal K current state.
4. Restore MasterBus live integration.
5. Restore bounded PostgreSQL writers.
6. Resume historical work only on staging after explicit review.
