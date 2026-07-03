#!/usr/bin/env node
import fs from 'node:fs'
import path from 'node:path'
import { spawn } from 'node:child_process'
import readline from 'node:readline'
import crypto from 'node:crypto'

const rawDir = process.env.RAW_N2K_DIR || '/srv/boat/raw-n2k'
const analyzer = process.env.ANALYZERJS || '/usr/lib/node_modules/signalk-server/node_modules/@canboat/canboatjs/dist/bin/analyzerjs.js'
const node = process.env.NODE || 'node'
const limit = Number(process.env.LIMIT_FILES || process.argv[2] || 0)
const tmpDir = process.env.TMPDIR || '/tmp'
const approved = process.env.ALLOW_RAW_N2K_IMPORT === '1' || process.argv.includes('--yes-really-import')

if (!approved) {
  console.error('Refusing to run raw N2K import: set ALLOW_RAW_N2K_IMPORT=1 or pass --yes-really-import after confirming host resources and approval.')
  process.exit(2)
}

const { makePool } = await import('./db.mjs')
const pool = makePool('ingest')

async function alreadyDone(file, st) {
  const r = await pool.query('select processed_at from raw_n2k_log_files where path=$1 and size_bytes=$2 and mtime=$3', [file, st.size, st.mtime])
  return r.rows[0]?.processed_at
}

async function sha256File(file) {
  const h = crypto.createHash('sha256')
  await new Promise((resolve, reject) => {
    const s = fs.createReadStream(file)
    s.on('data', chunk => h.update(chunk))
    s.on('error', reject)
    s.on('end', resolve)
  })
  return h.digest('hex')
}

async function markSeen(file, st, processed = false, meta = {}) {
  await pool.query(`insert into raw_n2k_log_files(path,size_bytes,mtime,processed_at,sha256,first_edge_time,last_edge_time,frame_count,updated_at)
    values($1,$2,$3,$4,$5,$6,$7,$8,now())
    on conflict(path) do update set
      size_bytes=excluded.size_bytes,
      mtime=excluded.mtime,
      processed_at=coalesce(excluded.processed_at, raw_n2k_log_files.processed_at),
      sha256=coalesce(excluded.sha256, raw_n2k_log_files.sha256),
      first_edge_time=coalesce(excluded.first_edge_time, raw_n2k_log_files.first_edge_time),
      last_edge_time=coalesce(excluded.last_edge_time, raw_n2k_log_files.last_edge_time),
      frame_count=coalesce(excluded.frame_count, raw_n2k_log_files.frame_count),
      updated_at=now()`,
    [file, st.size, st.mtime, processed ? new Date() : null, meta.sha256 ?? null, meta.firstEdgeTime ?? null, meta.lastEdgeTime ?? null, meta.frameCount ?? null])
}

async function insertRows(rows) {
  if (!rows.length) return
  const vals=[]
  const ph=rows.map((r,i)=>{const b=i*11; vals.push(r.log_path,r.message_index,r.time,r.pgn,r.prio,r.src,r.dst,r.description,r.id,r.fields,r.raw); return `($${b+1},$${b+2},$${b+3},$${b+4},$${b+5},$${b+6},$${b+7},$${b+8},$${b+9},$${b+10},$${b+11})`}).join(',')
  await pool.query(`insert into n2k_decoded_messages(log_path,message_index,time,pgn,prio,src,dst,description,decoder_id,fields,raw)
    values ${ph} on conflict(log_path,message_index) do nothing`, vals)
}

async function importFile(file) {
  const st = fs.statSync(file)
  if (await alreadyDone(file, st)) return { file, skipped: true }
  const sha256 = await sha256File(file)
  await markSeen(file, st, false, { sha256 })
  const temp = path.join(tmpDir, `boat-n2k-${process.pid}-${path.basename(file, '.gz')}`)
  await new Promise((resolve, reject) => {
    const out = fs.createWriteStream(temp)
    const gz = spawn('gzip', ['-dc', file])
    gz.stdout.pipe(out)
    gz.stderr.pipe(process.stderr)
    gz.on('error', reject)
    out.on('error', reject)
    out.on('finish', resolve)
    gz.on('close', code => { if (code !== 0) reject(new Error(`gzip exited ${code}`)) })
  })
  const an = spawn(node, [analyzer, '--file', temp, '--show-non-matches', '--include-raw-data'])
  const analyzerClosed = new Promise((res, rej) => an.on('close', code => code === 0 ? res() : rej(new Error(`analyzer exited ${code}`))))
  an.stderr.pipe(process.stderr)
  const rl = readline.createInterface({ input: an.stdout })
  let idx=0, inserted=0, batch=[], firstEdgeTime=null, lastEdgeTime=null
  for await (const line of rl) {
    if (!line.trim().startsWith('{')) continue
    let msg
    try { msg = JSON.parse(line) } catch { continue }
    const edgeTime = msg.timestamp || null
    if (edgeTime && !firstEdgeTime) firstEdgeTime = edgeTime
    if (edgeTime) lastEdgeTime = edgeTime
    batch.push({ log_path:file, message_index:idx++, time:edgeTime, pgn:msg.pgn, prio:msg.prio ?? null, src:msg.src ?? null, dst:msg.dst ?? null, description:msg.description ?? null, id:msg.id ?? null, fields:msg.fields ?? null, raw:msg })
    if (batch.length >= 500) { await insertRows(batch); inserted += batch.length; batch=[] }
  }
  if (batch.length) { await insertRows(batch); inserted += batch.length }
  await analyzerClosed
  fs.rmSync(temp, { force: true })
  await markSeen(file, st, true, { sha256, firstEdgeTime, lastEdgeTime, frameCount: idx })
  return { file, inserted }
}

function findRawLogs(dir) {
  const out = []
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name)
    if (ent.isDirectory()) out.push(...findRawLogs(p))
    else if (ent.isFile() && p.endsWith('.candump.log.gz')) out.push(p)
  }
  return out.sort()
}

try {
  const files = findRawLogs(rawDir)
  let done=0
  for (const f of files) {
    if (limit && done >= limit) break
    const r = await importFile(f)
    console.error(`${r.skipped?'skipped':'imported'} ${f} ${r.inserted ?? ''}`)
    if (!r.skipped) done++
  }
} finally { await pool.end() }
