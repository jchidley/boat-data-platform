#!/usr/bin/env node
import fs from 'node:fs'
import path from 'node:path'
import readline from 'node:readline'

const usage = `Usage:
  node scripts/masterbus-native-jsonl-to-copy.mjs --log-file-id ID --typed-dir DIR < masterbus-native.jsonl

Converts append-only masterbus-native-event-v1 records captured before Signal K mapping into typed PostgreSQL COPY TSV.
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
function decoded(value) {
  if (!value || typeof value !== 'object') return null
  if (typeof value.Float === 'number' && Number.isFinite(value.Float)) return value.Float
  if (typeof value.Boolean === 'boolean') return value.Boolean
  if (value.Time && typeof value.Time === 'object') {
    const { days = 0, hour = 0, min = 0, sec = 0 } = value.Time
    return days * 86400 + hour * 3600 + min * 60 + sec
  }
  if (value.List && Number.isInteger(value.List.index)) return value.List.index
  if (value.Eventable && Number.isInteger(value.Eventable.index)) return value.Eventable.index
  return null
}

const streams = new Map()
function write(file, row) {
  if (!streams.has(file)) streams.set(file, fs.createWriteStream(path.join(typedDir, file), { encoding: 'utf8' }))
  streams.get(file).write(row.map(tsv).join('\t') + '\n')
}
const counts = { alternator: 0, battery: 0, inverterCharger: 0, solar: 0, skipped: 0 }
let lineNumber = 0

function sparse(columns, field, value) {
  return columns.map(name => name === field ? value : null)
}

const rl = readline.createInterface({ input: process.stdin })
for await (const line of rl) {
  lineNumber++
  if (!line.trim()) continue
  let event
  try { event = JSON.parse(line) } catch { counts.skipped++; continue }
  if (event.schema !== 'masterbus-native-event-v1' || !event.observedAt || !event.instance || !event.name) {
    counts.skipped++
    continue
  }
  const value = decoded(event.value)
  if (value === null) { counts.skipped++; continue }
  const source = `masterbus-native:${event.device ?? 'unknown'}`
  const base = [event.observedAt, event.instance, null, source, logFileId, lineNumber]
  let field = null

  if (event.instance.startsWith('alpha-')) {
    field = ({
      'Sense voltage': 'senseVoltage', 'Alternator volt.': 'alternatorVoltage',
      'Battery voltage': 'voltage', 'Battery current': 'current', 'Field current': 'fieldCurrent',
      'Alternator temp.': 'alternatorTemperature', 'Battery temp.': 'temperature'
    })[event.name]
    if (field) {
      const v = event.unit === '°C' ? value + 273.15 : value
      write('masterbus_alternator_stage_v1.tsv', [...base, ...sparse([
        'senseVoltage', 'alternatorVoltage', 'voltage', 'current', 'fieldCurrent', 'alternatorTemperature', 'temperature'
      ], field, v)])
      counts.alternator++
      continue
    }
  }

  if (event.class === 'BAT') {
    field = ({
      'Battery': event.unit === 'V' ? 'voltage' : event.unit === 'A' ? 'current' : event.unit === '°C' ? 'temperature' : null,
      Voltage: 'voltage', Current: 'current', Temperature: 'temperature',
      'State of charge': 'stateOfCharge', 'Time remaining': 'timeRemaining'
    })[event.name]
    if (field) {
      let v = value
      if (event.unit === '°C') v += 273.15
      if (event.name === 'State of charge') v /= 100
      write('masterbus_battery_stage_v1.tsv', [...base, ...sparse([
        'voltage', 'current', 'temperature', 'stateOfCharge', 'timeRemaining'
      ], field, v)])
      counts.battery++
      continue
    }
  }

  if (event.class === 'CMR') {
    field = ({
      Inverter: 'inverterEnabled', Charger: 'chargerEnabled', 'Input voltage': 'acinVoltage',
      'Input current': 'acinCurrent', 'AC IN limit': 'acinCurrentLimit', 'Input frequency': 'acinFrequency',
      'Output voltage': 'acVoltage', 'Output power': 'acPower', 'Output frequency': 'acFrequency',
      'Battery voltage': 'dcVoltage', 'Battery current': 'dcCurrent'
    })[event.name]
    if (field) {
      write('masterbus_inverter_charger_stage_v1.tsv', [...base, ...sparse([
        'inverterEnabled', 'chargerEnabled', 'acinVoltage', 'acinCurrent', 'acinCurrentLimit',
        'acinFrequency', 'acVoltage', 'acPower', 'acFrequency', 'dcVoltage', 'dcCurrent'
      ], field, value)])
      counts.inverterCharger++
      continue
    }
  }

  if (event.instance.endsWith('-solars')) {
    field = ({ 'Battery voltage': 'batteryVoltage', 'Solar voltage': 'panelVoltage', 'Charge current': 'chargeCurrent', 'Total energy': 'yieldTotal' })[event.name]
    if (field) {
      const v = event.unit === 'kWh' ? value * 3_600_000 : value
      write('masterbus_solar_stage_v1.tsv', [...base, ...sparse([
        'batteryVoltage', 'panelVoltage', 'chargeCurrent', 'yieldTotal'
      ], field, v)])
      counts.solar++
      continue
    }
  }
  counts.skipped++
}
await Promise.all([...streams.values()].map(stream => new Promise((resolve, reject) => stream.end(err => err ? reject(err) : resolve()))))
console.error(JSON.stringify(counts))
