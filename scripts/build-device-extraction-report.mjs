#!/usr/bin/env node
import fs from 'node:fs/promises'
import path from 'node:path'

const args = process.argv.slice(2)
function arg(name, fallback = undefined) {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : fallback
}
const snapshotDir = arg('--snapshot-dir')
const outFile = arg('--out')
if (!snapshotDir || !outFile) {
  console.error('Usage: node scripts/build-device-extraction-report.mjs --snapshot-dir observations/device-extraction/<ts> --out docs/device-extraction.md')
  process.exit(2)
}

const sources = JSON.parse(await fs.readFile(path.join(snapshotDir, 'signalk-sources.json'), 'utf8'))
const vessel = JSON.parse(await fs.readFile(path.join(snapshotDir, 'signalk-vessel-self.json'), 'utf8'))

function mdTable(headers, rows) {
  return [
    `| ${headers.join(' | ')} |`,
    `| ${headers.map(() => '---').join(' | ')} |`,
    ...rows.map(r => `| ${r.map(c => String(c ?? '').replace(/\n/g, ' ').replace(/\|/g, '\\|')).join(' | ')} |`)
  ].join('\n')
}
function walkValues(node, p = [], rows = []) {
  if (!node || typeof node !== 'object') return rows
  if (Object.prototype.hasOwnProperty.call(node, 'value') && (node.$source || node.timestamp)) {
    rows.push({ path: p.join('.'), source: node.$source || '', pgn: node.pgn || '', value: node.value, timestamp: node.timestamp || '' })
  }
  for (const [k, v] of Object.entries(node)) {
    if (['value', 'timestamp', '$source', 'pgn', 'values', 'meta'].includes(k)) continue
    walkValues(v, p.concat(k), rows)
  }
  return rows
}
function sourceSa(source) {
  return /^picanm-raw-candump-fanout\.(\d+)$/.exec(source)?.[1] || ''
}
function v(v) {
  if (v === null || v === undefined) return String(v)
  if (typeof v === 'number') return Number.isFinite(v) ? String(Number(v.toPrecision(8))) : String(v)
  if (typeof v === 'string' || typeof v === 'boolean') return JSON.stringify(v)
  return JSON.stringify(v).slice(0, 120)
}
function groupBy(rows, fn) {
  const m = new Map()
  for (const row of rows) {
    const k = fn(row)
    if (!m.has(k)) m.set(k, [])
    m.get(k).push(row)
  }
  return m
}

const currentRows = walkValues(vessel).sort((a, b) => a.path.localeCompare(b.path))
const n2k = Object.entries(sources['picanm-raw-candump-fanout'] || {})
  .filter(([, e]) => e?.n2k)
  .map(([sa, e]) => ({
    sa,
    manufacturer: e.n2k.manufacturerCode || '',
    class: e.n2k.deviceClass || '',
    function: e.n2k.deviceFunction || '',
    canName: e.n2k.canName || '',
    pgns: Object.keys(e.n2k.pgns || {}).map(Number).sort((a, b) => a - b),
    unknown: e.n2k.unknownPGNs || {}
  }))
  .sort((a, b) => Number(a.sa) - Number(b.sa))

const rowsBySource = groupBy(currentRows, r => r.source)
function sourcePathSummary(source) {
  return (rowsBySource.get(source) || []).map(r => `${r.path}${r.pgn ? ` (${r.pgn})` : ''}=${v(r.value)}`).join('; ')
}

const n2kDeviceRows = n2k.map(d => [
  d.sa,
  d.manufacturer || '(unknown)',
  d.class,
  d.function,
  d.pgns.join(', '),
  sourcePathSummary(`picanm-raw-candump-fanout.${d.sa}`) || '(no current self-vessel path)'
])

const proprietaryRows = []
for (const d of n2k) {
  for (const [pgn, msg] of Object.entries(d.unknown)) {
    if (!['65313', '65317', '65350', '130821', '130822', '130824', '130860'].includes(pgn)) continue
    const fields = msg.fields || {}
    let extracted = ''
    if (pgn === '130821' && typeof fields.message === 'string') {
      const items = fields.message.trim().split(',').filter(x => x.length)
      extracted = items.map((x, i) => `${i}:${x}`).join(', ')
    } else if (pgn === '130824' && Array.isArray(fields.list)) {
      extracted = fields.list.map(item => `${item.key}${item.value != null ? `=${item.value}` : ''}`).join(', ')
    } else if (fields.data != null) {
      extracted = String(fields.data)
    } else {
      extracted = JSON.stringify(fields).slice(0, 300)
    }
    proprietaryRows.push([d.sa, d.manufacturer, pgn, msg.description || '', msg.timestamp || '', extracted])
  }
}

const masterbusCacheDir = path.join(snapshotDir, 'masterbus-cache')
let masterbusRows = []
try {
  for (const file of (await fs.readdir(masterbusCacheDir)).sort()) {
    if (!file.endsWith('.json')) continue
    const groups = JSON.parse(await fs.readFile(path.join(masterbusCacheDir, file), 'utf8'))
    for (const g of groups.filter(g => g.menu === 'Monitoring')) {
      for (const f of g.fields || []) {
        masterbusRows.push([file.replace(/\.json$/, ''), g.name, f.index, f.name, f.unit, f.viz_type, f.writeable ? 'rw' : 'ro', (f.options || []).join(', ')])
      }
    }
  }
} catch {}

const masterbusCurrentRows = currentRows.filter(r => r.source === 'masterbus').map(r => [r.path, v(r.value), r.timestamp])

const missingEngineElectricalTank = [127488, 127489, 127505, 127506, 127507, 127508, 127509].map(pgn => [
  pgn,
  n2k.filter(d => d.pgns.includes(pgn)).map(d => `${d.sa} ${d.manufacturer} ${d.class}`.trim()).join('; ') || 'not seen in current /sources snapshot'
])

const doc = `# 2026-07-04 device extraction attempt

Purpose: try to get all relevant read-only data out of the devices currently visible to the boat data platform, without enabling NMEA 2000 transmit/control, MasterBus writes, importer/backfill jobs, or broad database workloads.

Input snapshot directory: \`${snapshotDir}\`

Actions taken:

- Captured fresh low-impact Signal K \`/sources\` and \`/vessels/self\` snapshots.
- Copied the local MasterBus schema cache JSON files from \`/var/lib/masterbus\` for offline inspection.
- Attempted one bounded read-only MasterBus enumerate. It returned CombiMaster data, then timed out at the Alpha device; this was stopped and not retried aggressively.
- Added repo support for extra read-only MasterBus state mappings in \`infra/pi5nvme/masterbus/masterbus-signalk-extra-state-mapping.patch\` and updated the installer to apply both MasterBus patches. This is prepared but not live-deployed in this run.
- Generated this report from saved snapshots/caches only.

## Current NMEA 2000 devices and extracted Signal K data

${mdTable(['SA', 'Manufacturer', 'Class', 'Function', 'PGNs seen', 'Current Signal K self-vessel extraction'], n2kDeviceRows)}

## Current MasterBus Signal K extraction

${mdTable(['Signal K path', 'Current value', 'Timestamp'], masterbusCurrentRows)}

## MasterBus monitoring fields available in local cache

These are the read-only/read-write fields exposed by the device schemas. Only read-only fields should be mapped automatically; writeable fields are listed to understand the device but must not be automated without a separate safety review.

${mdTable(['Cache/device schema', 'Group', 'Index', 'Field', 'Unit', 'Type', 'R/W', 'Options'], masterbusRows)}

## Proprietary / partially decoded B&G/Navico/Simnet samples currently accessible from /sources

${mdTable(['SA', 'Manufacturer', 'PGN', 'Description', 'Timestamp', 'Extracted fields/sample'], proprietaryRows)}

## Direct engine / tanks / N2K electrical check

${mdTable(['PGN', 'Current owner(s)'], missingEngineElectricalTank)}

## Implemented in repo during this pass

1. \`scripts/build-device-extraction-report.mjs\` builds this device-centric report from saved snapshots and MasterBus schema cache files.
2. \`infra/pi5nvme/masterbus/masterbus-signalk-extra-state-mapping.patch\` adds prepared read-only mappings for:
   - CombiMaster device operating state and charger charge mode;
   - Alpha regulator/alternator operating state, charge mode, shunt connection state, and shunt SOC;
   - solar controller operating state, charge mode, shunt state, and shunt SOC.
3. \`infra/pi5nvme/install-masterbus-tools.sh\` now applies the base alternator/solar mapping patch plus the extra state mapping patch in order.

## What we can use now

- MasterBus: house batteries, Alpha alternator/regulator voltages/currents/temperatures, CombiMaster AC/DC inverter/charger values, solar controller voltages/currents/energy.
- Airmar SA 35: depth, speed-through-water, water log/trip, water/environmental temperature PGNs.
- B&G/Zeus/Navico: GNSS/nav display data, wind, route/rhumbline fields, autopilot state/target, switch-bank states, proprietary samples.
- Vesper SA 22: AIS/GNSS/environmental source is visible in /sources; current self-vessel primary GNSS paths are coming from B&G SA 11, while Vesper is still likely the AIS/GNSS device for AIS traffic.
- Synthesized engine state: \`propulsion.port.state\` and \`propulsion.starboard.state\` from MasterBus Alpha sense voltage.

## Still not available as live extracted data

- Direct Yanmar engine RPM/coolant/oil/fuel PGNs \`127488\`/\`127489\`.
- N2K tank level PGN \`127505\`.
- N2K DC/charger/battery/inverter PGNs \`127506\`-\`127509\`.
- Per-load states for watermaker/winches/windlass/aircon/washer.
- Reliable semantic labels for Navico ASCII \`130821\` numeric fields or Navico/B&G binary/key-value proprietary fields. The samples are preserved above, but not promoted to Signal K paths yet.

## Recommended next low-risk implementation steps

1. Deploy the prepared extra MasterBus state mapping during a normal Signal K/MasterBus maintenance moment, then run the standard \`npm run collect:health -- --sample-sec 10\` validation.
2. Add Grafana panels using source labels from \`2026-07-04-source-attribution-inventory.md\`: MasterBus electrical, Airmar depth/STW, B&G wind/nav, Vesper AIS/GNSS, synthesized engine state.
3. Keep proprietary B&G/Navico fields as raw/context until a specific missing display value is identified; if needed, begin with bounded \`130821\` samples because it is already ASCII-decoded by canboat.
`

await fs.writeFile(outFile, doc)
console.log(`wrote ${outFile}`)
