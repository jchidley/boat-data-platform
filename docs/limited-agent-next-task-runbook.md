# Limited-agent execution runbook

## Purpose

This runbook gives a less capable agent a small, safe sequence of tasks that advances the current plan. It is an execution guide, not the architecture source of truth.

Canonical sources, in precedence order:

1. `AGENTS.md`
2. `docs/llm-implementation-brief.md`
3. `docs/plan.md`
4. the subject-specific plan named by each task
5. this runbook

If these disagree, stop and report the conflict. Do not choose the more permissive instruction.

## Validated starting point

Validated against repository commit:

```text
cf446dea1ad5fccd3553f76ad267f09fee4da66c
```

The current commit may be this commit or a descendant. Never reset to this hash.

The plans are directionally sound and agree on the next order:

1. improve Grafana empty/open-runtime UX and historical range;
2. automate live schema/role and Grafana acceptance checks;
3. finish port-only and both-running physical commissioning;
4. consider another MasterBus batch only after staging proves its value;
5. defer logbook and live N2K import until their gates are met.

Two details require care:

- `docs/postgresql-storage-plan.md` still describes the fixed 24-hour electrical view as the deployed implementation. That is current-state evidence, not the desired end state. The current plan explicitly requires removing that hidden 24-hour restriction.
- “Completed runtime has no data” is correct for the currently open interval, but poor UX. The dashboard should display zero completed hours and show the open interval separately. It must not close or count the open interval.

Current deployed evidence:

- first bounded MasterBus batch: 2,937 alternator, 2,124 battery, 1,482 inverter/charger and 2,376 solar rows;
- engine history: one open starboard interval and no port transition;
- Grafana dashboard UID: `boat-typed-history`;
- Grafana datasource UID: `boat-timescaledb`;
- Grafana 13 needs `database: boatdata` both at datasource top level and under `jsonData`;
- both-off and starboard-only are physically verified;
- port-only and both-running are not verified;
- no typed N2K batch has been imported live.

Do not assume live state still matches this list. Check it before live work.

---

## Absolute boundaries

### Never do these

- Never transmit on NMEA 2000 or write to MasterBus.
- Never control engines, charging, switching or autopilot functions.
- Never start or stop an engine. Only the human operator may do so.
- Never infer an engine stop from missing data or the end of a file.
- Never count an open interval as completed runtime.
- Never run broad conversion, backfill, analyzer or aggregate jobs on `pi5nvme`.
- Never run `infra/pi5nvme/install-pi5nvme.sh` for a targeted upgrade.
- Never import any MasterBus or N2K file without explicit approval in the current conversation.
- Never alter a live database, Grafana configuration or service without explicit approval in the current conversation.
- Never delete source logs under `/srv/boat/raw-n2k/`, `/srv/boat/masterbus/` or `/var/log/n2k/`.
- Never print `/etc/boat-data-platform/db.env`, Grafana secrets or database passwords.
- Never change the 13.25 V threshold or debounce values merely to make an observation pass.
- Never claim engine runtime is logbook-ready until all four physical combinations agree with derived state.

### Operating rules

- Use `pi5nvme-ip` and `picanm-ip` with `ssh -o BatchMode=yes -o ConnectTimeout=8`.
- Do not use bare hostnames from WSL.
- Keep live SQL narrow, indexed and bounded.
- Keep builds and project work in Linux, not `/mnt/c/`.
- If a command fails unexpectedly, stop. Explain the failure and state a revised plan before doing anything else.
- If another agent has made the tree dirty, stop. Do not stash, discard or overwrite its work.

### Approval classes

| Work | Approval needed? |
|---|---|
| Read repository, run local tests | No |
| Edit repository files and tests | No, when implementation was requested |
| Commit/push | Only when requested or normally expected for the task |
| Read-only live health checks | No |
| Apply SQL to `pi5nvme` | Yes, explicit and current |
| Restart Grafana or deploy dashboard files | Yes, explicit and current |
| Import one settled source file | Yes, naming that batch |
| Physical engine capture | Human physically present and explicitly confirms state |

An approval for one task does not approve later tasks.

---

## Checkpoint 0 — establish the baseline

Run locally:

```bash
git status --short --branch
git rev-parse HEAD
git rev-parse origin/main
npm test
npm run test:engine-history:integration
git diff --check
```

Expected:

- clean tree;
- local `main` equals `origin/main`;
- default suite has no failures and one intentional integration-test skip;
- explicit integration result contains 7 transitions, 4 intervals, 2 summaries and 230 completed seconds.

Run bounded live checks:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 pi5nvme-ip \
  'df -P / | tail -1; systemctl is-active postgresql signalk-pi5nvme masterbus-signalk boat-n2k-raw-receiver grafana-server'

ssh -o BatchMode=yes -o ConnectTimeout=8 picanm-ip \
  'df -P / | tail -1; systemctl is-active can0-nmea2000 n2k-raw-logger n2k-raw-forwarder; ip -brief link show can0'
```

Expected: every service is `active`, `can0` is `UP`, and both filesystems are below 75% used.

Check only known bounded database inventories:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 pi5nvme-ip \
  "sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d boatdata -Atc \"
select 'alternator=' || count(*) from masterbus_alternator_samples_v1;
select 'battery=' || count(*) from masterbus_battery_samples_v1;
select 'inverter_charger=' || count(*) from masterbus_inverter_charger_samples_v1;
select 'solar=' || count(*) from masterbus_solar_samples_v1;
select 'staging=' || (
  (select count(*) from masterbus_alternator_stage_v1) +
  (select count(*) from masterbus_battery_stage_v1) +
  (select count(*) from masterbus_inverter_charger_stage_v1) +
  (select count(*) from masterbus_solar_stage_v1));
select 'open_intervals=' || count(*) from masterbus_engine_runtime_intervals_v1 where end_reason='open';
\""
```

Expected baseline:

```text
alternator=2937
battery=2124
inverter_charger=1482
solar=2376
staging=0
open_intervals=1
```

### STOP conditions

Stop without repairing if any service is inactive, disk is at least 75%, staging is nonzero, counts differ, tests fail, or the repository is unexpectedly dirty. Report exact observed values.

---

# Task 1 — implement Grafana history UX in the repository

**Scope:** repository only. Do not deploy.

Files expected to change:

```text
infra/pi5nvme/grafana/dashboards/boat-history.json
infra/pi5nvme/sql/011_masterbus_engine_history_v1.sql
infra/pi5nvme/sql/012_masterbus_history_consumer_upgrade.sql   # new
test/grafana-files.test.mjs
test/sql-merge-files.test.mjs
```

The exact test-file set may differ slightly, but production changes must remain limited to the dashboard and SQL view upgrade.

## 1.1 Change the dashboard default range

Change:

```json
"time": {"from": "now-24h", "to": "now"}
```

to:

```json
"time": {"from": "now-30d", "to": "now"}
```

Do not remove `$__timeFilter(...)` from any query. The longer default is safe only because each query remains time-filtered and has a numeric `LIMIT`.

## 1.2 Make completed runtime an explicit zero

Rename the panel to:

```text
Completed runtime — closed intervals only
```

The query must always return both engines, even when no closed intervals exist. A suitable pattern is:

```sql
WITH engines(engine_key) AS (
  VALUES ('port'::text), ('starboard'::text)
), closed AS (
  SELECT engine_key, sum(duration_seconds) / 3600.0 AS runtime_hours
  FROM masterbus_engine_runtime_intervals_v1
  WHERE $__timeFilter(started_at)
    AND end_reason <> 'open'
  GROUP BY engine_key
)
SELECT e.engine_key,
       round(coalesce(c.runtime_hours, 0)::numeric, 2) AS runtime_hours
FROM engines e
LEFT JOIN closed c USING (engine_key)
ORDER BY e.engine_key
LIMIT 2
```

This returns `0.00` for engines with no closed interval. It does not include an open interval.

Bad example — never use:

```sql
sum(coalesce(duration_seconds, extract(epoch from now() - started_at)))
```

That incorrectly counts a still-open interval as completed runtime.

## 1.3 Add an open-interval panel

Add a bounded table titled:

```text
Open engine intervals
```

Use fields such as:

```sql
SELECT engine_key, started_at, start_evidence_time,
       start_raw_log_file_id, start_raw_line_number, source
FROM masterbus_engine_runtime_intervals_v1
WHERE end_reason = 'open'
  AND $__timeFilter(started_at)
ORDER BY started_at DESC
LIMIT 20
```

Success on current data means the starboard open interval is visible separately. Do not display a fabricated end time or completed duration.

## 1.4 Remove the hidden 24-hour SQL restriction

In `011_masterbus_engine_history_v1.sql`, remove both predicates:

```sql
WHERE time >= now() - interval '24 hours'
```

from `v_masterbus_recent_electrical_v1`. Keep the view name for compatibility. Grafana's bounded `$__timeFilter(time)` owns the requested range.

Because editing `011` fixes fresh installations but does not constitute an explicit existing-install upgrade, add:

```text
infra/pi5nvme/sql/012_masterbus_history_consumer_upgrade.sql
```

It should contain only an idempotent `CREATE OR REPLACE VIEW public.v_masterbus_recent_electrical_v1 AS ...` without the 24-hour predicates, followed by conditional `GRANT SELECT` blocks for existing reader roles. Do not rebuild engine history and do not modify typed rows.

Good boundary: `012` changes one view and its grants.

Bad boundary: copying all of migration `011`, truncating derived tables, changing functions, or invoking `rebuild_masterbus_engine_history_v1()`.

## 1.5 Strengthen tests

Tests must prove:

- default range is `now-30d`;
- completed-runtime title says closed intervals only;
- runtime SQL has both `port` and `starboard`, `coalesce`, and excludes `open`;
- an open-interval panel exists and filters `end_reason = 'open'`;
- every target retains a time macro and numeric `LIMIT`;
- neither `011` nor `012` contains the fixed `now() - interval '24 hours'` electrical predicate;
- `012` is limited to replacing the view and conditional grants.

Do not write a weak test that merely searches the combined dashboard JSON for the word `open`. Inspect the panel by title and assert against that panel's own SQL.

## 1.6 Verify locally

```bash
npm test
npm run test:engine-history:integration
node -e "JSON.parse(require('fs').readFileSync('infra/pi5nvme/grafana/dashboards/boat-history.json'))"
git diff --check
git status --short
git diff -- infra/pi5nvme/grafana/dashboards/boat-history.json infra/pi5nvme/sql/011_masterbus_engine_history_v1.sql infra/pi5nvme/sql/012_masterbus_history_consumer_upgrade.sql test
```

### Checkpoint 1 success criteria

- all tests pass;
- dashboard JSON parses;
- only intended files changed;
- no importer, service, engine-state function or threshold changed;
- SQL upgrade is idempotent and does not touch data;
- closed runtime returns both engines as zero when no closed interval exists;
- open interval remains open and separately visible.

Commit this repository work before seeking deployment approval. Then stop and report:

```text
Checkpoint 1: PASS
Live changes: none
Approval required next: apply SQL 012 and deploy the revised dashboard to pi5nvme
```

---

# Task 2 — preflight and deploy Task 1

**Scope:** live change. **Explicit approval required.**

If approval is absent, perform only the read-only preflight and stop.

## 2.1 Read-only preflight

Repeat Checkpoint 0. Then verify current objects and grants:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 pi5nvme-ip \
  "sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d boatdata -Atc \"
select to_regclass('public.v_masterbus_recent_electrical_v1');
select has_table_privilege('grafana_reader','public.v_masterbus_recent_electrical_v1','SELECT');
select count(*) from masterbus_engine_runtime_intervals_v1 where end_reason='open';
\""
```

Expected: relation name, `t`, and `1` open interval.

Verify safe datasource fields without showing secrets:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 pi5nvme-ip \
  'sudo grep -E "^( *uid:| *type:| *database:)" /etc/grafana/provisioning/datasources/boatdata-postgres.yaml; systemctl is-active grafana-server'
```

Required fields include UID `boat-timescaledb`, type `postgres`, top-level database `boatdata`, and `jsonData.database: boatdata`. Never print the full file.

## 2.2 Back up the narrow scope

```bash
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
ssh -o BatchMode=yes -o ConnectTimeout=8 pi5nvme-ip "set -euo pipefail
BACKUP=/home/jack/grafana-history-ux-backup-$STAMP
mkdir -p \"\$BACKUP\"
sudo -u postgres pg_dump -X -d boatdata --schema-only \
  --table=public.v_masterbus_recent_electrical_v1 > \"\$BACKUP/view.sql\"
sudo cp -a /etc/grafana/dashboards/boat-data-platform/boat-history.json \"\$BACKUP/boat-history.json\"
printf 'backup=%s\n' \"\$BACKUP\"
"
```

Record the printed backup path.

## 2.3 Stage, validate and apply only SQL 012

```bash
scp -q -o BatchMode=yes -o ConnectTimeout=8 \
  infra/pi5nvme/sql/012_masterbus_history_consumer_upgrade.sql \
  infra/pi5nvme/grafana/dashboards/boat-history.json \
  pi5nvme-ip:/tmp/
```

First validate SQL transactionally and roll it back:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 pi5nvme-ip \
  "sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d boatdata <<'SQL'
BEGIN;
\i /tmp/012_masterbus_history_consumer_upgrade.sql
SELECT count(*) FROM public.v_masterbus_recent_electrical_v1
WHERE time >= '2026-07-21 07:00:00+00' AND time < '2026-07-21 09:00:00+00';
ROLLBACK;
SQL"
```

A count is expected; SQL errors are not. Then apply once:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 pi5nvme-ip \
  "sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d boatdata -f /tmp/012_masterbus_history_consumer_upgrade.sql"
```

## 2.4 Deploy only the dashboard

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 pi5nvme-ip 'set -euo pipefail
sudo install -m 0644 /tmp/boat-history.json /etc/grafana/dashboards/boat-data-platform/boat-history.json
rm -f /tmp/boat-history.json /tmp/012_masterbus_history_consumer_upgrade.sql
sudo systemctl restart grafana-server
systemctl is-active grafana-server
'
```

Do not restart PostgreSQL, Signal K, MasterBus or raw acquisition.

## 2.5 Verify through every consumer layer

1. Repository and deployed dashboard checksums match.
2. `curl -fsS --max-time 8 http://127.0.0.1:3000/api/health` reports success.
3. Grafana's query API returns bounded data for the known imported interval.
4. A real browser renders:
   - electrical history older than 24 hours when included by the dashboard range;
   - `0 h` completed runtime for both engines;
   - the separate open starboard interval;
   - no warning triangles.
5. The health helper passes and all acquisition services remain active.

Use browser automation if available; otherwise use a screenshot and panel-query inspection. Direct SQL plus datasource health is not sufficient.

Known interval for acceptance:

```text
2026-07-21T07:26:31Z through 2026-07-21T07:59:59Z
```

Never put credentials in a URL, command transcript, commit or report.

## 2.6 Rollback rule

If SQL fails before deployment, the transaction must roll back; stop.

If Grafana fails after dashboard deployment, restore only the dashboard from the recorded backup and restart Grafana. Do not run the full installer.

If the new view causes an unexpected consumer failure, restore `view.sql` with `psql -X -v ON_ERROR_STOP=1 -d boatdata -f <backup>/view.sql`, restore the dashboard, restart Grafana, and report. Do not alter typed rows.

### Checkpoint 2 success criteria

- SQL 012 applied without changing typed or engine-history row counts;
- dashboard checksum matches repository;
- both completed-runtime values visibly show zero;
- open starboard interval is visibly separate;
- known electrical history remains queryable beyond the former fixed 24-hour window;
- no panel warnings;
- all acquisition services active, disk below 75%, health helper passes;
- backup path and verification evidence recorded in canonical docs.

Stop after this checkpoint. Deployment approval does not approve another data import.

---

# Task 3 — automate a read-only deployed-parity report

**Scope:** repository work first. Do not make live repairs.

Create one narrowly scoped script, for example:

```text
scripts/check-live-parity.sh
```

The script should accept `--host` (default `pi5nvme-ip`) and perform only:

- short-timeout SSH connectivity;
- disk and required-service checks;
- relation/column existence checks for MasterBus typed, staging and engine tables;
- `has_table_privilege` and `has_function_privilege` checks for `boat_ingest` and `grafana_reader`;
- deployed view-definition check proving no fixed 24-hour predicate;
- Grafana safe-field checks for UID and both database entries;
- dashboard checksum comparison when given `--dashboard-file`.

It must not:

- source or print secret environment files;
- apply SQL;
- grant privileges;
- restart services;
- import data;
- use unbounded table scans.

Output one stable line per assertion:

```text
PASS service.grafana active
PASS grant.boat_ingest.stage_delete true
FAIL view.electrical.fixed_24h absent expected=absent actual=present
```

Exit `0` only when all checks pass; otherwise exit nonzero.

Add tests using mocked `ssh` output. At minimum test:

- complete success;
- missing staging `DELETE` grant;
- stale fixed-24-hour view;
- absent `jsonData.database` despite healthy Grafana;
- failed SSH exits nonzero without retrying indefinitely;
- output never contains a supplied fake password.

### Checkpoint 3 success criteria

- local tests pass;
- script is read-only by inspection and by test;
- all remote commands have timeouts;
- failures identify the exact drift;
- no automatic repair exists;
- one read-only run against `pi5nvme` passes or stops with a precise drift report.

Do not combine rollback-only ingest testing into this first script. That is a separate write-capable preflight and requires its own review and transaction guarantees.

---

# Task 4 — add rollback-only ingest-role preflight

**Scope:** implement and validate on disposable PostgreSQL first. Live execution requires explicit approval because it performs writes inside a transaction, even though it rolls back.

Extend the existing MasterBus importer or add a dedicated command that:

1. connects as the actual ingest role;
2. begins a transaction;
3. inserts a uniquely named synthetic inventory row;
4. exercises `DELETE` and one synthetic insert in each staging table;
5. invokes `masterbus_merge_staged_log_v1` with only synthetic data;
6. raises an error on any missing privilege or unexpected result;
7. always rolls back;
8. reconnects read-only and proves the synthetic marker and staging rows do not exist.

Required marker example:

```text
preflight-only-<UTC timestamp>-<random suffix>
```

Never use a real source checksum/path as the marker.

Required safety features:

- `ON_ERROR_STOP` or equivalent;
- transaction timeout and statement timeout;
- cleanup verification in a separate connection;
- refusal to run without `--rollback-only`;
- refusal when disk is at least 75%;
- no engine-history rebuild;
- no active source file access;
- no secret output.

Test first against disposable PostgreSQL. Include a test that revokes one required privilege and proves the preflight fails, rolls back, and leaves zero rows.

### Checkpoint 4 success criteria

- disposable success path leaves zero rows;
- missing-privilege mutation is detected;
- every error path rolls back;
- live mode cannot run accidentally;
- no live execution occurred unless separately approved;
- if approved live, post-check proves inventory and all staging counts unchanged.

---

# Task 5 — capture remaining physical engine combinations

**Scope:** observation only. The human must be physically present and operate the engines.

Remaining observations:

| Label | Human-confirmed physical state | Expected Signal K output |
|---|---|---|
| `port-only` | port on, starboard off | port `started`, starboard `stopped` |
| `both-engines` | both on | both `started` |

Before capture, ask for explicit confirmation of the current physical state. Do not ask the human to start an engine merely for the agent's convenience.

Capture 60 seconds:

```bash
HOST=$(ssh -G pi5nvme-ip | awk '$1=="hostname" {print $2; exit}')
node scripts/capture-alternator-observation.mjs \
  --label <port-only-or-both-engines> \
  --duration-sec 60 \
  --interval-sec 2 \
  --url "http://$HOST:3001"
```

Edit only the generated `manifest.json` note to record the human-confirmed state and conditions. Never alter `samples.jsonl`.

Verify:

- approximately 30 samples were attempted;
- both sense-voltage paths are present;
- both field-current paths are present;
- both `propulsion.*.state` paths are present;
- running engine sense voltage is above 13.25 V after debounce;
- stopped engine sense voltage is at or below 13.25 V;
- derived states match physical state;
- timestamps remain fresh.

Example state count:

```bash
rg -o '"path":"propulsion\.(port|starboard)\.state","value":"[^"]+"' <DIR>/samples.jsonl | sort | uniq -c
```

STOP if data is stale/missing, physical state changes, voltage disagrees with derived state, or MasterBus/USB disappears. Do not tune thresholds during commissioning.

### Checkpoint 5 success criteria

- evidence directory has `manifest.json`, `samples.jsonl`, `summary.json` and `summary.tsv`;
- immutable samples agree with the human-confirmed state;
- canonical engine plan and status docs are updated;
- tests pass;
- evidence and docs are committed;
- only after both remaining combinations pass may docs say all four are commissioned.

This checkpoint does not approve logbook integration.

---

# Task 6 — stage-select a possible interval-closing MasterBus file

**Scope:** staging analysis only. Do not import live.

This task is optional and follows Tasks 1–2 so there is a demonstrated consumer.

Goal: identify at most one settled file after the imported `070000Z` file that contains genuine starboard stop or data-gap evidence.

Rules:

- never read the currently active hourly file;
- copy one settled candidate to staging;
- record path, checksum, bytes, physical event lines and first/last timestamps;
- use the existing bounded converter limits;
- import only into disposable PostgreSQL;
- rebuild engine history there;
- predict exact typed row deltas, transitions and interval closure;
- preserve the distinction between physical source lines and coalesced typed rows;
- do not claim file end is a stop.

A useful result looks like:

```text
Candidate: masterbus-native-<timestamp>.jsonl
Settled proof: later hourly segment exists
Expected new stop evidence: starboard at <time>, raw line <n>
Expected interval end_reason: stopped (or data_gap)
Expected completed runtime: <seconds>
Live action: none
Approval needed: import this exact checksum as one bounded batch
```

A valid “no useful candidate found” result is success. Do not broaden the search automatically.

### Checkpoint 6 success criteria

- at most one candidate analyzed;
- all limits and provenance recorded;
- disposable database cleaned up;
- predicted result is deterministic and evidence-backed;
- no live database writes;
- a later live import remains explicitly approval-gated.

---

# Task 7 — define, but do not import, the first N2K consumer

**Scope:** planning only.

Use only the parity-gated PGNs:

```text
127245 rudder
127250 heading
128259 water speed
128267 water depth
129025 position rapid update
129026 COG/SOG rapid update
130306 wind
```

Choose one named user question, not a generic “all navigation” dashboard. Good example:

```text
Question: Where did the boat travel, and what were COG/SOG over that track?
PGNs: 129025 and 129026 only
```

Bad example:

```text
Import every available PGN now in case it is useful later.
```

The proposal must state bounded time filters, numeric row limits, provenance fields, null handling, expected user-visible panels, staging evidence required, and the exact later approval needed for one live import.

Do not add GNSS quality, route, AIS or environmental PGNs without a named consumer and a new representative/parity gate.

### Checkpoint 7 success criteria

- one user-visible question;
- only required approved PGNs;
- bounded queries;
- explicit provenance and null behavior;
- no live import or service change;
- exact future approval gate stated.

---

## Required final report after every task

```text
Task completed: <number and name>
Repository changes: <paths or none>
Live changes: <exact SQL/files/services or none>
Tests: <commands and results>
Live checks: <services, disk, bounded database result>
Safety: no N2K transmit, no MasterBus write, no device control
Checkpoint result: PASS or STOPPED
Remaining approval gate: <exact approval or none>
Commit: <hash or none>
```

Never say “complete” when a checkpoint stopped, browser acceptance was omitted, a physical observation is missing, or a live action lacked explicit approval.
