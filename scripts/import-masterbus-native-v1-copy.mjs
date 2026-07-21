#!/usr/bin/env node
import crypto from 'node:crypto'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import readline from 'node:readline'
import zlib from 'node:zlib'
import { spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const scriptDir = path.dirname(fileURLToPath(import.meta.url))
const usage = `Usage:
  node scripts/import-masterbus-native-v1-copy.mjs --raw-file PATH [options]

Options:
  --sample-lines N      Import only the first N events (required unless --allow-full-file)
  --allow-full-file     Explicitly permit a complete settled event file
  --max-input-bytes N   Reject larger input (default 104857600)
  --max-runtime-sec N   Timeout converter/psql processes (default 300)
  --work-dir DIR        Work directory (default temporary)
  --keep-work           Keep generated work files
  --dry-run             Convert only; do not touch PostgreSQL

Offline/staging batch importer for masterbus-native-event-v1 logs. It never accesses or writes the MasterBus.
`
const args = process.argv.slice(2)
function arg(name) { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : null }
function has(name) { return args.includes(name) }
if (has('--help') || has('-h')) { console.log(usage); process.exit(0) }
const rawFile = arg('--raw-file')
const sampleLines = arg('--sample-lines') ? Number(arg('--sample-lines')) : null
const allowFullFile = has('--allow-full-file')
const maxInputBytes = Number(arg('--max-input-bytes') ?? 104857600)
const maxRuntimeSec = Number(arg('--max-runtime-sec') ?? 300)
const dryRun = has('--dry-run')
const keepWork = has('--keep-work')
const workDir = arg('--work-dir') || fs.mkdtempSync(path.join(os.tmpdir(), 'masterbus-native-copy-'))
const psqlCmd = process.env.PSQL || 'psql'
if (!rawFile || !fs.existsSync(rawFile)) { console.error(usage); process.exit(2) }
if (sampleLines !== null && (!Number.isInteger(sampleLines) || sampleLines <= 0)) throw new Error('--sample-lines must be positive')
if (sampleLines === null && !allowFullFile) throw new Error('refusing complete file without --allow-full-file')
if (!Number.isInteger(maxInputBytes) || maxInputBytes < 0 || !Number.isInteger(maxRuntimeSec) || maxRuntimeSec <= 0) throw new Error('invalid resource limit')
if (maxInputBytes && fs.statSync(rawFile).size > maxInputBytes) throw new Error('input exceeds --max-input-bytes')

function run(cmd, cmdArgs, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, cmdArgs, { stdio: options.stdio || ['ignore', 'pipe', 'pipe'] })
    const timer = setTimeout(() => child.kill('SIGKILL'), maxRuntimeSec * 1000)
    let stdout = '', stderr = ''
    child.stdout?.on('data', d => { stdout += d })
    child.stderr?.on('data', d => { stderr += d })
    child.on('error', error => { clearTimeout(timer); reject(error) })
    child.on('close', code => {
      clearTimeout(timer)
      code === 0 ? resolve({ stdout, stderr }) : reject(new Error(`${cmd} failed (${code})\n${stderr || stdout}`))
    })
  })
}
async function prepare(src, dest) {
  const input = fs.createReadStream(src)
  const stream = src.endsWith('.gz') ? input.pipe(zlib.createGunzip()) : input
  const output = fs.createWriteStream(dest)
  const rl = readline.createInterface({ input: stream })
  let count = 0
  for await (const line of rl) {
    output.write(`${line}\n`); count++
    if (sampleLines !== null && count >= sampleLines) { rl.close(); stream.destroy(); break }
  }
  await new Promise((resolve, reject) => output.end(error => error ? reject(error) : resolve()))
  return count
}
function hash(file) { return new Promise((resolve, reject) => { const h = crypto.createHash('sha256'); fs.createReadStream(file).on('data', d => h.update(d)).on('error', reject).on('end', () => resolve(h.digest('hex'))) }) }
function copy(table, file) { return `\\copy ${table} FROM '${file.replace(/'/g, "''")}' WITH (FORMAT text, DELIMITER E'\\t', NULL '\\N')` }
function psqlArgs(file) { return ['-X', '-v', 'ON_ERROR_STOP=1', '-d', process.env.PGDATABASE || 'boatdata', '-f', file] }

async function main() {
  fs.mkdirSync(workDir, { recursive: true })
  const prepared = path.join(workDir, 'input.jsonl')
  const typedDir = path.join(workDir, 'typed')
  const lineCount = await prepare(rawFile, prepared)
  if (!lineCount) throw new Error('prepared input is empty')
  const converter = path.join(scriptDir, 'masterbus-native-jsonl-to-copy.mjs')
  async function convert(id) {
    fs.rmSync(typedDir, { recursive: true, force: true }); fs.mkdirSync(typedDir, { recursive: true })
    const input = fs.openSync(prepared, 'r')
    return run(process.execPath, [converter, '--log-file-id', String(id), '--typed-dir', typedDir], { stdio: [input, 'pipe', 'pipe'] })
  }
  let result = await convert(1)
  let stats = JSON.parse(result.stderr.trim())
  if (dryRun) { console.log(JSON.stringify({ dryRun: true, rawFile, lineCount, workDir, stats }, null, 2)); return }

  const { makePool } = await import('./db.mjs')
  const pool = makePool('ingest')
  let id
  try {
    const stat = fs.statSync(prepared)
    const digest = await hash(prepared)
    const inventoryPath = sampleLines ? `${rawFile}#first-${sampleLines}` : rawFile
    const q = await pool.query(`INSERT INTO masterbus_log_files_v1(path,size_bytes,mtime,sha256,line_count,import_status,updated_at)
      VALUES($1,$2,to_timestamp($3),$4,$5,'staged',now()) ON CONFLICT(path) DO UPDATE SET
      size_bytes=EXCLUDED.size_bytes,mtime=EXCLUDED.mtime,sha256=EXCLUDED.sha256,line_count=EXCLUDED.line_count,
      import_status='staged',updated_at=now() RETURNING masterbus_log_file_id`,
    [inventoryPath, stat.size, stat.mtimeMs / 1000, digest, lineCount])
    id = q.rows[0].masterbus_log_file_id
  } finally { await pool.end() }

  result = await convert(id); stats = JSON.parse(result.stderr.trim())
  const tables = [
    ['masterbus_alternator_stage_v1', 'masterbus_alternator_stage_v1.tsv'],
    ['masterbus_battery_stage_v1', 'masterbus_battery_stage_v1.tsv'],
    ['masterbus_inverter_charger_stage_v1', 'masterbus_inverter_charger_stage_v1.tsv'],
    ['masterbus_solar_stage_v1', 'masterbus_solar_stage_v1.tsv']
  ]
  const existing = tables.filter(([, file]) => fs.existsSync(path.join(typedDir, file)) && fs.statSync(path.join(typedDir, file)).size)
  const sqlFile = path.join(workDir, 'copy-and-merge.sql')
  fs.writeFileSync(sqlFile, ['\\set ON_ERROR_STOP on', 'BEGIN;', ...tables.map(([table]) => `DELETE FROM ${table} WHERE raw_log_file_id=${id};`), ...existing.map(([table, file]) => copy(table, path.join(typedDir, file))), `SELECT masterbus_merge_staged_log_v1(${id});`, 'COMMIT;', ''].join('\n'))
  await run(psqlCmd, psqlArgs(sqlFile))
  if (!keepWork) fs.rmSync(workDir, { recursive: true, force: true })
  console.log(JSON.stringify({ imported: true, rawFile, masterbusLogFileId: id, lineCount, stats, copiedTypedTables: existing.map(([table]) => table) }, null, 2))
}
main().catch(error => { console.error(error.stack || error.message); if (!keepWork) fs.rmSync(workDir, { recursive: true, force: true }); process.exit(1) })
