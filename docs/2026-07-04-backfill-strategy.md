# Historical N2K import strategy

## Decision

Historical N2K conversion runs offline or on a staging host. Do not run broad conversion or backfill workloads on live `pi5nvme`.

## Source and destination

```text
compressed candump archive
  -> bounded direct Rust/canboat-core conversion for parity-gated PGNs
     (canboatjs/analyzer remains the fallback for other typed PGNs)
  -> PGN-shaped TSV
  -> PostgreSQL COPY staging
  -> selected typed tables with raw provenance
  -> summaries and import status
```

Raw candump files remain authoritative and must not be deleted after import.

## Required limits

Every run must set and record:

- input files and total source bytes;
- maximum process runtime;
- CPU and memory limits;
- temporary workspace limit;
- minimum free disk before start;
- PostgreSQL transaction scope;
- expected typed tables;
- research mode, normally `none`.

The wrapper requires `--allow-full-file` for complete files and supports input-size and runtime limits. That flag is technical permission, not operational approval for live-host backfill.

## Validation sequence

1. Validate converter output with synthetic fixtures.
2. Validate one small real sample.
3. Compare source message counts, typed row counts and null rates.
4. Prove duplicate/idempotent handling.
5. Prove failure cleanup and import-status reporting.
6. Compare typed-only storage with envelope-plus-typed storage.
7. Approve a bounded staging batch.
8. Verify PostgreSQL size and query usefulness before expanding scope.

## Acceptance criteria

- imported rows trace to `raw_file_id` and message position;
- normal imports produce no research-field rows;
- repeated import does not duplicate facts;
- failed files remain retryable;
- source checksums and first/last timestamps are recorded;
- typed values match decoder output and expected units;
- resource limits terminate overruns cleanly;
- live Signal K, MasterBus and raw acquisition are unaffected;
- only PGNs with a concrete historical use are retained.

## 2026-07-21 bounded staging results

The first seven-PGN Rust batch was run only against settled mirrored picanm data on disposable staging. It used the first 10,000 lines of `can0-20260713T070000Z.candump.log.gz`, decoder revision `d0f7f24a41b1274f63b71f08703539554523858f`, schema `7.1.0`, research mode `none`, 20 MB input, 10,000-line, 120-second, 512 MiB memory-planning, 1 GB workspace and 1 GB free-disk limits. It produced 5,752 frame summaries and 2,810 typed rows, imported twice idempotently, and rebuilt to identical per-table counts and normalized hashes after `TRUNCATE ... CASCADE` cleanup. No live host conversion or import was run.

The native MasterBus settled-file gate used equivalent explicit limits and additionally recorded source event times, converter/skips, sparse-merge counts, workspace, free disk and peak RSS. The complete evidence is in `2026-07-05-copy-merge-validation.md`. These validation batches do not constitute approval for any live import.
