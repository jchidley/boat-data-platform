# PostgreSQL end-state migration

## Status

Applied and verified on `pi5nvme` on 2026-07-21. The obsolete-object snapshot is stored at `/home/jack/boat-migration-backup-20260721T015537Z`. The later direct-provenance schema snapshot is stored at `/home/jack/boat-schema-backup-20260721T022037Z`. No import or backfill was run.

## Goal

Make the deployed system match the two-path architecture:

```text
source data -> Signal K current state
source data -> typed PostgreSQL history
```

PostgreSQL must contain only typed history, provenance, health and bounded import metadata.

## Objects to remove

These deployed objects are not part of the end state:

```text
signal_k_measurements
raw_n2k_log_files
masterbus_snapshots
data_quality_observations
boat_data_summaries
v_signalk_path_catalog
v_latest_boat_state
v_recent_data_quality
n2k_device_pgn_summary_v2
```

Reasons:

- `signal_k_measurements` belongs to an extra Signal K-to-PostgreSQL path;
- `raw_n2k_log_files` duplicates `n2k_raw_files_v2`;
- MasterBus snapshots are preserved as source files under `/srv/boat/masterbus/`;
- health history is owned by `health_observations` and its views;
- summaries should be reproducible views/queries over typed history, not manually persisted documents;
- `n2k_device_pgn_summary_v2` is unused and can be derived from typed/source-attribution tables.

The repository cleanup migration is:

```text
infra/pi5nvme/sql/010_end_state_cleanup.sql
```

The installer also stops, disables and removes the deployed `boat-signalk-collector.service`.

## Keep

```text
n2k_raw_files_v2
n2k_import_runs_v2
n2k_pgn_definitions_v2
n2k_devices_v2
n2k_source_observations_v2
selected typed n2k_*_v2 tables
n2k file/source/device summaries
MasterBus typed tables and log-file inventory
health_observations and health views
unlogged staging tables used by bounded COPY imports
```

The bounded staging comparison selected typed-only direct provenance. Migration `004a_reset_n2k_typed_provenance.sql` removes the experimental persistent frame table before `005_relational_n2k_v2.sql` creates typed tables carrying `raw_file_id` and `message_index` directly.

`n2k_research_fields_v2` remains available only for explicit bounded research. Normal imports must produce zero research rows.

## Preconditions

Before applying the migration on `pi5nvme`:

1. Confirm raw N2K source files are present and growing.
2. Confirm MasterBus replay logs and configuration/schema snapshots are present.
3. Snapshot PostgreSQL object names and sizes using catalog queries only.
4. Check whether any Grafana dashboard or script references an object in the removal list.
5. Export any uniquely valuable derived rows; normally none should be authoritative.
6. Confirm at least 20% filesystem free space.
7. Do not run an import or backfill during this migration.

## Apply

Use the repo installer or apply only the cleanup SQL and service removal:

```bash
sudo systemctl disable --now boat-signalk-collector.service || true
sudo rm -f /etc/systemd/system/boat-signalk-collector.service
sudo systemctl daemon-reload
sudo -u postgres psql -v ON_ERROR_STOP=1 -d boatdata \
  -f infra/pi5nvme/sql/010_end_state_cleanup.sql
```

## Verify

1. Signal K remains active and current N2K/MasterBus paths are fresh.
2. Raw N2K acquisition and archive files continue growing.
3. PostgreSQL, Grafana and health collection remain active.
4. Removed objects are absent from `pg_class`.
5. `n2k_raw_files_v2`, typed N2K tables, MasterBus typed tables and `health_observations` remain present.
6. Standard tests and bounded health checks pass.
7. Disk usage is healthy.

## Rollback

There is no data rollback requirement because removed objects are derived and outside the end-state ownership model. If an application dependency is discovered, fix it to use Signal K current state or typed PostgreSQL history. Do not recreate the removed general telemetry path.

## Completion criteria

- exactly two processing paths remain;
- no service writes general Signal K telemetry to PostgreSQL;
- no duplicate raw-file inventory table remains;
- source snapshots remain on disk rather than in duplicate PostgreSQL storage;
- health and typed history consumers pass verification;
- the migration result is recorded in the implementation brief.
