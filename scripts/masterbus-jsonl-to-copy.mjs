#!/usr/bin/env node
import fs from 'node:fs'
import path from 'node:path'
import readline from 'node:readline'

const usage = `Usage:
  node scripts/masterbus-jsonl-to-copy.mjs --log-file-id ID --typed-dir DIR < masterbus-signalk.jsonl

Reads replayable MasterBus Signal K JSONL logs from collect-masterbus-signalk-log.mjs and emits PostgreSQL COPY TSV files for MasterBus typed staging tables.
`

const args = process.argv.slice(2)
function arg(name) { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : null }
if (args.includes('--help') || args.includes('-h')) { console.log(usage); process.exit(0) }
const logFileId = Number(arg('--log-file-id'))
const typedDir = arg('--typed-dir')
if (!Number.isInteger(logFileId) || logFileId <= 0 || !typedDir) { console.error(usage); process.exit(2) }
fs.mkdirSync(typedDir, { recursive: true })

function tsv(value) {
  if (value === null || value === undefined || (typeof value === 'number' && !Number.isFinite(value))) return '\\N'
  return String(value).replace(/\\/g, '\\\\').replace(/\t/g, ' ').replace(/\r?\n/g, ' ')
}
function num(value) { return typeof value === 'number' && Number.isFinite(value) ? value : null }
function bool(value) { return typeof value === 'boolean' ? value : null }
function updateSource(update) { return update?.$source || update?.source?.label || update?.source?.src || null }
function isMasterbus(update) {
  const source = updateSource(update)
  return source === 'masterbus' || String(source).startsWith('masterbus.')
}

const streams = new Map()
function out(file) {
  if (!streams.has(file)) streams.set(file, fs.createWriteStream(path.join(typedDir, file), { encoding: 'utf8' }))
  return streams.get(file)
}
function write(file, row) { out(file).write(row.map(tsv).join('\t') + '\n') }

const counts = { alternator: 0, battery: 0, inverterCharger: 0, solar: 0, skipped: 0 }
let lineNumber = 0

function emitGroup(time, source, rawLineNumber, kind, key, values) {
  if (kind === 'alternator') {
    write('masterbus_alternator_stage_v1.tsv', [
      time, key, null, source, logFileId, rawLineNumber,
      values.senseVoltage, values.alternatorVoltage, values.voltage, values.current,
      values.fieldCurrent, values.alternatorTemperature, values.temperature
    ])
    counts.alternator++
  } else if (kind === 'battery') {
    write('masterbus_battery_stage_v1.tsv', [
      time, key, null, source, logFileId, rawLineNumber,
      values.voltage, values.current, values.temperature, values.stateOfCharge, values.timeRemaining
    ])
    counts.battery++
  } else if (kind === 'inverterCharger') {
    write('masterbus_inverter_charger_stage_v1.tsv', [
      time, key, null, source, logFileId, rawLineNumber,
      values.inverterEnabled, values.chargerEnabled,
      values.acinVoltage, values.acinCurrent, values.acinCurrentLimit, values.acinFrequency,
      values.acVoltage, values.acPower, values.acFrequency,
      values.dcVoltage, values.dcCurrent
    ])
    counts.inverterCharger++
  } else if (kind === 'solar') {
    write('masterbus_solar_stage_v1.tsv', [
      time, key, null, source, logFileId, rawLineNumber,
      values.batteryVoltage, values.panelVoltage, values.chargeCurrent, values.yieldTotal
    ])
    counts.solar++
  }
}

function add(groups, kind, key, field, value) {
  const groupKey = `${kind}:${key}`
  if (!groups.has(groupKey)) groups.set(groupKey, { kind, key, values: {} })
  groups.get(groupKey).values[field] = value
}

function ingestPath(groups, pathName, value) {
  let m
  if ((m = pathName.match(/^electrical\.alternators\.([^.]+)\.(.+)$/))) {
    const field = {
      senseVoltage: 'senseVoltage', alternatorVoltage: 'alternatorVoltage', voltage: 'voltage', current: 'current',
      fieldCurrent: 'fieldCurrent', alternatorTemperature: 'alternatorTemperature', temperature: 'temperature'
    }[m[2]]
    if (field) add(groups, 'alternator', m[1], field, num(value))
  } else if ((m = pathName.match(/^electrical\.batteries\.([^.]+)\.(.+)$/))) {
    const tail = m[2]
    const field = tail === 'voltage' ? 'voltage'
      : tail === 'current' ? 'current'
      : tail === 'temperature' ? 'temperature'
      : tail === 'capacity.stateOfCharge' ? 'stateOfCharge'
      : tail === 'capacity.timeRemaining' ? 'timeRemaining'
      : null
    if (field) add(groups, 'battery', m[1], field, num(value))
  } else if ((m = pathName.match(/^electrical\.inverters\.([^.]+)\.(.+)$/))) {
    const field = {
      enabled: 'inverterEnabled', 'ac.voltage': 'acVoltage', 'ac.power': 'acPower', 'ac.frequency': 'acFrequency',
      'dc.voltage': 'dcVoltage', 'dc.current': 'dcCurrent'
    }[m[2]]
    if (field) add(groups, 'inverterCharger', m[1], field, field.endsWith('Enabled') ? bool(value) : num(value))
  } else if ((m = pathName.match(/^electrical\.chargers\.([^.]+)\.(.+)$/))) {
    const field = {
      enabled: 'chargerEnabled', 'acin.voltage': 'acinVoltage', 'acin.current': 'acinCurrent',
      'acin.currentLimit': 'acinCurrentLimit', 'acin.frequency': 'acinFrequency'
    }[m[2]]
    if (field) add(groups, 'inverterCharger', m[1], field, field.endsWith('Enabled') ? bool(value) : num(value))
  } else if ((m = pathName.match(/^electrical\.solar\.([^.]+)\.(.+)$/))) {
    const field = {
      batteryVoltage: 'batteryVoltage', panelVoltage: 'panelVoltage', chargeCurrent: 'chargeCurrent', yieldTotal: 'yieldTotal'
    }[m[2]]
    if (field) add(groups, 'solar', m[1], field, num(value))
  }
}

const rl = readline.createInterface({ input: process.stdin })
for await (const line of rl) {
  lineNumber++
  if (!line.trim()) continue
  let record
  try { record = JSON.parse(line) } catch { counts.skipped++; continue }
  const delta = record.delta || record
  const groups = new Map()
  for (const update of delta.updates || []) {
    if (!isMasterbus(update)) continue
    const time = update.timestamp || delta.timestamp || record.receivedAt
    const source = String(updateSource(update) || 'masterbus')
    for (const pv of update.values || []) ingestPath(groups, pv.path, pv.value)
    for (const g of groups.values()) emitGroup(time, source, lineNumber, g.kind, g.key, g.values)
    groups.clear()
  }
}

await Promise.all(Array.from(streams.values(), s => new Promise((resolve, reject) => s.end(err => err ? reject(err) : resolve()))))
console.error(JSON.stringify(counts))
