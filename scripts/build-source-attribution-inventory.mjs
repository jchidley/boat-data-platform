#!/usr/bin/env node
import fs from 'node:fs/promises'

const args = process.argv.slice(2)
const usage = `Usage:
  node scripts/build-source-attribution-inventory.mjs --sources signalk-sources.json --vessel signalk-vessel-self.json --out docs/source-attribution.md [--snapshot-dir observations/...]

Builds a low-impact source attribution report from saved Signal K API snapshots.
It does not query Signal K, run canboat/analyzer, import raw logs, or query Postgres.
`

function arg(name, fallback = undefined) {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : fallback
}

const sourcesFile = arg('--sources')
const vesselFile = arg('--vessel')
const outFile = arg('--out')
const snapshotDir = arg('--snapshot-dir', '')

if (!sourcesFile || !vesselFile || !outFile) {
  console.error(usage)
  process.exit(2)
}

const sources = JSON.parse(await fs.readFile(sourcesFile, 'utf8'))
const vessel = JSON.parse(await fs.readFile(vesselFile, 'utf8'))

function walkValues(node, path = [], rows = []) {
  if (!node || typeof node !== 'object') return rows
  if (Object.prototype.hasOwnProperty.call(node, 'value') && (node.$source || node.timestamp)) {
    rows.push({
      path: path.join('.'),
      source: node.$source || '',
      pgn: node.pgn || '',
      timestamp: node.timestamp || '',
      value: node.value
    })
  }
  for (const [key, child] of Object.entries(node)) {
    if (['value', 'timestamp', '$source', 'pgn', 'values', 'meta'].includes(key)) continue
    walkValues(child, path.concat(key), rows)
  }
  return rows
}

function sourceAddressFromSignalkSource(source) {
  const match = /^picanm-raw-candump-fanout\.(\d+)$/.exec(source)
  return match ? match[1] : ''
}

function valueSummary(value) {
  if (value === null || value === undefined) return String(value)
  if (typeof value === 'number') return Number.isFinite(value) ? String(Number(value.toPrecision(8))) : String(value)
  if (typeof value === 'string' || typeof value === 'boolean') return JSON.stringify(value)
  return JSON.stringify(value).slice(0, 80).replace(/\|/g, '\\|')
}

function mdTable(headers, rows) {
  const header = `| ${headers.join(' | ')} |`
  const sep = `| ${headers.map(() => '---').join(' | ')} |`
  return [header, sep, ...rows.map(row => `| ${row.map(cell => String(cell ?? '').replace(/\n/g, ' ').replace(/\|/g, '\\|')).join(' | ')} |`)].join('\n')
}

const n2kSources = Object.entries(sources['picanm-raw-candump-fanout'] || {})
  .filter(([, entry]) => entry && entry.n2k)
  .map(([sa, entry]) => {
    const n2k = entry.n2k
    const pgns = Object.keys(n2k.pgns || {}).map(Number).sort((a, b) => a - b)
    return {
      sa,
      manufacturer: n2k.manufacturerCode || '',
      deviceClass: n2k.deviceClass || '',
      function: n2k.deviceFunction || '',
      deviceInstance: n2k.deviceInstance ?? '',
      canName: n2k.canName || '',
      pgns
    }
  })
  .sort((a, b) => Number(a.sa) - Number(b.sa))

const valueRows = walkValues(vessel).sort((a, b) => a.path.localeCompare(b.path))
const bySource = new Map()
for (const row of valueRows) {
  const key = row.source || '(none)'
  if (!bySource.has(key)) bySource.set(key, { count: 0, pgns: new Set(), prefixes: new Set() })
  const item = bySource.get(key)
  item.count++
  if (row.pgn) item.pgns.add(row.pgn)
  item.prefixes.add(row.path.split('.').slice(0, 2).join('.'))
}

const sourceSummaryRows = [...bySource.entries()]
  .sort((a, b) => b[1].count - a[1].count || a[0].localeCompare(b[0]))
  .map(([source, item]) => [
    source,
    sourceAddressFromSignalkSource(source),
    item.count,
    [...item.pgns].sort((a, b) => Number(a) - Number(b)).join(', '),
    [...item.prefixes].sort().join(', ')
  ])

function pgnOwnerRows(pgns) {
  return pgns.map(pgn => {
    const owners = n2kSources.filter(src => src.pgns.includes(pgn))
    return [
      pgn,
      owners.map(o => `${o.sa} ${o.manufacturer} ${o.deviceClass}`.trim()).join('; ') || 'not present in /sources snapshot'
    ]
  })
}

const pathRows = valueRows.map(row => [
  row.path,
  row.source,
  sourceAddressFromSignalkSource(row.source),
  row.pgn,
  valueSummary(row.value)
])

const doc = `# 2026-07-04 source-attribution inventory

Purpose: attribute current Signal K paths and current raw NMEA 2000 PGN source addresses before building dashboards that assume a device source.

This report is generated from saved low-impact Signal K API snapshots only:

- Sources snapshot: \`${sourcesFile}\`
- Vessel snapshot: \`${vesselFile}\`${snapshotDir ? `\n- Snapshot directory: \`${snapshotDir}\`` : ''}

No raw import/backfill, analyzer bulk job, broad database aggregate, or NMEA 2000 transmit/control action was run.

## NMEA 2000 source-address inventory from Signal K /sources

${mdTable(['SA', 'Manufacturer', 'Class', 'Function', 'Instance', 'CAN name', 'PGNs seen in /sources'], n2kSources.map(src => [src.sa, src.manufacturer, src.deviceClass, src.function, src.deviceInstance, src.canName, src.pgns.join(', ')]))}

## Current Signal K path source summary

${mdTable(['Signal K source', 'N2K SA', 'Current path count', 'PGNs on current paths', 'Path groups'], sourceSummaryRows)}

## High-value PGN attribution checks

### Engine / tanks / N2K electrical

${mdTable(['PGN', 'Current /sources owner(s)'], pgnOwnerRows([127488, 127489, 127505, 127506, 127507, 127508, 127509]))}

### Airmar / instrument data

${mdTable(['PGN', 'Current /sources owner(s)'], pgnOwnerRows([128259, 128267, 128275, 130310, 130311, 130312, 130316]))}

### Vesper / AIS / GNSS candidates

${mdTable(['PGN', 'Current /sources owner(s)'], pgnOwnerRows([129025, 129026, 129029, 129038, 129039, 129040, 129041, 129794, 129798, 129801, 129802, 129809, 129810]))}

### B&G / Navico proprietary and autopilot candidates

${mdTable(['PGN', 'Current /sources owner(s)'], pgnOwnerRows([65313, 65317, 65350, 127237, 127245, 127501, 130821, 130822, 130824, 130860]))}

## Current Signal K self-vessel path attribution

${mdTable(['Path', 'Signal K source', 'N2K SA', 'PGN', 'Current value summary'], pathRows)}

## Conclusions

1. Current self-vessel electrical/house/Alpha alternator/solar/inverter data is from \`masterbus\`, not NMEA 2000 PGNs.
2. Current synthesized engine state is from \`signalk-two-engine-state.XX\`, not direct Yanmar PGNs.
3. No current /sources owner is present for direct engine PGNs \`127488\`/\`127489\`, tank PGN \`127505\`, or N2K DC/charger/battery/inverter PGNs \`127506\`-\`127509\`.
4. Airmar source address \`35\` currently owns depth/STW/log and related environmental PGNs: \`128259\`, \`128267\`, \`128275\`, \`130310\`, \`130311\`, and \`130316\`.
5. Vesper source address \`22\` is a strong AIS/GNSS candidate: it advertises AIS/GNSS PGNs including \`129025\`, \`129026\`, \`129029\`, \`129038\`, \`129794\`, plus heading/environmental PGNs.
6. B&G/Navico sources dominate navigation display, wind, GNSS, display, switch-bank, route/autopilot, and proprietary traffic. Source addresses \`4\`, \`8\`, \`9\`, \`12\`, \`14\`, \`15\`-\`18\` are especially relevant for dashboards that mention B&G/Zeus/Navico.
7. Proprietary PGNs remain read-only context. \`130821\` is sourced by Navico SA \`4\`; \`130824\` by B&G SA \`12\`; \`130822\` by B&G display SAs \`15\`-\`18\`; \`65313\`/\`65317\` by B&G navigation SAs \`8\` and \`9\`.
`

await fs.writeFile(outFile, doc)
console.log(`wrote ${outFile}`)
