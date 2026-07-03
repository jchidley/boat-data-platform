import fs from 'node:fs'
import pg from 'pg'

export function loadEnvFile(path = '/etc/boat-data-platform/db.env') {
  const out = {}
  if (!fs.existsSync(path)) return out
  let text
  try { text = fs.readFileSync(path, 'utf8') } catch { return out }
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/)
    if (!m) continue
    out[m[1]] = m[2]
  }
  return out
}

export function makePool(role = 'ingest') {
  const hasPasswordEnv = Boolean(process.env.PGPASSWORD || process.env.BOAT_INGEST_PASSWORD || process.env.GRAFANA_READER_PASSWORD)
  const user = process.env.PGUSER || (!hasPasswordEnv && process.env.USER ? process.env.USER : (role === 'grafana' ? 'grafana_reader' : 'boat_ingest'))
  const needsPassword = !hasPasswordEnv && user !== process.env.USER
  const envFile = needsPassword ? loadEnvFile() : {}
  const password = process.env.PGPASSWORD || (user === 'grafana_reader' ? (process.env.GRAFANA_READER_PASSWORD || envFile.GRAFANA_READER_PASSWORD) : (process.env.BOAT_INGEST_PASSWORD || envFile.BOAT_INGEST_PASSWORD))
  return new pg.Pool({
    host: process.env.PGHOST || (password ? '127.0.0.1' : '/var/run/postgresql'),
    port: Number(process.env.PGPORT || 5432),
    database: process.env.PGDATABASE || 'boatdata',
    user,
    password,
    max: Number(process.env.PGPOOL_MAX || 4)
  })
}

export function splitValue(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return { value_double: value, value_text: null, value_json: null }
  if (typeof value === 'string') return { value_double: null, value_text: value, value_json: null }
  if (typeof value === 'boolean') return { value_double: value ? 1 : 0, value_text: String(value), value_json: value }
  if (value === null || value === undefined) return { value_double: null, value_text: null, value_json: null }
  return { value_double: null, value_text: null, value_json: value }
}
