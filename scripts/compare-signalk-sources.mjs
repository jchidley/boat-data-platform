#!/usr/bin/env node
import fs from 'node:fs/promises'

const args = process.argv.slice(2)
const usage = `Usage:
  node scripts/compare-signalk-sources.mjs --file vessel.json --old-source can0-nmea2000 --new-source picanm-raw-candump-fanout
  node scripts/compare-signalk-sources.mjs --url http://host:3001/signalk/v1/api/vessels/self --old-source ... --new-source ...

This is a low-impact comparison helper. Prefer --file with saved snapshots.
It only reads one Signal K vessel snapshot when --url is used.
`

function arg(name, fallback = undefined) {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : fallback
}

const file = arg('--file')
const url = arg('--url')
const oldSource = arg('--old-source', 'can0-nmea2000')
const newSource = arg('--new-source', 'picanm-raw-candump-fanout')

if ((!file && !url) || !oldSource || !newSource) {
  console.error(usage)
  process.exit(2)
}

async function loadSnapshot() {
  if (file) return JSON.parse(await fs.readFile(file, 'utf8'))
  const res = await fetch(url, { signal: AbortSignal.timeout(5000) })
  if (!res.ok) throw new Error(`GET ${url} failed: ${res.status} ${res.statusText}`)
  return res.json()
}

function isMatchingSource(actual, wanted) {
  return actual === wanted || actual?.startsWith(`${wanted}.`)
}

function valueSummary(value) {
  if (value === null || value === undefined) return String(value)
  if (typeof value === 'number') return Number.isFinite(value) ? String(Number(value.toPrecision(8))) : String(value)
  if (typeof value === 'string' || typeof value === 'boolean') return JSON.stringify(value)
  return JSON.stringify(value).slice(0, 160)
}

function walk(node, path = [], out = []) {
  if (!node || typeof node !== 'object') return out
  if (Object.prototype.hasOwnProperty.call(node, 'value') && node.$source) {
    out.push({
      path: path.join('.'),
      source: node.$source,
      timestamp: node.timestamp ?? null,
      value: node.value
    })
  }
  for (const [key, child] of Object.entries(node)) {
    if (['value', 'timestamp', '$source', 'meta'].includes(key)) continue
    walk(child, path.concat(key), out)
  }
  return out
}

const snapshot = await loadSnapshot()
const rows = walk(snapshot)
const oldRows = rows.filter(r => isMatchingSource(r.source, oldSource))
const newRows = rows.filter(r => isMatchingSource(r.source, newSource))
const oldByPath = new Map(oldRows.map(r => [r.path, r]))
const newByPath = new Map(newRows.map(r => [r.path, r]))
const oldOnly = [...oldByPath.keys()].filter(p => !newByPath.has(p)).sort()
const newOnly = [...newByPath.keys()].filter(p => !oldByPath.has(p)).sort()
const common = [...oldByPath.keys()].filter(p => newByPath.has(p)).sort()

const comparable = common.map(path => {
  const oldRow = oldByPath.get(path)
  const newRow = newByPath.get(path)
  const oldVal = valueSummary(oldRow.value)
  const newVal = valueSummary(newRow.value)
  return { path, sameValue: oldVal === newVal, old: oldVal, new: newVal, oldTimestamp: oldRow.timestamp, newTimestamp: newRow.timestamp }
})
const differing = comparable.filter(r => !r.sameValue)

const result = {
  comparedAt: new Date().toISOString(),
  oldSource,
  newSource,
  counts: {
    totalValues: rows.length,
    oldValues: oldRows.length,
    newValues: newRows.length,
    commonPaths: common.length,
    oldOnly: oldOnly.length,
    newOnly: newOnly.length,
    differingCommonValues: differing.length
  },
  oldOnly: oldOnly.slice(0, 100),
  newOnly: newOnly.slice(0, 100),
  differingCommonValues: differing.slice(0, 100)
}

console.log(JSON.stringify(result, null, 2))
