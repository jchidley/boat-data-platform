#!/usr/bin/env node
import fs from 'node:fs/promises'
import path from 'node:path'

const args = process.argv.slice(2)
function arg(name, fallback = undefined) {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : fallback
}
function has(name) { return args.includes(name) }

const usage = `Usage:
  node scripts/capture-alternator-observation.mjs --label engines-off [--duration-sec 60] [--interval-sec 2] [--url http://192.168.1.135:3001]

Captures Signal K alternator and derived propulsion state for controlled engine-state observations.
Suggested labels: engines-off, port-only, starboard-only, both-engines.
`

if (has('--help')) {
  console.log(usage)
  process.exit(0)
}

const label = arg('--label')
if (!label || !/^[a-z0-9][a-z0-9._-]*$/i.test(label)) {
  console.error(usage)
  console.error('ERROR: --label is required and must be path-safe')
  process.exit(2)
}

const baseUrl = arg('--url', process.env.SIGNALK_URL || 'http://192.168.1.135:3001').replace(/\/$/, '')
const durationSec = Number(arg('--duration-sec', process.env.DURATION_SEC || '60'))
const intervalSec = Number(arg('--interval-sec', process.env.INTERVAL_SEC || '2'))
const outRoot = arg('--out-root', process.env.OUT_ROOT || 'observations/alternator-engine-state')

if (!Number.isFinite(durationSec) || durationSec <= 0 || durationSec > 3600) throw new Error('duration must be 1..3600 seconds')
if (!Number.isFinite(intervalSec) || intervalSec <= 0 || intervalSec > 300) throw new Error('interval must be 1..300 seconds')

const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z')
const outDir = path.join(outRoot, `${stamp}-${label}`)
await fs.mkdir(outDir, { recursive: true })

function sleep(ms) { return new Promise(resolve => setTimeout(resolve, ms)) }

function flatten(node, prefix = [], rows = []) {
  if (!node || typeof node !== 'object') return rows
  if (Object.prototype.hasOwnProperty.call(node, 'value')) {
    rows.push({
      path: prefix.join('.'),
      value: node.value,
      source: node.$source ?? '',
      timestamp: node.timestamp ?? ''
    })
  }
  for (const [key, value] of Object.entries(node)) {
    if (['value', 'timestamp', '$source', 'meta', 'values'].includes(key)) continue
    flatten(value, prefix.concat(key), rows)
  }
  return rows
}

const samplesPath = path.join(outDir, 'samples.jsonl')
const started = Date.now()
const samples = []
let sampleNo = 0
while ((Date.now() - started) / 1000 < durationSec || sampleNo === 0) {
  sampleNo += 1
  const capturedAt = new Date().toISOString()
  const res = await fetch(`${baseUrl}/signalk/v1/api/vessels/self`, {
    signal: AbortSignal.timeout(5000)
  })
  if (!res.ok) throw new Error(`GET vessel state failed: ${res.status} ${res.statusText}`)
  const json = await res.json()
  const selected = {
    electrical: { alternators: json?.electrical?.alternators ?? {} },
    propulsion: json?.propulsion ?? {}
  }
  const rows = flatten(selected).map(row => ({ captured_at: capturedAt, sample: sampleNo, ...row }))
  samples.push(...rows)
  await fs.appendFile(samplesPath, JSON.stringify({ captured_at: capturedAt, sample: sampleNo, rows }) + '\n')
  const remainingMs = durationSec * 1000 - (Date.now() - started)
  if (remainingMs > 0) await sleep(Math.min(intervalSec * 1000, remainingMs))
}

const byPath = new Map()
for (const row of samples) {
  if (typeof row.value !== 'number' || !Number.isFinite(row.value)) continue
  const s = byPath.get(row.path) ?? { path: row.path, source: row.source, count: 0, min: Infinity, max: -Infinity, sum: 0, latest: row.value, latestTimestamp: row.timestamp }
  s.count += 1
  s.min = Math.min(s.min, row.value)
  s.max = Math.max(s.max, row.value)
  s.sum += row.value
  s.latest = row.value
  s.latestTimestamp = row.timestamp
  byPath.set(row.path, s)
}
const summary = [...byPath.values()].sort((a, b) => a.path.localeCompare(b.path)).map(s => ({
  path: s.path,
  source: s.source,
  count: s.count,
  min: s.min,
  avg: s.sum / s.count,
  max: s.max,
  latest: s.latest,
  latestTimestamp: s.latestTimestamp
}))

const tsv = ['path\tsource\tcount\tmin\tavg\tmax\tlatest\tlatestTimestamp']
for (const s of summary) {
  tsv.push([s.path, s.source, s.count, s.min, s.avg, s.max, s.latest, s.latestTimestamp].join('\t'))
}
await fs.writeFile(path.join(outDir, 'summary.tsv'), tsv.join('\n') + '\n')
await fs.writeFile(path.join(outDir, 'summary.json'), JSON.stringify(summary, null, 2) + '\n')
await fs.writeFile(path.join(outDir, 'manifest.json'), JSON.stringify({
  captured_at: new Date().toISOString(),
  label,
  baseUrl,
  durationSec,
  intervalSec,
  samples: sampleNo,
  rows: samples.length,
  note: 'Signal K /electrical/alternators controlled engine-state observation. Record actual physical engine state separately if not represented by label.'
}, null, 2) + '\n')

console.log(`observation_dir=${outDir}`)
console.log(`samples=${sampleNo}`)
console.log(`rows=${samples.length}`)
for (const s of summary) {
  console.log(`${s.path}\tmin=${s.min.toFixed(3)}\tavg=${s.avg.toFixed(3)}\tmax=${s.max.toFixed(3)}\tlatest=${s.latest.toFixed(3)}`)
}
