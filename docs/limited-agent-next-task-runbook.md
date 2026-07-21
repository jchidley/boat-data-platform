# Limited-agent next-task runbook

Purpose: give a less capable coding agent a safe, exact sequence of useful tasks for the boat data platform.

This is an execution checklist, not the architecture source of truth. Before work, read these files in order:

1. `AGENTS.md`
2. `docs/llm-implementation-brief.md`
3. `docs/plan.md`
4. `docs/postgresql-storage-plan.md`
5. `docs/2026-07-03-pi5nvme-incident-and-picanm-status.md`

If this runbook conflicts with those files, stop and follow the canonical files.

## Current starting point

Baseline completed-plan commit before this runbook was added:

```text
ccf532ea25d983cd8ede0616fa6c9e693212feb6
```

The current commit should be this commit or a descendant. Do not reset back to this hash.

Current state:

- `picanm` acquires and forwards raw NMEA 2000 data.
- `pi5nvme` runs Signal K, MasterBus, PostgreSQL, Grafana and raw archival.
- The first bounded native MasterBus batch is imported in PostgreSQL.
- Expected typed counts are:
  - alternator: `2937`
  - battery: `2124`
  - inverter/charger: `1482`
  - solar: `2376`
- Engine-history migration `011_masterbus_engine_history_v1.sql` is deployed.
- Engine history has one open starboard interval and no port transition.
- Both-off and starboard-only physical engine combinations are verified.
- Port-only and both-running still require safe physical commissioning.
- Grafana dashboard UID `boat-typed-history` is deployed with stable datasource UID `boat-timescaledb`.
- No live N2K typed batch has been imported.

Do not assume this state remains true. Verify it at Checkpoint 0.

Tasks 1–4 were completed on 2026-07-21. A new agent should begin with Task 5 unless explicitly asked to audit or redeploy Grafana.

## Absolute boundaries

### Never do these

- Never transmit on NMEA 2000.
- Never write to MasterBus devices.
- Never control engines, charging, switching or autopilot functions.
- Never start an engine. Only the human operator may operate engines.
- Never run broad conversion, backfill, analyzer or aggregate jobs on `pi5nvme`.
- Never run `infra/pi5nvme/install-pi5nvme.sh` merely to deploy Grafana. It installs packages, applies every SQL migration and changes services.
- Never import another MasterBus file without explicit approval in the current conversation.
- Never run a live N2K import without explicit approval in the current conversation.
- Never deploy Grafana or change a live service without explicit approval in the current conversation.
- Never delete source files under `/srv/boat/raw-n2k/`, `/srv/boat/masterbus/` or `picanm:/var/log/n2k/`.
- Never expose `/etc/boat-data-platform/db.env` or print database passwords.
- Never treat missing data as an engine stop.
- Never claim engine runtime is trusted for logbook use until port-only and both-running are physically verified.

### Host rules

- Use `pi5nvme-ip` and `picanm-ip` SSH aliases with `ConnectTimeout=8`.
- Do not rely on bare hostnames. Starlink/WSL name resolution is unreliable.
- Use read-only, bounded SQL for checks.
- Keep commands against `/mnt/c/` out of this project.
- If a command fails unexpectedly, stop, state a revised plan, and investigate. Do not repeatedly retry.

## Checkpoint 0 — establish a clean baseline

Run locally:

```bash
git status --short --branch
git rev-parse HEAD
git rev-parse origin/main
npm test
```

Expected:

- working tree is clean;
- local `main` matches `origin/main`;
- Node tests have no failures; the disposable PostgreSQL integration test may be intentionally skipped by the default suite.

Run the explicit integration test:

```bash
npm run test:engine-history:integration
```

Expected fixture result:

```text
transitions=7
intervals=4
summaries=2
completedRuntimeSeconds=230
```

Read-only live checks:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 pi5nvme-ip \
  'df -P / | tail -1; systemctl is-active postgresql signalk-pi5nvme masterbus-signalk boat-n2k-raw-receiver grafana-server'

ssh -o BatchMode=yes -o ConnectTimeout=8 picanm-ip \
  'df -P / | tail -1; systemctl is-active can0-nmea2000 n2k-raw-logger n2k-raw-forwarder; ip -brief link show can0'
```

Expected:

- all listed services are `active`;
- `can0` is `UP`;
- disk use is below 75% on both hosts.

Verify the bounded live database state:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 pi5nvme-ip \
  "sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d boatdata -Atc \"
select 'alternator='||count(*) from masterbus_alternator_samples_v1;
select 'battery='||count(*) from masterbus_battery_samples_v1;
select 'inverter_charger='||count(*) from masterbus_inverter_charger_samples_v1;
select 'solar='||count(*) from masterbus_solar_samples_v1;
select 'staging='||(
  (select count(*) from masterbus_alternator_stage_v1) +
  (select count(*) from masterbus_battery_stage_v1) +
  (select count(*) from masterbus_inverter_charger_stage_v1) +
  (select count(*) from masterbus_solar_stage_v1));
\""
```

Expected:

```text
alternator=2937
battery=2124
inverter_charger=1482
solar=2376
staging=0
```

### Stop conditions at Checkpoint 0

Stop and report; do not repair automatically if:

- a required service is inactive;
- disk use is 75% or higher;
- typed counts differ;
- staging is nonzero;
- the repository is dirty due to another agent;
- tests fail.

## Task 1 — make the Grafana dashboard ready for the imported batch (completed)

This is repository-only and safe to perform without live-deployment approval.

The imported batch may be older than the dashboard's current six-hour default window. Change:

```json
"time": {"from": "now-6h", "to": "now"}
```

to:

```json
"time": {"from": "now-24h", "to": "now"}
```

File:

```text
infra/pi5nvme/grafana/dashboards/boat-history.json
```

Also strengthen `test/grafana-files.test.mjs` with:

```js
assert.equal(dashboard.time.from, 'now-24h')
assert.equal(dashboard.time.to, 'now')
```

Do not alter datasource UID `boat-timescaledb` or dashboard UID `boat-typed-history`.

Run:

```bash
npm test
node -e "JSON.parse(require('fs').readFileSync('infra/pi5nvme/grafana/dashboards/boat-history.json'))"
git diff --check
git diff -- infra/pi5nvme/grafana/dashboards/boat-history.json test/grafana-files.test.mjs
```

### Task 1 success criteria

- dashboard parses as JSON;
- every Grafana SQL target still contains a `$__timeFilter(...)` and a numeric `LIMIT`;
- default range is 24 hours;
- tests pass;
- only the intended repository files changed.

### Checkpoint 1

Commit and push only if the user asked for implementation rather than review:

```bash
git add infra/pi5nvme/grafana/dashboards/boat-history.json test/grafana-files.test.mjs
git commit -m "Use imported batch in default Grafana history range"
git push origin main
git status --short --branch
```

Do not deploy yet unless the user explicitly approves Grafana deployment.

## Task 2 — preflight Grafana deployment (completed)

This task is read-only. It may be performed before deployment approval.

Verify the datasource exists without printing credentials:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 pi5nvme-ip \
  'sudo test -f /etc/grafana/provisioning/datasources/boatdata-postgres.yaml; sudo grep -E "^( *uid:| *type:| *database:)" /etc/grafana/provisioning/datasources/boatdata-postgres.yaml; systemctl is-active grafana-server'
```

Expected safe fields include:

```text
uid: boat-timescaledb
type: postgres
database: boatdata
```

Do not print `secureJsonData` or the full datasource file.

Verify repository/live schema compatibility:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 pi5nvme-ip \
  "sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d boatdata -Atc \"
select to_regclass('public.masterbus_alternator_samples_v1');
select to_regclass('public.masterbus_battery_samples_v1');
select to_regclass('public.masterbus_engine_transitions_v1');
select to_regclass('public.masterbus_engine_runtime_intervals_v1');
select to_regclass('public.v_masterbus_recent_electrical_v1');
select has_table_privilege('grafana_reader','public.masterbus_alternator_samples_v1','SELECT');
select has_table_privilege('grafana_reader','public.masterbus_engine_transitions_v1','SELECT');
\""
```

Expected:

- all five relation names are returned, not blank;
- both privilege checks return `t`.

### Checkpoint 2

Stop and report if any datasource, relation, privilege or service check fails. Do not compensate by changing passwords, roles or schema unless separately approved.

## Task 3 — deploy only the Grafana dashboard files (completed)

**Approval required:** perform this task only after the user explicitly says to deploy Grafana.

Do not run the full installer.

Create a timestamped backup and stage files through `/tmp`:

```bash
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
scp -q -o BatchMode=yes -o ConnectTimeout=8 \
  infra/pi5nvme/grafana/provisioning/dashboards/boatdata.yaml \
  infra/pi5nvme/grafana/dashboards/boat-history.json \
  pi5nvme-ip:/tmp/

ssh -o BatchMode=yes -o ConnectTimeout=8 pi5nvme-ip "set -euo pipefail
BACKUP=/home/jack/grafana-history-backup-$STAMP
mkdir -p \"\$BACKUP\"
sudo cp -a /etc/grafana/provisioning/dashboards/boatdata.yaml \"\$BACKUP/\" 2>/dev/null || true
sudo cp -a /etc/grafana/dashboards/boat-data-platform/boat-history.json \"\$BACKUP/\" 2>/dev/null || true
sudo install -d -m 0755 /etc/grafana/provisioning/dashboards /etc/grafana/dashboards/boat-data-platform
sudo install -m 0644 /tmp/boatdata.yaml /etc/grafana/provisioning/dashboards/boatdata.yaml
sudo install -m 0644 /tmp/boat-history.json /etc/grafana/dashboards/boat-data-platform/boat-history.json
rm -f /tmp/boatdata.yaml /tmp/boat-history.json
sudo systemctl restart grafana-server
systemctl is-active grafana-server
printf 'backup=%s\n' \"\$BACKUP\"
"
```

Why restart Grafana: it gives a clear deployment checkpoint. It does not restart Signal K, MasterBus, PostgreSQL or raw acquisition.

### Rollback

If Grafana fails after deployment, restore only the backed-up dashboard files. Do not run the full installer and do not modify PostgreSQL.

Example, replacing `<BACKUP>` with the printed path:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 pi5nvme-ip "set -euo pipefail
sudo cp -a <BACKUP>/boatdata.yaml /etc/grafana/provisioning/dashboards/boatdata.yaml 2>/dev/null || sudo rm -f /etc/grafana/provisioning/dashboards/boatdata.yaml
sudo cp -a <BACKUP>/boat-history.json /etc/grafana/dashboards/boat-data-platform/boat-history.json 2>/dev/null || sudo rm -f /etc/grafana/dashboards/boat-data-platform/boat-history.json
sudo systemctl restart grafana-server
systemctl is-active grafana-server
"
```

## Task 4 — verify Grafana deployment (completed)

Compare repository and deployed checksums:

```bash
sha256sum \
  infra/pi5nvme/grafana/provisioning/dashboards/boatdata.yaml \
  infra/pi5nvme/grafana/dashboards/boat-history.json

ssh -o BatchMode=yes -o ConnectTimeout=8 pi5nvme-ip \
  'sha256sum /etc/grafana/provisioning/dashboards/boatdata.yaml /etc/grafana/dashboards/boat-data-platform/boat-history.json'
```

Verify Grafana and acquisition health:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 pi5nvme-ip \
  'curl -fsS --max-time 8 http://127.0.0.1:3000/api/health; systemctl is-active grafana-server postgresql signalk-pi5nvme masterbus-signalk boat-n2k-raw-receiver; df -P / | tail -1; timeout 30 /usr/local/bin/check-pi5-boat-health >/dev/null; echo health_helper=pass'
```

Inspect only recent Grafana errors:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 pi5nvme-ip \
  'journalctl -u grafana-server --since "5 minutes ago" --no-pager -p warning..alert | tail -100'
```

Do not declare success merely because Grafana is active. The checksum, API health and service checks must also pass.

### Task 3/4 success criteria

- repository/deployed checksums match;
- Grafana API reports database `ok`;
- Grafana and all acquisition services are active;
- disk remains below 75%;
- health helper passes;
- no new Grafana provisioning/query errors appear;
- no PostgreSQL schema or typed data changed.

After successful deployment, update:

```text
docs/llm-implementation-brief.md
docs/plan.md
```

Record backup path, checksums, health result and deployment time. Run `npm test`, commit and push documentation.

## Task 5 — collect remaining physical engine observations

This task is allowed only while the human operator is physically present and explicitly confirms the engine combination. The agent must not start or stop engines.

Remaining combinations:

| Label | Physical state | Expected Signal K state |
|---|---|---|
| `port-only` | port on, starboard off | port `started`, starboard `stopped` |
| `both-engines` | port on, starboard on | port `started`, starboard `started` |

When the human confirms a combination, capture 60 seconds:

```bash
HOST=$(ssh -G pi5nvme-ip | awk '$1=="hostname" {print $2; exit}')
node scripts/capture-alternator-observation.mjs \
  --label <port-only-or-both-engines> \
  --duration-sec 60 \
  --interval-sec 2 \
  --url "http://$HOST:3001"
```

Do not use `pi5nvme.local` from WSL if it fails to resolve. Use the IPv4 from `ssh -G` as shown.

After capture, edit only the generated `manifest.json` `note` field to record the human-confirmed physical engine state and relevant operating conditions. Do not alter captured samples.

For each capture verify:

- 30 samples were attempted;
- both `senseVoltage` paths are present;
- both `fieldCurrent` paths are present;
- both `propulsion.*.state` paths are present;
- expected running engine has `senseVoltage > 13.25 V` after debounce;
- expected stopped engine has `senseVoltage <= 13.25 V`;
- derived state matches the physical state;
- source timestamps are fresh during the capture.

Example state count check, replacing `<DIR>`:

```bash
rg -o '"path":"propulsion\.(port|starboard)\.state","value":"[^"]+"' <DIR>/samples.jsonl | sort | uniq -c
```

### Stop conditions during physical commissioning

Stop capture and report; do not alter thresholds if:

- the human says the physical state differs from the label;
- Signal K data is stale or missing;
- voltage and derived state disagree;
- either engine changes state unexpectedly;
- the MasterBus service or USB device disappears.

Threshold changes require a separate review. Never tune the threshold merely to make one observation pass.

### Task 5 success criteria

- evidence directory contains `manifest.json`, `samples.jsonl`, `summary.json` and `summary.tsv`;
- manifest records the human-confirmed physical state;
- observed values and states match expectations;
- `docs/two-engine-state-plugin-plan.md`, `docs/llm-implementation-brief.md` and `docs/plan.md` are updated;
- tests pass;
- evidence and documentation are committed and pushed.

Only after both remaining combinations pass may documentation say all four combinations are commissioned. This does not automatically approve logbook integration.

## Task 6 — propose, but do not enable, ongoing MasterBus imports

This is a planning task. Do not create a timer or run another import.

Use the first dashboard and existing evidence to write a short recommendation covering:

- consumer value demonstrated by the dashboard;
- proposed import frequency, or a recommendation to remain manual;
- settled-file rule;
- maximum files/bytes/runtime/memory/workspace;
- deployed-schema parity check;
- source provenance checks;
- failure and retry behavior;
- disk thresholds;
- whether explicit approval remains per batch.

Place the recommendation in a new dated file under `docs/`. Do not change services.

### Task 6 success criteria

- recommendation names a real consumer;
- it preserves native logs as source of truth;
- it never reads active hourly files;
- it keeps broad conversion off `pi5nvme`;
- it has explicit stop/rollback conditions;
- it does not silently authorize automation.

## Task 7 — define the first N2K historical consumer

This is repository/planning work only. Do not perform a live N2K import.

Start with the seven parity-gated PGNs only:

```text
127245 rudder
127250 heading
128259 water speed
128267 water depth
129025 position rapid update
129026 COG/SOG rapid update
130306 wind
```

Write a bounded dashboard/query proposal that answers a named need such as:

- GPS track;
- heading/COG/SOG comparison;
- speed-through-water versus speed-over-ground;
- depth history;
- apparent wind history.

Do not add GNSS-quality, route, AIS or environmental PGNs merely because converters exist. Each additional PGN needs a named consumer and parity/representative-data gate.

### Task 7 success criteria

- proposal names the user-visible question;
- every field maps to one of the seven approved PGNs;
- SQL/query ranges and row limits are bounded;
- no live import is performed;
- required provenance and null-handling behavior are stated;
- proposal identifies the exact approval needed for a later live import.

## Final reporting template

Use this format after any task:

```text
Task completed: <task number and name>
Repository changes: <paths or none>
Live changes: <exact files/services or none>
Tests: <commands and pass/fail counts>
Live checks: <services, disk, bounded DB result>
Safety: no N2K transmit, no MasterBus write, no device control
Checkpoint result: PASS or STOPPED
Remaining approval gate: <exact approval needed>
Commit: <hash or none>
```

Do not say “complete” when a checkpoint is stopped, a physical observation is missing, or a live deployment has not been explicitly approved and verified.
