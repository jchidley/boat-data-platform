#!/usr/bin/env node
import WebSocket from 'ws'
import { makePool, splitValue } from './db.mjs'

const url = process.env.SIGNALK_WS_URL || 'ws://127.0.0.1:3001/signalk/v1/stream?subscribe=none'
const pool = makePool('ingest')
const flushMs = Number(process.env.FLUSH_MS || 1000)
const maxBatch = Number(process.env.MAX_BATCH || 500)
let batch = []
let shuttingDown = false
let ws

function enqueue(delta) {
  const context = delta.context || 'vessels.self'
  for (const update of delta.updates || []) {
    const timestamp = update.timestamp || delta.timestamp || new Date().toISOString()
    const source = update.$source || update.source?.label || update.source?.src || null
    const pgn = update.source?.pgn ?? update.pgn ?? null
    for (const pv of update.values || []) {
      const sv = splitValue(pv.value)
      batch.push({ time: timestamp, path: pv.path, source: source == null ? null : String(source), pgn, ...sv, raw: { context, updateSource: update.source ?? null } })
    }
  }
}

async function flush() {
  if (batch.length === 0) return
  const rows = batch.splice(0, maxBatch)
  const values = []
  const ph = rows.map((r, i) => {
    const base = i * 7
    values.push(r.time, r.path, r.source, r.pgn, r.value_double, r.value_text, r.value_json ?? r.raw)
    return `($${base + 1},$${base + 2},$${base + 3},$${base + 4},$${base + 5},$${base + 6},$${base + 7})`
  }).join(',')
  await pool.query(`INSERT INTO signal_k_measurements
    (time,path,source,pgn,value_double,value_text,value_json)
    VALUES ${ph}`, values)
}

function connect() {
  ws = new WebSocket(url)
  ws.on('open', () => {
    console.error(`connected ${url}`)
    ws.send(JSON.stringify({ context: 'vessels.self', subscribe: [{ path: '*', period: 1000 }] }))
  })
  ws.on('message', (data) => {
    try { enqueue(JSON.parse(data.toString())) } catch (e) { console.error(`bad message: ${e.message}`) }
  })
  ws.on('close', () => {
    console.error('websocket closed')
    if (!shuttingDown) setTimeout(connect, 5000)
  })
  ws.on('error', (e) => console.error(`websocket error: ${e.message}`))
}

setInterval(() => flush().catch(e => console.error(`flush failed: ${e.stack || e}`)), flushMs)
process.on('SIGTERM', async () => { shuttingDown = true; try { ws?.close(); await flush(); await pool.end() } finally { process.exit(0) } })
process.on('SIGINT', async () => { shuttingDown = true; try { ws?.close(); await flush(); await pool.end() } finally { process.exit(0) } })
connect()
