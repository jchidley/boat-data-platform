#!/usr/bin/env node
import fs from 'node:fs'
import path from 'node:path'
import readline from 'node:readline'

const usage = `Usage:
  node scripts/analyzer-jsonl-to-n2k-copy.mjs --log-file-id ID --frames-tsv PATH --fields-tsv PATH [options] < analyzer.jsonl

Options:
  --typed-dir DIR          Write supported PGN-shaped TSV files
  --research-mode MODE     none (default), untyped, or selected
  --research-pgn LIST      Comma-separated PGNs required with selected mode

Converts canboat/analyzerjs JSONL to relational TSV files suitable for PostgreSQL COPY. Normal imports write a disposable staging envelope for summaries plus supported typed PGNs carrying direct raw-file/message provenance. Research fields are opt-in and must never be enabled as an unbounded full-history duplicate.
`

const args = process.argv.slice(2)
if (args.includes('--help') || args.includes('-h')) {
  console.log(usage)
  process.exit(0)
}
function arg(name) {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : null
}
const logFileId = Number(arg('--log-file-id'))
const framesPath = arg('--frames-tsv')
const fieldsPath = arg('--fields-tsv')
const typedDir = arg('--typed-dir')
const researchMode = arg('--research-mode') || 'none'
const researchPgns = new Set((arg('--research-pgn') || '').split(',').filter(Boolean).map(Number))
if (!['none', 'untyped', 'selected'].includes(researchMode)) {
  console.error('--research-mode must be none, untyped, or selected')
  process.exit(2)
}
if (researchMode === 'selected' && (researchPgns.size === 0 || [...researchPgns].some(pgn => !Number.isInteger(pgn) || pgn <= 0))) {
  console.error('--research-pgn must contain one or more positive comma-separated PGNs in selected mode')
  process.exit(2)
}
if (!Number.isInteger(logFileId) || logFileId <= 0 || !framesPath || !fieldsPath) {
  console.error(usage)
  process.exit(2)
}
if (typedDir) fs.mkdirSync(typedDir, { recursive: true })

function edgeTimestampFromAnalyzerInput(msg) {
  const line = Array.isArray(msg.input) ? msg.input[0] : null
  if (typeof line === 'string') {
    const match = line.match(/^\((\d+(?:\.\d+)?)\)/)
    if (match) {
      const epochSeconds = Number(match[1])
      if (Number.isFinite(epochSeconds)) return new Date(epochSeconds * 1000).toISOString()
    }
  }
  if (msg.timestamp) return new Date(msg.timestamp).toISOString()
  return null
}

function tsv(value) {
  if (value === null || value === undefined || (typeof value === 'number' && !Number.isFinite(value))) return '\\N'
  return String(value)
    .replace(/\\/g, '\\\\')
    .replace(/\t/g, ' ')
    .replace(/\r?\n/g, ' ')
}

function fieldKind(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return 'number'
  if (typeof value === 'boolean') return 'boolean'
  if (typeof value === 'string') return 'text'
  return null
}

function canId(value) {
  if (Number.isInteger(value)) return value
  if (typeof value === 'string') {
    const n = value.startsWith('0x') ? Number.parseInt(value.slice(2), 16) : Number(value)
    if (Number.isInteger(n)) return n
  }
  return null
}

function primitiveFieldEntries(fields, prefix = '') {
  const out = []
  if (!fields || typeof fields !== 'object' || Array.isArray(fields)) return out
  for (const [key, value] of Object.entries(fields)) {
    const name = prefix ? `${prefix}.${key}` : key
    const kind = fieldKind(value)
    if (kind) out.push([name, value, kind])
    else if (value && typeof value === 'object' && !Array.isArray(value)) out.push(...primitiveFieldEntries(value, name))
  }
  return out
}

function keyName(name) {
  return String(name).toLowerCase().replace(/[^a-z0-9]+/g, '')
}

function fieldMap(fields) {
  const map = new Map()
  for (const [name, value] of primitiveFieldEntries(fields)) map.set(keyName(name), value)
  return map
}

function f(map, ...names) {
  for (const name of names) {
    const value = map.get(keyName(name))
    if (value !== undefined) return value
  }
  return null
}

function num(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value
  if (typeof value === 'string' && value.trim() !== '') {
    const n = Number(value)
    if (Number.isFinite(n)) return n
  }
  return null
}

function int(value) {
  const n = num(value)
  return Number.isInteger(n) ? n : null
}

function text(value) {
  return value === null || value === undefined ? null : String(value)
}

function daysSince1970(value) {
  const n = num(value)
  if (n !== null) return Math.trunc(n)
  if (typeof value === 'string') {
    const match = value.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$/)
    if (match) return Math.floor(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])) / 86400000)
    const d = new Date(value)
    if (!Number.isNaN(d.valueOf())) return Math.floor(d.valueOf() / 86400000)
  }
  return null
}

function secondsSinceMidnight(value) {
  const n = num(value)
  if (n !== null) return n
  if (typeof value === 'string') {
    const m = value.match(/(\d{1,2}):(\d{2})(?::(\d{2}(?:\.\d+)?))?/)
    if (m) return Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3] ?? 0)
  }
  return null
}

function switchIndicators(fields) {
  return Array.from({ length: 28 }, (_, i) => text(f(fields, `Indicator${i + 1}`)))
}

function satelliteRows(c) {
  const list = Array.isArray(c.rawFields?.list) ? c.rawFields.list : []
  // No child row exists when the repeating list is absent/empty. Emitting a
  // placeholder would violate satellite_index NOT NULL and invent a fact.
  if (!list.length) return []
  return list.map((sat, idx) => {
    const m = fieldMap(sat)
    return [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'SID')), text(f(c.fields, 'Range Residual Mode')), int(f(c.fields, 'Sats in View')), idx, int(f(m, 'PRN')), num(f(m, 'Elevation')), num(f(m, 'Azimuth')), num(f(m, 'SNR')), num(f(m, 'Range residuals')), text(f(m, 'Status'))]
  })
}

function routeWaypointRows(c) {
  const list = Array.isArray(c.rawFields?.list) ? c.rawFields.list : []
  const base = [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'Start RPS#')), int(f(c.fields, 'nItems')), int(f(c.fields, 'Database ID')), int(f(c.fields, 'Route ID')), text(f(c.fields, 'Navigation direction in route')), text(f(c.fields, 'Supplementary Route/WP data available')), text(f(c.fields, 'Route Name'))]
  // The parent message remains represented by frame/file summaries. Do not
  // invent a waypoint child with a null list position.
  if (!list.length) return []
  return list.map((wp, idx) => {
    const m = fieldMap(wp)
    return [...base, idx, int(f(m, 'WP ID')), text(f(m, 'WP Name')), num(f(m, 'WP Latitude')), num(f(m, 'WP Longitude'))]
  })
}

const typedSpecs = new Map([
  [129025, {
    file: 'n2k_position_rapid_129025_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, num(f(c.fields, 'Latitude')), num(f(c.fields, 'Longitude'))]
  }],
  [129026, {
    file: 'n2k_cog_sog_129026_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'SID')), text(f(c.fields, 'COG Reference', 'Reference')), num(f(c.fields, 'COG')), num(f(c.fields, 'SOG'))]
  }],
  [129029, {
    file: 'n2k_gnss_position_129029_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'SID')), daysSince1970(f(c.fields, 'Date')), secondsSinceMidnight(f(c.fields, 'Time')), num(f(c.fields, 'Latitude')), num(f(c.fields, 'Longitude')), num(f(c.fields, 'Altitude')), text(f(c.fields, 'GNSS type')), text(f(c.fields, 'Method')), text(f(c.fields, 'Integrity')), int(f(c.fields, 'Number of SVs', 'Satellites')), num(f(c.fields, 'HDOP')), num(f(c.fields, 'PDOP')), num(f(c.fields, 'Geoidal Separation')), int(f(c.fields, 'Reference Stations'))]
  }],
  [127250, {
    file: 'n2k_heading_127250_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'SID')), num(f(c.fields, 'Heading')), num(f(c.fields, 'Deviation')), num(f(c.fields, 'Variation')), text(f(c.fields, 'Reference'))]
  }],
  [127245, {
    file: 'n2k_rudder_127245_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'Instance')), text(f(c.fields, 'Direction Order')), num(f(c.fields, 'Angle Order')), num(f(c.fields, 'Position'))]
  }],
  [127237, {
    file: 'n2k_heading_track_control_127237_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, text(f(c.fields, 'Rudder Limit Exceeded')), text(f(c.fields, 'Off-Heading Limit Exceeded')), text(f(c.fields, 'Off-Track Limit Exceeded')), text(f(c.fields, 'Override')), text(f(c.fields, 'Steering Mode')), text(f(c.fields, 'Turn Mode')), text(f(c.fields, 'Heading Reference')), text(f(c.fields, 'Commanded Rudder Direction')), num(f(c.fields, 'Commanded Rudder Angle')), num(f(c.fields, 'Heading-To-Steer (Course)', 'Heading To Steer Course')), num(f(c.fields, 'Track')), num(f(c.fields, 'Rudder Limit')), num(f(c.fields, 'Off-Heading Limit')), num(f(c.fields, 'Radius of Turn Order')), num(f(c.fields, 'Rate of Turn Order')), num(f(c.fields, 'Off-Track Limit')), num(f(c.fields, 'Vessel Heading'))]
  }],
  [127251, {
    file: 'n2k_rate_of_turn_127251_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'SID')), num(f(c.fields, 'Rate'))]
  }],
  [127501, {
    file: 'n2k_switch_bank_status_127501_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'Instance')), ...switchIndicators(c.fields)]
  }],
  [127257, {
    file: 'n2k_attitude_127257_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'SID')), num(f(c.fields, 'Yaw')), num(f(c.fields, 'Pitch')), num(f(c.fields, 'Roll'))]
  }],
  [127258, {
    file: 'n2k_magnetic_variation_127258_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'SID')), text(f(c.fields, 'Source')), num(f(c.fields, 'Variation'))]
  }],
  [128259, {
    file: 'n2k_water_speed_128259_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, num(f(c.fields, 'Speed Water Referenced')), num(f(c.fields, 'Speed Ground Referenced')), text(f(c.fields, 'Speed Water Referenced Type'))]
  }],
  [128267, {
    file: 'n2k_water_depth_128267_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'SID')), num(f(c.fields, 'Depth')), num(f(c.fields, 'Offset')), num(f(c.fields, 'Range'))]
  }],
  [128275, {
    file: 'n2k_distance_log_128275_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, daysSince1970(f(c.fields, 'Date')), secondsSinceMidnight(f(c.fields, 'Time')), num(f(c.fields, 'Log')), num(f(c.fields, 'Trip Log'))]
  }],
  [129284, {
    file: 'n2k_navigation_data_129284_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'SID')), num(f(c.fields, 'Distance to Waypoint')), text(f(c.fields, 'Course/Bearing reference')), text(f(c.fields, 'Perpendicular Crossed')), text(f(c.fields, 'Arrival Circle Entered')), text(f(c.fields, 'Calculation Type')), secondsSinceMidnight(f(c.fields, 'ETA Time')), daysSince1970(f(c.fields, 'ETA Date')), num(f(c.fields, 'Bearing, Origin to Destination Waypoint')), num(f(c.fields, 'Bearing, Position to Destination Waypoint')), int(f(c.fields, 'Origin Waypoint Number')), int(f(c.fields, 'Destination Waypoint Number')), num(f(c.fields, 'Destination Latitude')), num(f(c.fields, 'Destination Longitude')), num(f(c.fields, 'Waypoint Closing Velocity'))]
  }],
  [129285, {
    file: 'n2k_route_waypoint_129285_stage_v2.tsv',
    rows: routeWaypointRows
  }],
  [129038, {
    file: 'n2k_ais_class_a_position_129038_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, text(f(c.fields, 'Message ID')), text(f(c.fields, 'Repeat Indicator')), int(f(c.fields, 'User ID')), num(f(c.fields, 'Longitude')), num(f(c.fields, 'Latitude')), text(f(c.fields, 'Position Accuracy')), text(f(c.fields, 'RAIM')), text(f(c.fields, 'Time Stamp')), num(f(c.fields, 'COG')), num(f(c.fields, 'SOG')), text(f(c.fields, 'Communication State')), text(f(c.fields, 'AIS Transceiver information')), num(f(c.fields, 'Heading')), num(f(c.fields, 'Rate of Turn')), text(f(c.fields, 'Nav Status')), text(f(c.fields, 'Special Maneuver Indicator')), int(f(c.fields, 'Sequence ID'))]
  }],
  [129039, {
    file: 'n2k_ais_class_b_position_129039_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, text(f(c.fields, 'Message ID')), text(f(c.fields, 'Repeat Indicator')), int(f(c.fields, 'User ID')), num(f(c.fields, 'Longitude')), num(f(c.fields, 'Latitude')), text(f(c.fields, 'Position Accuracy')), text(f(c.fields, 'RAIM')), text(f(c.fields, 'Time Stamp')), num(f(c.fields, 'COG')), num(f(c.fields, 'SOG')), text(f(c.fields, 'Communication State')), text(f(c.fields, 'AIS Transceiver information')), num(f(c.fields, 'Heading')), text(f(c.fields, 'Unit type')), text(f(c.fields, 'Integrated Display')), text(f(c.fields, 'DSC')), text(f(c.fields, 'Band')), text(f(c.fields, 'Can handle Msg 22')), text(f(c.fields, 'AIS mode')), text(f(c.fields, 'AIS communication state'))]
  }],
  [129794, {
    file: 'n2k_ais_class_a_static_129794_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, text(f(c.fields, 'Message ID')), text(f(c.fields, 'Repeat Indicator')), int(f(c.fields, 'User ID')), int(f(c.fields, 'IMO number')), text(f(c.fields, 'Callsign')), text(f(c.fields, 'Name')), text(f(c.fields, 'Type of ship')), num(f(c.fields, 'Length')), num(f(c.fields, 'Beam')), num(f(c.fields, 'Position reference from Starboard')), num(f(c.fields, 'Position reference from Bow')), daysSince1970(f(c.fields, 'ETA Date')), secondsSinceMidnight(f(c.fields, 'ETA Time')), num(f(c.fields, 'Draft')), text(f(c.fields, 'Destination')), text(f(c.fields, 'AIS version indicator')), text(f(c.fields, 'GNSS type')), text(f(c.fields, 'DTE')), text(f(c.fields, 'AIS Transceiver information'))]
  }],
  [129809, {
    file: 'n2k_ais_class_b_static_a_129809_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, text(f(c.fields, 'Message ID')), text(f(c.fields, 'Repeat Indicator')), int(f(c.fields, 'User ID')), text(f(c.fields, 'Name')), text(f(c.fields, 'AIS Transceiver information')), int(f(c.fields, 'Sequence ID'))]
  }],
  [129810, {
    file: 'n2k_ais_class_b_static_b_129810_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, text(f(c.fields, 'Message ID')), text(f(c.fields, 'Repeat Indicator')), int(f(c.fields, 'User ID')), text(f(c.fields, 'Type of ship')), text(f(c.fields, 'Vendor ID')), text(f(c.fields, 'Callsign')), num(f(c.fields, 'Length')), num(f(c.fields, 'Beam')), num(f(c.fields, 'Position reference from Starboard')), num(f(c.fields, 'Position reference from Bow')), int(f(c.fields, 'Mothership User ID')), text(f(c.fields, 'GNSS type')), text(f(c.fields, 'AIS Transceiver information')), int(f(c.fields, 'Sequence ID'))]
  }],
  [129539, {
    file: 'n2k_gnss_dops_129539_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'SID')), text(f(c.fields, 'Desired Mode')), text(f(c.fields, 'Actual Mode')), num(f(c.fields, 'HDOP')), num(f(c.fields, 'VDOP')), num(f(c.fields, 'TDOP'))]
  }],
  [129540, {
    file: 'n2k_gnss_satellites_129540_stage_v2.tsv',
    rows: satelliteRows
  }],
  [130306, {
    file: 'n2k_wind_130306_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'SID')), num(f(c.fields, 'Wind Speed', 'Wind.Speed')), num(f(c.fields, 'Wind Angle', 'Wind.Angle')), text(f(c.fields, 'Reference'))]
  }],
  [130310, {
    file: 'n2k_environment_130310_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'SID')), num(f(c.fields, 'Water Temperature')), num(f(c.fields, 'Outside Ambient Air Temperature')), num(f(c.fields, 'Atmospheric Pressure'))]
  }],
  [130311, {
    file: 'n2k_environment_130311_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'SID')), text(f(c.fields, 'Temperature Source')), text(f(c.fields, 'Humidity Source')), num(f(c.fields, 'Temperature')), num(f(c.fields, 'Humidity')), num(f(c.fields, 'Atmospheric Pressure'))]
  }],
  [130312, {
    file: 'n2k_temperature_130312_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'SID')), int(f(c.fields, 'Instance')), text(f(c.fields, 'Source')), num(f(c.fields, 'Actual Temperature')), num(f(c.fields, 'Set Temperature'))]
  }],
  [130314, {
    file: 'n2k_pressure_130314_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'SID')), int(f(c.fields, 'Instance')), text(f(c.fields, 'Source')), num(f(c.fields, 'Pressure'))]
  }],
  [130316, {
    file: 'n2k_temperature_ext_130316_stage_v2.tsv',
    row: c => [c.logFileId, c.messageIndex, c.time, c.src, int(f(c.fields, 'SID')), int(f(c.fields, 'Instance')), text(f(c.fields, 'Source')), num(f(c.fields, 'Temperature')), num(f(c.fields, 'Set Temperature'))]
  }]
])

const frames = fs.createWriteStream(framesPath, { encoding: 'utf8' })
const fields = fs.createWriteStream(fieldsPath, { encoding: 'utf8' })
const typedStreams = new Map()
function typedStream(spec) {
  if (!typedDir) return null
  if (!typedStreams.has(spec.file)) typedStreams.set(spec.file, fs.createWriteStream(path.join(typedDir, spec.file), { encoding: 'utf8' }))
  return typedStreams.get(spec.file)
}

const rl = readline.createInterface({ input: process.stdin })
let messageIndex = 0
let framesWritten = 0
let fieldsWritten = 0
let typedWritten = 0
let skipped = 0

for await (const line of rl) {
  if (!line.trim().startsWith('{')) continue
  let msg
  try { msg = JSON.parse(line) } catch { skipped++; continue }
  const time = edgeTimestampFromAnalyzerInput(msg)
  if (!time || !Number.isInteger(msg.pgn)) { skipped++; continue }
  const rowIndex = messageIndex++
  const src = Number.isInteger(msg.src) ? msg.src : null
  frames.write([
    logFileId,
    rowIndex,
    time,
    msg.pgn,
    src,
    Number.isInteger(msg.dst) ? msg.dst : null,
    Number.isInteger(msg.prio) ? msg.prio : null,
    canId(msg.id)
  ].map(tsv).join('\t') + '\n')
  framesWritten++

  const fieldsForMsg = fieldMap(msg.fields)
  const spec = typedSpecs.get(msg.pgn)
  const stream = spec ? typedStream(spec) : null
  if (stream) {
    const context = { logFileId, messageIndex: rowIndex, time, src, fields: fieldsForMsg, rawFields: msg.fields }
    const rows = spec.rows ? spec.rows(context) : [spec.row(context)]
    for (const row of rows) {
      stream.write(row.map(tsv).join('\t') + '\n')
      typedWritten++
    }
  }

  const writeResearch = researchMode === 'selected'
    ? researchPgns.has(msg.pgn)
    : researchMode === 'untyped' && !typedSpecs.has(msg.pgn)
  if (writeResearch) {
    for (const [fieldName, value, kind] of primitiveFieldEntries(msg.fields)) {
      let valueDouble = null, valueText = null, valueBool = null
      if (kind === 'number') valueDouble = value
      else if (kind === 'boolean') valueBool = value
      else valueText = value
      fields.write([
        logFileId,
        rowIndex,
        time,
        msg.pgn,
        src,
        fieldName,
        valueDouble,
        valueText,
        valueBool
      ].map(tsv).join('\t') + '\n')
      fieldsWritten++
    }
  }
}

await Promise.all([
  new Promise((resolve, reject) => frames.end(err => err ? reject(err) : resolve())),
  new Promise((resolve, reject) => fields.end(err => err ? reject(err) : resolve())),
  ...Array.from(typedStreams.values(), stream => new Promise((resolve, reject) => stream.end(err => err ? reject(err) : resolve())))
])

console.error(JSON.stringify({ researchMode, researchPgns: [...researchPgns], framesWritten, fieldsWritten, typedWritten, skipped }))
