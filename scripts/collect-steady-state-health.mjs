#!/usr/bin/env node
import { spawnSync } from 'node:child_process'

const args = process.argv.slice(2)
const usage = `Usage:
  node scripts/collect-steady-state-health.mjs [--sample-sec 30] [--pi5-host pi5nvme] [--print-only]

Runs scripts/check-steady-state.sh, stores PASS/WARN/FAIL lines in the boatdata database table public.health_observations via psql on pi5.
The underlying health check remains low-impact and does not run importers/backfills/analyzer jobs.
`

if (args.includes('--help') || args.includes('-h')) {
  console.log(usage)
  process.exit(0)
}
function arg(name, fallback) {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : fallback
}
const sampleSec = arg('--sample-sec', process.env.SAMPLE_SEC || '30')
const sampleSecNumber = Number(sampleSec)
if (!Number.isFinite(sampleSecNumber) || sampleSecNumber <= 0) {
  console.error(`invalid --sample-sec/SAMPLE_SEC: ${sampleSec}`)
  process.exit(2)
}
const pi5Host = arg('--pi5-host', process.env.PI5_HOST || 'pi5nvme')
const printOnly = args.includes('--print-only') || process.env.PRINT_ONLY === '1'
const checkTimeoutMs = Math.ceil((sampleSecNumber + 90) * 1000)
const runId = new Date().toISOString().replace(/[-:.]/g, '').replace('T', 'T').replace('Z', 'Z')

function slug(s) {
  return s.toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 96) || 'unknown'
}
function groupFor(message) {
  if (/^picanm|^can0|^CAN|^can_rx|^can_bus|^raw_logger|^raw_forwarder|^signalk inactive|\/var\/log\/n2k/i.test(message)) return 'picanm'
  if (/^pi5|^receiver|^masterbus|^collector|^raw importer|^raw TCP|^Signal K fanout|^Timescale/i.test(message)) return 'pi5nvme'
  if (/^Signal K raw-feed/i.test(message)) return 'signalk'
  if (/^MasterBus vessel/i.test(message)) return 'masterbus'
  return 'general'
}
function numericValue(message) {
  const age = message.match(/age ([0-9]+(?:\.[0-9]+)?)s/)
  if (age) return Number(age[1])
  const offset = message.match(/(?:clock|chrony system) offset (-?[0-9]+(?:\.[0-9]+)?)s/)
  if (offset) return Number(offset[1])
  const temp = message.match(/temperature ([0-9]+(?:\.[0-9]+)?)C/)
  if (temp) return Number(temp[1])
  const ratio = message.match(/\(([0-9]+(?:\.[0-9]+)?)%\)/)
  if (ratio) return Number(ratio[1])
  const grew = message.match(/grew ([0-9]+) -> ([0-9]+) bytes/)
  if (grew) return Number(grew[2]) - Number(grew[1])
  const mem = message.match(/memory available ([0-9]+(?:\.[0-9]+)?) MiB/)
  if (mem) return Number(mem[1])
  const stable = message.match(/stable at ([0-9]+(?:\.[0-9]+)?)/)
  if (stable) return Number(stable[1])
  return null
}
function csvCell(value) {
  if (value === null || value === undefined) return ''
  const s = String(value)
  return `"${s.replace(/"/g, '""')}"`
}

const env = {
  ...process.env,
  SAMPLE_SEC: sampleSec,
  PI5_HOST: pi5Host,
  PI5_SIGNALK_URL: process.env.PI5_SIGNALK_URL || `http://${pi5Host}:3001`
}
const check = spawnSync('bash', ['scripts/check-steady-state.sh'], { encoding: 'utf8', env, timeout: checkTimeoutMs })
process.stdout.write(check.stdout || '')
process.stderr.write(check.stderr || '')
if (check.error?.code === 'ETIMEDOUT') {
  console.error(`steady-state health check timed out after ${Math.round(checkTimeoutMs / 1000)}s (sample_sec=${sampleSecNumber}); try a shorter --sample-sec or run outside a constrained harness`)
  process.exit(124)
}

const observations = []
for (const line of (check.stdout || '').split(/\r?\n/)) {
  const m = line.match(/^(PASS|WARN|FAIL)\s+(.*)$/)
  if (!m) continue
  const status = m[1].toLowerCase()
  const message = m[2]
  observations.push({
    observed_at: new Date().toISOString(),
    run_id: runId,
    check_group: groupFor(message),
    check_name: slug(message.replace(/=.*$/, '').replace(/\s+\d+.*$/, '')),
    status,
    message,
    value_double: numericValue(message),
    value_text: null,
    evidence: { sampleSec: sampleSecNumber, checkExitCode: check.status ?? null }
  })
}

if (observations.length === 0) {
  console.error('No PASS/WARN/FAIL observations parsed from health check output')
  process.exit(check.status || 2)
}

const csv = observations.map(o => [
  o.observed_at,
  o.run_id,
  o.check_group,
  o.check_name,
  o.status,
  o.message,
  o.value_double,
  o.value_text,
  JSON.stringify(o.evidence)
].map(csvCell).join(',')).join('\n') + '\n'

if (printOnly) {
  process.stderr.write(`parsed_observations=${observations.length}\n`)
  process.stdout.write(csv)
  process.exit(check.status || 0)
}

const copySql = `COPY public.health_observations (observed_at, run_id, check_group, check_name, status, message, value_double, value_text, evidence) FROM STDIN WITH (FORMAT csv);`
const verifySql = `SELECT count(*) FROM public.health_observations WHERE run_id = '${runId.replace(/'/g, "''")}';`
const remoteCommand = `cd /tmp && sudo -u postgres psql -v ON_ERROR_STOP=1 -d boatdata -c ${JSON.stringify(copySql)} && sudo -u postgres psql -v ON_ERROR_STOP=1 -d boatdata -Atc ${JSON.stringify(verifySql)}`
const ssh = spawnSync('ssh', ['-o', 'ConnectTimeout=5', pi5Host, remoteCommand], {
  input: csv,
  encoding: 'utf8',
  timeout: 30000
})
if (ssh.stdout) process.stderr.write(ssh.stdout)
if (ssh.stderr) process.stderr.write(ssh.stderr)
if (ssh.error?.code === 'ETIMEDOUT') {
  console.error('failed to insert health observations into pi5 database: ssh/psql timed out after 30s')
  process.exit(124)
}
if (ssh.status !== 0) {
  console.error(`failed to insert health observations into pi5 database: ssh/psql exit ${ssh.status}`)
  process.exit(ssh.status || 2)
}
const verifyCount = Number((ssh.stdout || '').trim().split(/\s+/).at(-1))
if (verifyCount !== observations.length) {
  console.error(`insert verification mismatch for run_id=${runId}: expected ${observations.length}, got ${Number.isFinite(verifyCount) ? verifyCount : 'unknown'}`)
  process.exit(2)
}
process.stderr.write(`inserted_health_observations=${observations.length} run_id=${runId}\n`)
process.exit(check.status || 0)
