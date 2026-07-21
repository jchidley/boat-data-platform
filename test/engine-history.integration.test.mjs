import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import { Client } from 'pg'

const requested = process.env.ENGINE_HISTORY_INTEGRATION === '1'
const migration = fs.readFileSync('infra/pi5nvme/sql/011_masterbus_engine_history_v1.sql', 'utf8')
const timestampFormat = `YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"`

function quoteIdentifier(value) {
  return `\"${value.replaceAll('"', '""')}\"`
}

function adminConfig() {
  if (process.env.ENGINE_HISTORY_TEST_ADMIN_URL) {
    const url = new URL(process.env.ENGINE_HISTORY_TEST_ADMIN_URL)
    const host = url.hostname.replace(/^\[|\]$/g, '').toLowerCase()
    if (!['localhost', '127.0.0.1', '::1'].includes(host)) {
      throw new Error('engine-history integration refuses non-local PostgreSQL targets')
    }
    return { connectionString: url.toString() }
  }
  return {
    host: process.env.ENGINE_HISTORY_TEST_SOCKET || '/var/run/postgresql',
    port: Number(process.env.PGPORT || 5432),
    user: process.env.PGUSER || os.userInfo().username,
    password: process.env.PGPASSWORD,
    database: 'postgres',
  }
}

function databaseConfig(config, database) {
  if (config.connectionString) {
    const url = new URL(config.connectionString)
    url.pathname = `/${database}`
    return { connectionString: url.toString() }
  }
  return { ...config, database }
}

function at(seconds) {
  return new Date(Date.UTC(2026, 0, 1, 0, 0, seconds))
}

const minimumSchema = `
CREATE TABLE public.masterbus_log_files_v1 (
  masterbus_log_file_id bigserial PRIMARY KEY,
  path text NOT NULL UNIQUE,
  size_bytes bigint NOT NULL,
  mtime timestamptz NOT NULL,
  sha256 text,
  import_status text NOT NULL DEFAULT 'new'
);
CREATE TABLE public.masterbus_devices_v1 (
  masterbus_device_id bigserial PRIMARY KEY,
  stable_key text NOT NULL UNIQUE
);
CREATE TABLE public.masterbus_alternator_samples_v1 (
  time timestamptz NOT NULL,
  alternator_key text NOT NULL,
  masterbus_device_id bigint REFERENCES public.masterbus_devices_v1(masterbus_device_id),
  source text NOT NULL DEFAULT 'masterbus',
  raw_log_file_id bigint REFERENCES public.masterbus_log_files_v1(masterbus_log_file_id),
  raw_line_number integer,
  sense_voltage_v double precision,
  alternator_voltage_v double precision,
  voltage_v double precision,
  current_a double precision,
  field_current_a double precision,
  alternator_temperature_k double precision,
  temperature_k double precision,
  PRIMARY KEY (time, alternator_key)
);
CREATE TABLE public.masterbus_battery_samples_v1 (
  time timestamptz NOT NULL,
  battery_key text NOT NULL,
  source text NOT NULL DEFAULT 'masterbus',
  raw_log_file_id bigint REFERENCES public.masterbus_log_files_v1(masterbus_log_file_id),
  raw_line_number integer,
  voltage_v double precision,
  current_a double precision,
  temperature_k double precision,
  PRIMARY KEY (time, battery_key)
);
`

async function insertSample(client, sample) {
  await client.query(`
    INSERT INTO public.masterbus_alternator_samples_v1 (
      time, alternator_key, source, raw_log_file_id, raw_line_number, sense_voltage_v, current_a
    ) VALUES ($1, $2, $3, $4, $5, $6, $7)
  `, [at(sample.seconds), sample.key, sample.source, sample.file, sample.line, sample.voltage, sample.current ?? null])
}

async function snapshot(client) {
  const transitions = await client.query(`
    SELECT engine_key, to_char(event_time, '${timestampFormat}') AS event_time,
           event_type, state, to_char(evidence_time, '${timestampFormat}') AS evidence_time,
           alternator_key, raw_log_file_id::text AS raw_log_file_id,
           raw_line_number::text AS raw_line_number, threshold_v::text AS threshold_v,
           debounce_seconds::text AS debounce_seconds, source
    FROM public.masterbus_engine_transitions_v1
    ORDER BY engine_key, event_time, event_type
  `)
  const intervals = await client.query(`
    SELECT engine_key, to_char(started_at, '${timestampFormat}') AS started_at,
           to_char(ended_at, '${timestampFormat}') AS ended_at,
           duration_seconds::text AS duration_seconds, end_reason,
           to_char(start_evidence_time, '${timestampFormat}') AS start_evidence_time,
           to_char(end_evidence_time, '${timestampFormat}') AS end_evidence_time,
           start_raw_log_file_id::text AS start_raw_log_file_id,
           start_raw_line_number::text AS start_raw_line_number,
           end_raw_log_file_id::text AS end_raw_log_file_id,
           end_raw_line_number::text AS end_raw_line_number, source
    FROM public.masterbus_engine_runtime_intervals_v1
    ORDER BY engine_key, started_at
  `)
  const summaries = await client.query(`
    SELECT engine_key, completed_intervals::text,
           round(completed_runtime_seconds::numeric, 6)::text AS completed_runtime_seconds,
           to_char(first_started_at, '${timestampFormat}') AS first_started_at,
           to_char(last_completed_at, '${timestampFormat}') AS last_completed_at,
           open_intervals::text
    FROM public.v_masterbus_engine_runtime_summary_v1
    ORDER BY engine_key
  `)
  return { transitions: transitions.rows, intervals: intervals.rows, summaries: summaries.rows }
}

test('rebuilds deterministic MasterBus engine history in disposable PostgreSQL', { skip: !requested && 'set ENGINE_HISTORY_INTEGRATION=1 to run disposable PostgreSQL integration tests' }, async () => {
  const started = performance.now()
  const admin = new Client(adminConfig())
  let database
  let db
  try {
    await admin.connect()
    const owner = (await admin.query('SELECT current_user')).rows[0].current_user
    database = `boat_engine_test_${process.pid}_${Math.random().toString(36).slice(2, 10)}`
    await admin.query(`CREATE DATABASE ${quoteIdentifier(database)} OWNER ${quoteIdentifier(owner)}`)

    db = new Client(databaseConfig(adminConfig(), database))
    await db.connect()
    await db.query("SET TIME ZONE 'UTC'")
    await db.query(minimumSchema)
    await db.query(migration)

    for (const [path, file] of [['native-a.jsonl', 1], ['native-b.jsonl', 2], ['native-c.jsonl', 3]]) {
      await db.query(`INSERT INTO public.masterbus_log_files_v1 (path, size_bytes, mtime, sha256) VALUES ($1, 100, $2, $3)`, [path, at(file), `sha-${file}`])
    }

    const starboard = [
      [0, 13.25, 1, 10, 'native-a'], [5, 13.30, 1, 11, 'native-a'], [8, 13.20, 1, 12, 'native-a'],
      [38, 13.25, 1, 13, 'native-a'], [60, 13.30, 1, 14, 'native-a'], [69, 13.30, 1, 15, 'native-a'],
      [70, 13.30, 2, 20, 'native-b'], [75, 13.20, 2, 21, 'native-b'], [80, 13.30, 2, 22, 'native-b'],
      [89, 13.30, 2, 23, 'native-b'], [90, 13.20, 2, 24, 'native-b'], [119, 13.20, 2, 25, 'native-b'],
      [120, 13.20, 2, 26, 'native-b'], [240, 13.20, 2, 27, 'native-b'], [270, null, 2, 28, 'native-b'],
      [361, 13.20, 2, 29, 'native-b'], [391, 13.20, 2, 30, 'native-b'], [400, 13.30, 2, 31, 'native-b'],
      [410, 13.30, 2, 32, 'native-b'], [530, 13.30, 2, 33, 'native-b'], [651, 13.30, 3, 40, 'native-c'],
      [661, 13.30, 3, 41, 'native-c'], [665, null, 3, 42, 'native-c'], [671, 13.30, 3, 43, 'native-c'],
    ]
    for (const [seconds, voltage, file, line, source] of starboard) {
      await insertSample(db, { seconds, voltage, file, line, source, key: 'alpha-stbd' })
    }

    // The typed key is (time, alternator_key): sparse same-timestamp source
    // events coalesce into one row while retaining non-null fields.
    await insertSample(db, { seconds: 700, voltage: null, current: 1, file: 3, line: 50, source: 'native-c', key: 'alpha-stbd' })
    await db.query(`
      INSERT INTO public.masterbus_alternator_samples_v1
        (time, alternator_key, source, raw_log_file_id, raw_line_number, sense_voltage_v, current_a)
      VALUES ($1, 'alpha-stbd', 'native-c', 3, 51, 13.4, NULL)
      ON CONFLICT (time, alternator_key) DO UPDATE SET
        source = EXCLUDED.source,
        raw_log_file_id = EXCLUDED.raw_log_file_id,
        raw_line_number = LEAST(public.masterbus_alternator_samples_v1.raw_line_number, EXCLUDED.raw_line_number),
        sense_voltage_v = coalesce(EXCLUDED.sense_voltage_v, public.masterbus_alternator_samples_v1.sense_voltage_v),
        current_a = coalesce(EXCLUDED.current_a, public.masterbus_alternator_samples_v1.current_a)
    `, [at(700)])

    const port = [[0, 13.0, 3, 100], [10, 13.3, 3, 101], [20, 13.3, 3, 102], [50, 13.2, 3, 103], [80, 13.2, 3, 104]]
    for (const [seconds, voltage, file, line] of port) {
      await insertSample(db, { seconds, voltage, file, line, source: 'native-c', key: 'alpha-port' })
    }

    await db.query('SELECT public.rebuild_masterbus_engine_history_v1()')

    const coalesced = (await db.query(`SELECT count(*)::text AS count, sense_voltage_v::text, current_a::text, raw_line_number::text FROM public.masterbus_alternator_samples_v1 WHERE time = $1 AND alternator_key = 'alpha-stbd' GROUP BY sense_voltage_v, current_a, raw_line_number`, [at(700)])).rows
    assert.deepEqual(coalesced, [{ count: '1', sense_voltage_v: '13.4', current_a: '1', raw_line_number: '50' }])

    const first = await snapshot(db)
    assert.equal(first.transitions.length, 7)
    assert.equal(first.intervals.length, 4)
    assert.deepEqual(first.transitions, [
      { engine_key: 'port', event_time: '2026-01-01T00:00:20.000Z', event_type: 'started', state: 'started', evidence_time: '2026-01-01T00:00:20.000Z', alternator_key: 'alpha-port', raw_log_file_id: '3', raw_line_number: '102', threshold_v: '13.25', debounce_seconds: '10', source: 'native-c' },
      { engine_key: 'port', event_time: '2026-01-01T00:01:20.000Z', event_type: 'stopped', state: 'stopped', evidence_time: '2026-01-01T00:01:20.000Z', alternator_key: 'alpha-port', raw_log_file_id: '3', raw_line_number: '104', threshold_v: '13.25', debounce_seconds: '30', source: 'native-c' },
      { engine_key: 'starboard', event_time: '2026-01-01T00:01:10.000Z', event_type: 'started', state: 'started', evidence_time: '2026-01-01T00:01:10.000Z', alternator_key: 'alpha-stbd', raw_log_file_id: '2', raw_line_number: '20', threshold_v: '13.25', debounce_seconds: '10', source: 'native-b' },
      { engine_key: 'starboard', event_time: '2026-01-01T00:02:00.000Z', event_type: 'stopped', state: 'stopped', evidence_time: '2026-01-01T00:02:00.000Z', alternator_key: 'alpha-stbd', raw_log_file_id: '2', raw_line_number: '26', threshold_v: '13.25', debounce_seconds: '30', source: 'native-b' },
      { engine_key: 'starboard', event_time: '2026-01-01T00:08:50.000Z', event_type: 'data_gap', state: 'unknown', evidence_time: '2026-01-01T00:08:50.000Z', alternator_key: 'alpha-stbd', raw_log_file_id: '2', raw_line_number: '33', threshold_v: '13.25', debounce_seconds: '0', source: 'native-b' },
      { engine_key: 'starboard', event_time: '2026-01-01T00:06:50.000Z', event_type: 'started', state: 'started', evidence_time: '2026-01-01T00:06:50.000Z', alternator_key: 'alpha-stbd', raw_log_file_id: '2', raw_line_number: '32', threshold_v: '13.25', debounce_seconds: '10', source: 'native-b' },
      { engine_key: 'starboard', event_time: '2026-01-01T00:11:01.000Z', event_type: 'started', state: 'started', evidence_time: '2026-01-01T00:11:01.000Z', alternator_key: 'alpha-stbd', raw_log_file_id: '3', raw_line_number: '41', threshold_v: '13.25', debounce_seconds: '10', source: 'native-c' },
    ].sort((a, b) => `${a.engine_key}${a.event_time}${a.event_type}`.localeCompare(`${b.engine_key}${b.event_time}${b.event_type}`)))
    assert.deepEqual(first.intervals, [
      { engine_key: 'port', started_at: '2026-01-01T00:00:20.000Z', ended_at: '2026-01-01T00:01:20.000Z', duration_seconds: '60', end_reason: 'stopped', start_evidence_time: '2026-01-01T00:00:20.000Z', end_evidence_time: '2026-01-01T00:01:20.000Z', start_raw_log_file_id: '3', start_raw_line_number: '102', end_raw_log_file_id: '3', end_raw_line_number: '104', source: 'native-c' },
      { engine_key: 'starboard', started_at: '2026-01-01T00:01:10.000Z', ended_at: '2026-01-01T00:02:00.000Z', duration_seconds: '50', end_reason: 'stopped', start_evidence_time: '2026-01-01T00:01:10.000Z', end_evidence_time: '2026-01-01T00:02:00.000Z', start_raw_log_file_id: '2', start_raw_line_number: '20', end_raw_log_file_id: '2', end_raw_line_number: '26', source: 'native-b' },
      { engine_key: 'starboard', started_at: '2026-01-01T00:06:50.000Z', ended_at: '2026-01-01T00:08:50.000Z', duration_seconds: '120', end_reason: 'data_gap', start_evidence_time: '2026-01-01T00:06:50.000Z', end_evidence_time: '2026-01-01T00:08:50.000Z', start_raw_log_file_id: '2', start_raw_line_number: '32', end_raw_log_file_id: '2', end_raw_line_number: '33', source: 'native-b' },
      { engine_key: 'starboard', started_at: '2026-01-01T00:11:01.000Z', ended_at: null, duration_seconds: null, end_reason: 'open', start_evidence_time: '2026-01-01T00:11:01.000Z', end_evidence_time: null, start_raw_log_file_id: '3', start_raw_line_number: '41', end_raw_log_file_id: null, end_raw_line_number: null, source: 'native-c' },
    ])
    assert.deepEqual(first.summaries, [
      { engine_key: 'port', completed_intervals: '1', completed_runtime_seconds: '60.000000', first_started_at: '2026-01-01T00:00:20.000Z', last_completed_at: '2026-01-01T00:01:20.000Z', open_intervals: '0' },
      { engine_key: 'starboard', completed_intervals: '2', completed_runtime_seconds: '170.000000', first_started_at: '2026-01-01T00:01:10.000Z', last_completed_at: '2026-01-01T00:08:50.000Z', open_intervals: '1' },
    ])

    // Source inventory deletion is refused while raw provenance is referenced.
    await assert.rejects(() => db.query('DELETE FROM public.masterbus_log_files_v1 WHERE masterbus_log_file_id = 1'), error => error.code === '23503')

    for (const args of [[13.25, -1, 30, 120], [13.25, 10, -1, 120], [13.25, 10, 30, 0], [null, 10, 30, 120]]) {
      await assert.rejects(() => db.query('SELECT public.rebuild_masterbus_engine_history_v1($1, $2, $3, $4)', args), /invalid engine history parameters/)
    }

    await db.query('SELECT public.rebuild_masterbus_engine_history_v1()')
    assert.deepEqual(await snapshot(db), first)
    await db.query('DELETE FROM public.masterbus_engine_runtime_intervals_v1; DELETE FROM public.masterbus_engine_transitions_v1;')
    assert.deepEqual((await db.query('SELECT count(*)::text AS count FROM public.masterbus_engine_runtime_intervals_v1')).rows, [{ count: '0' }])
    await db.query('SELECT public.rebuild_masterbus_engine_history_v1()')
    assert.deepEqual(await snapshot(db), first)

    const databaseSize = (await db.query('SELECT pg_database_size(current_database())::text AS bytes')).rows[0].bytes
    const usage = process.resourceUsage()
    console.log(`ENGINE_HISTORY_RESULT ${JSON.stringify({ transitions: first.transitions.length, intervals: first.intervals.length, summaries: first.summaries.length, completedRuntimeSeconds: 230, databaseSizeBytes: databaseSize, peakRssKiB: usage.maxRSS, elapsedMs: Math.round(performance.now() - started), timescaledb: false })}`)
  } finally {
    if (db) await db.end().catch(() => {})
    if (database) {
      await admin.query(`DROP DATABASE IF EXISTS ${quoteIdentifier(database)} WITH (FORCE)`).catch(error => console.error(`engine-history cleanup failed for ${database}: ${error.message}`))
    }
    await admin.end().catch(() => {})
  }
})
