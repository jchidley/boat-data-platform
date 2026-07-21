#!/usr/bin/env node
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import readline from 'node:readline'
import zlib from 'node:zlib'
import crypto from 'node:crypto'
import { spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const scriptDir = path.dirname(fileURLToPath(import.meta.url))

const usage = `Usage:
  node scripts/import-n2k-v2-copy.mjs --raw-file PATH [options]

Options:
  --raw-file PATH       Raw candump log (.log, .tmp, or .gz) to import/stage
  --work-dir DIR        Work directory for analyzer JSONL/TSV files (default: temp dir)
  --sample-lines N      Copy only the first N candump lines (required unless --allow-full-file)
  --allow-full-file     Explicitly permit a complete file import
  --max-input-bytes N   Reject larger source files (default: 104857600; 0 disables)
  --max-lines N         Reject larger prepared samples (default: 100000)
  --max-runtime-sec N   Timeout for each analyzer/psql process (default: 300)
  --max-memory-mb N     RSS planning limit (default: 512)
  --max-workspace-bytes N  Reject work files above limit (default: 1073741824)
  --min-free-disk-bytes N  Require free space before/after work (default: 1073741824)
  --research-mode MODE  none (default), untyped, or selected
  --research-pgn LIST   Comma-separated PGNs required with selected research mode
  --decoder MODE        js (default) or rust; rust emits typed TSV directly
  --analyzer CMD        analyzerjs command/path (default: ANALYZERJS or common Signal K path)
  --rust-importer CMD   Rust importer binary (default: tools/n2k-rust-importer/target/release/n2k-rust-importer)
  --psql CMD            psql command/path (default: psql)
  --keep-work           Keep generated work directory
  --dry-run             Prepare/analyze/convert only; do not touch PostgreSQL
  --help                Show this help

This is the safe v2 relational/COPY path for offline/staging validation.
It is not approved for broad live-host import.
`

const args = process.argv.slice(2)
function arg(name) { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : null }
function has(name) { return args.includes(name) }
if (has('--help') || has('-h')) { console.log(usage); process.exit(0) }

const rawFile = arg('--raw-file')
const sampleLines = arg('--sample-lines') ? Number(arg('--sample-lines')) : null
const allowFullFile = has('--allow-full-file')
const maxInputBytes = Number(arg('--max-input-bytes') ?? process.env.N2K_IMPORT_MAX_INPUT_BYTES ?? 104857600)
const maxLines = Number(arg('--max-lines') ?? 100000)
const maxRuntimeSec = Number(arg('--max-runtime-sec') ?? process.env.N2K_IMPORT_MAX_RUNTIME_SEC ?? 300)
const maxMemoryMb = Number(arg('--max-memory-mb') ?? 512)
const maxWorkspaceBytes = Number(arg('--max-workspace-bytes') ?? 1073741824)
const minFreeDiskBytes = Number(arg('--min-free-disk-bytes') ?? 1073741824)
const researchMode = arg('--research-mode') || 'none'
const researchPgn = arg('--research-pgn')
const decoder = arg('--decoder') || 'js'
const keepWork = has('--keep-work')
const dryRun = has('--dry-run')
const psqlCmd = arg('--psql') || process.env.PSQL || 'psql'
const analyzerCmd = arg('--analyzer') || process.env.ANALYZERJS || '/usr/lib/node_modules/signalk-server/node_modules/@canboat/canboatjs/dist/bin/analyzerjs.js'
const rustImporterCmd = arg('--rust-importer') || process.env.N2K_RUST_IMPORTER || path.resolve(scriptDir, '../tools/n2k-rust-importer/target/release/n2k-rust-importer')
const workDir = arg('--work-dir') || fs.mkdtempSync(path.join(os.tmpdir(), 'n2k-v2-copy-'))

if (!rawFile) { console.error(usage); process.exit(2) }
if (sampleLines !== null && (!Number.isInteger(sampleLines) || sampleLines <= 0)) {
  console.error('--sample-lines must be a positive integer')
  process.exit(2)
}
if (sampleLines === null && !allowFullFile) {
  console.error('refusing a complete import without --allow-full-file; use --sample-lines for validation')
  process.exit(2)
}
if (![maxInputBytes, maxLines, maxRuntimeSec, maxMemoryMb, maxWorkspaceBytes, minFreeDiskBytes].every(Number.isInteger)
  || maxInputBytes < 0 || maxLines <= 0 || maxRuntimeSec <= 0 || maxMemoryMb <= 0 || maxWorkspaceBytes <= 0 || minFreeDiskBytes < 0) {
  console.error('--max-input-bytes must be non-negative and resource limits must be positive (except min free disk)')
  process.exit(2)
}
if (!['none', 'untyped', 'selected'].includes(researchMode) || (researchMode === 'selected' && !researchPgn)) {
  console.error('--research-mode must be none, untyped, or selected; selected requires --research-pgn')
  process.exit(2)
}
if (!['js', 'rust'].includes(decoder)) {
  console.error('--decoder must be js or rust')
  process.exit(2)
}
if (decoder === 'rust' && researchMode !== 'none') {
  console.error('the incremental Rust importer currently supports --research-mode none only')
  process.exit(2)
}
if (!fs.existsSync(rawFile)) {
  console.error(`raw file not found: ${rawFile}`)
  process.exit(2)
}
const rawStat = fs.statSync(rawFile)
const sourceSize = rawStat.size
if (maxInputBytes > 0 && sourceSize > maxInputBytes) {
  console.error(`source file is ${sourceSize} bytes, above --max-input-bytes ${maxInputBytes}`)
  process.exit(2)
}

const typedTables = [
  ['n2k_position_rapid_129025_stage_v2', 'n2k_position_rapid_129025_stage_v2.tsv'],
  ['n2k_cog_sog_129026_stage_v2', 'n2k_cog_sog_129026_stage_v2.tsv'],
  ['n2k_gnss_position_129029_stage_v2', 'n2k_gnss_position_129029_stage_v2.tsv'],
  ['n2k_heading_127250_stage_v2', 'n2k_heading_127250_stage_v2.tsv'],
  ['n2k_rudder_127245_stage_v2', 'n2k_rudder_127245_stage_v2.tsv'],
  ['n2k_heading_track_control_127237_stage_v2', 'n2k_heading_track_control_127237_stage_v2.tsv'],
  ['n2k_rate_of_turn_127251_stage_v2', 'n2k_rate_of_turn_127251_stage_v2.tsv'],
  ['n2k_switch_bank_status_127501_stage_v2', 'n2k_switch_bank_status_127501_stage_v2.tsv'],
  ['n2k_attitude_127257_stage_v2', 'n2k_attitude_127257_stage_v2.tsv'],
  ['n2k_magnetic_variation_127258_stage_v2', 'n2k_magnetic_variation_127258_stage_v2.tsv'],
  ['n2k_water_speed_128259_stage_v2', 'n2k_water_speed_128259_stage_v2.tsv'],
  ['n2k_water_depth_128267_stage_v2', 'n2k_water_depth_128267_stage_v2.tsv'],
  ['n2k_distance_log_128275_stage_v2', 'n2k_distance_log_128275_stage_v2.tsv'],
  ['n2k_navigation_data_129284_stage_v2', 'n2k_navigation_data_129284_stage_v2.tsv'],
  ['n2k_route_waypoint_129285_stage_v2', 'n2k_route_waypoint_129285_stage_v2.tsv'],
  ['n2k_ais_class_a_position_129038_stage_v2', 'n2k_ais_class_a_position_129038_stage_v2.tsv'],
  ['n2k_ais_class_b_position_129039_stage_v2', 'n2k_ais_class_b_position_129039_stage_v2.tsv'],
  ['n2k_ais_class_a_static_129794_stage_v2', 'n2k_ais_class_a_static_129794_stage_v2.tsv'],
  ['n2k_ais_class_b_static_a_129809_stage_v2', 'n2k_ais_class_b_static_a_129809_stage_v2.tsv'],
  ['n2k_ais_class_b_static_b_129810_stage_v2', 'n2k_ais_class_b_static_b_129810_stage_v2.tsv'],
  ['n2k_gnss_dops_129539_stage_v2', 'n2k_gnss_dops_129539_stage_v2.tsv'],
  ['n2k_gnss_satellites_129540_stage_v2', 'n2k_gnss_satellites_129540_stage_v2.tsv'],
  ['n2k_wind_130306_stage_v2', 'n2k_wind_130306_stage_v2.tsv'],
  ['n2k_environment_130310_stage_v2', 'n2k_environment_130310_stage_v2.tsv'],
  ['n2k_environment_130311_stage_v2', 'n2k_environment_130311_stage_v2.tsv'],
  ['n2k_temperature_130312_stage_v2', 'n2k_temperature_130312_stage_v2.tsv'],
  ['n2k_pressure_130314_stage_v2', 'n2k_pressure_130314_stage_v2.tsv'],
  ['n2k_temperature_ext_130316_stage_v2', 'n2k_temperature_ext_130316_stage_v2.tsv']
]
const stageTables = ['n2k_frames_stage_v2', 'n2k_research_fields_stage_v2', ...typedTables.map(t => t[0])]

function workspaceBytes(dir) {
  let total = 0
  if (!fs.existsSync(dir)) return total
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const target = path.join(dir, entry.name)
    total += entry.isDirectory() ? workspaceBytes(target) : (entry.isFile() ? fs.statSync(target).size : 0)
  }
  return total
}
function freeDiskBytes(dir) {
  const stat = fs.statfsSync(dir)
  return Number(stat.bavail) * Number(stat.bsize)
}
function enforceLimits(stage) {
  if (process.memoryUsage().rss > maxMemoryMb * 1024 * 1024) throw new Error(`${stage}: RSS exceeds --max-memory-mb`)
  if (workspaceBytes(workDir) > maxWorkspaceBytes) throw new Error(`${stage}: workspace exceeds --max-workspace-bytes`)
  if (freeDiskBytes(workDir) < minFreeDiskBytes) throw new Error(`${stage}: free disk below --min-free-disk-bytes`)
}

function run(cmd, cmdArgs, opts = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, cmdArgs, { stdio: opts.stdio || ['ignore', 'pipe', 'pipe'], env: opts.env || process.env })
    const timer = setTimeout(() => child.kill('SIGKILL'), maxRuntimeSec * 1000)
    let stdout = '', stderr = ''
    child.stdout?.on('data', d => { stdout += d })
    child.stderr?.on('data', d => { stderr += d })
    child.on('error', err => { clearTimeout(timer); reject(err) })
    child.on('close', code => {
      clearTimeout(timer)
      if (code === 0) resolve({ stdout, stderr })
      else reject(new Error(`${cmd} ${cmdArgs.join(' ')} failed with ${code}\n${stderr || stdout}`))
    })
  })
}

async function copyPossiblyGz(src, dest, sampleLimit = null) {
  fs.mkdirSync(path.dirname(dest), { recursive: true })
  const input = fs.createReadStream(src)
  const stream = src.endsWith('.gz') ? input.pipe(zlib.createGunzip()) : input
  const output = fs.createWriteStream(dest, { encoding: 'utf8' })
  const rl = readline.createInterface({ input: stream })
  let lines = 0
  for await (const line of rl) {
    lines++
    if (lines > maxLines) throw new Error('prepared input exceeds --max-lines')
    output.write(line + '\n')
    if (sampleLimit !== null && lines >= sampleLimit) {
      rl.close()
      stream.destroy?.()
      break
    }
  }
  await new Promise((resolve, reject) => output.end(err => err ? reject(err) : resolve()))
}

function sha256File(file) {
  return new Promise((resolve, reject) => {
    const h = crypto.createHash('sha256')
    fs.createReadStream(file).on('data', d => h.update(d)).on('error', reject).on('end', () => resolve(h.digest('hex')))
  })
}

function psqlDsnArgs() {
  const dsn = process.env.DATABASE_URL || process.env.PGDATABASE
  return dsn ? ['-d', dsn] : ['-d', 'boatdata']
}

function copyCommand(table, file) {
  return `\\copy ${table} FROM '${file.replace(/'/g, "''")}' WITH (FORMAT text, DELIMITER E'\\t', NULL '\\N')`
}

function analyzerInvocation() {
  if (analyzerCmd.endsWith('.js') || analyzerCmd.includes('/')) return [process.execPath, [analyzerCmd]]
  return [analyzerCmd, []]
}

async function main() {
  fs.mkdirSync(workDir, { recursive: true })
  const startedAt = Date.now()
  enforceLimits('start')
  const preparedRaw = path.join(workDir, 'input.candump.log')
  const analyzerJsonl = path.join(workDir, 'analyzer.jsonl')
  const framesTsv = path.join(workDir, 'frames.tsv')
  const fieldsTsv = path.join(workDir, 'fields.tsv')
  const typedDir = path.join(workDir, 'typed')
  fs.mkdirSync(typedDir, { recursive: true })

  await copyPossiblyGz(rawFile, preparedRaw, sampleLines)
  const preparedStat = fs.statSync(preparedRaw)
  if (preparedStat.size === 0) throw new Error('prepared raw sample is empty')
  enforceLimits('after-prepare')

  const converter = path.join(scriptDir, 'analyzer-jsonl-to-n2k-copy.mjs')
  const converterArgs = id => [converter, '--log-file-id', String(id), '--frames-tsv', framesTsv, '--fields-tsv', fieldsTsv, '--typed-dir', typedDir, '--research-mode', researchMode, ...(researchPgn ? ['--research-pgn', researchPgn] : [])]

  if (decoder === 'js') {
    const [analyzerExe, analyzerPrefixArgs] = analyzerInvocation()
    await run(analyzerExe, [...analyzerPrefixArgs, '--file', preparedRaw], { stdio: ['ignore', fs.openSync(analyzerJsonl, 'w'), 'pipe'] })
  } else if (!fs.existsSync(rustImporterCmd)) {
    throw new Error(`Rust importer not found: ${rustImporterCmd}; build it with cargo build --release --manifest-path tools/n2k-rust-importer/Cargo.toml`)
  }

  async function convert(id) {
    if (decoder === 'rust') {
      const result = await run(rustImporterCmd, ['--raw-file', preparedRaw, '--log-file-id', String(id), '--frames-tsv', framesTsv, '--fields-tsv', fieldsTsv, '--typed-dir', typedDir])
      return result.stderr.trim()
    }
    return await new Promise((resolve, reject) => {
      const input = fs.openSync(analyzerJsonl, 'r')
      const child = spawn(process.execPath, converterArgs(id), { stdio: [input, 'pipe', 'pipe'] })
      let stderr = ''
      child.stderr.on('data', d => { stderr += d })
      child.on('error', reject)
      child.on('close', code => code === 0 ? resolve(stderr.trim()) : reject(new Error(`converter failed with ${code}\n${stderr}`)))
    })
  }

  const conv = await convert(1)
  enforceLimits('after-convert')
  let convertStats = {}
  try { convertStats = JSON.parse(conv) } catch { convertStats = { raw: conv } }

  if (dryRun) {
    console.log(JSON.stringify({ dryRun: true, rawFile, preparedRaw, workDir, convertStats, resourceLimits: { maxInputBytes, maxLines, maxRuntimeSec, maxMemoryMb, maxWorkspaceBytes, minFreeDiskBytes }, workspaceBytes: workspaceBytes(workDir), freeDiskBytes: freeDiskBytes(workDir), elapsedMs: Date.now() - startedAt, maxRssKb: process.resourceUsage().maxRSS }, null, 2))
    return
  }

  const sourceSha256 = await sha256File(rawFile)
  const { makePool } = await import('./db.mjs')
  const pool = makePool('ingest')
  let rawFileId
  try {
    const inv = await pool.query(`
      INSERT INTO n2k_raw_files_v2(path, size_bytes, mtime, sha256, import_status, updated_at)
      VALUES ($1, $2, to_timestamp($3), $4, 'staged', now())
      ON CONFLICT (path) DO UPDATE SET
        size_bytes = EXCLUDED.size_bytes,
        mtime = EXCLUDED.mtime,
        sha256 = EXCLUDED.sha256,
        import_status = 'staged',
        error_summary = NULL,
        updated_at = now()
      RETURNING raw_file_id
    `, [sampleLines ? `${rawFile}#first-${sampleLines}` : rawFile, sourceSize, rawStat.mtimeMs / 1000, sourceSha256])
    rawFileId = inv.rows[0].raw_file_id
  } finally {
    await pool.end()
  }

  // Re-run conversion with the real raw_file_id embedded in TSV.
  fs.rmSync(framesTsv, { force: true })
  fs.rmSync(fieldsTsv, { force: true })
  fs.rmSync(typedDir, { recursive: true, force: true })
  fs.mkdirSync(typedDir, { recursive: true })
  const conv2 = await convert(rawFileId)
  try { convertStats = JSON.parse(conv2) } catch { convertStats = { raw: conv2 } }

  const copySqlPath = path.join(workDir, 'copy-and-merge.sql')
  const existingTyped = typedTables
    .map(([table, file]) => [table, path.join(typedDir, file)])
    .filter(([, file]) => fs.existsSync(file) && fs.statSync(file).size > 0)
  const sql = [
    '\\set ON_ERROR_STOP on',
    'BEGIN;',
    ...stageTables.map(table => `DELETE FROM ${table} WHERE raw_file_id = ${rawFileId};`),
    copyCommand('n2k_frames_stage_v2', framesTsv),
    ...(fs.statSync(fieldsTsv).size > 0 ? [copyCommand('n2k_research_fields_stage_v2', fieldsTsv)] : []),
    ...existingTyped.map(([table, file]) => copyCommand(table, file)),
    `SELECT n2k_merge_staged_file_v2(${rawFileId});`,
    'COMMIT;',
    ''
  ].join('\n')
  fs.writeFileSync(copySqlPath, sql)
  const psql = await run(psqlCmd, [...psqlDsnArgs(), '-X', '-v', 'ON_ERROR_STOP=1', '-f', copySqlPath])

  enforceLimits('after-merge')
  if (!keepWork) fs.rmSync(workDir, { recursive: true, force: true })

  console.log(JSON.stringify({
    imported: true,
    rawFile,
    rawFileId,
    sampleLines,
    sourceSha256,
    sourceSizeBytes: sourceSize,
    preparedSizeBytes: preparedStat.size,
    convertStats,
    resourceLimits: { maxInputBytes, maxLines, maxRuntimeSec, maxMemoryMb, maxWorkspaceBytes, minFreeDiskBytes },
    workspaceBytes: workspaceBytes(workDir),
    freeDiskBytes: freeDiskBytes(workDir),
    elapsedMs: Date.now() - startedAt,
    maxRssKb: process.resourceUsage().maxRSS,
    copiedTypedTables: existingTyped.map(([table]) => table),
    psqlStdout: psql.stdout.trim()
  }, null, 2))
}

main().catch(err => {
  console.error(err.stack || err.message)
  if (!keepWork) {
    try { fs.rmSync(workDir, { recursive: true, force: true }) } catch {}
  }
  process.exit(1)
})
