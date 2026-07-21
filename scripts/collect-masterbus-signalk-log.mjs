#!/usr/bin/env node
import fs from 'node:fs'
import path from 'node:path'
import WebSocket from 'ws'

const url = process.env.SIGNALK_WS_URL || 'ws://127.0.0.1:3001/signalk/v1/stream?subscribe=none'
const logDir = process.env.MASTERBUS_LOG_DIR || '/srv/boat/masterbus/signalk-jsonl'
const flushMs = Number(process.env.FLUSH_MS || 1000)
let stream = null
let currentHour = null
let shuttingDown = false
let buffered = 0
let ws

fs.mkdirSync(logDir, { recursive: true })

function hourStamp(d = new Date()) {
  const iso = d.toISOString()
  return `${iso.slice(0, 13).replace(/[-:]/g, '')}0000Z`
}

function openStream(now = new Date()) {
  const hour = hourStamp(now)
  if (stream && currentHour === hour) return stream
  if (stream) stream.end()
  currentHour = hour
  const file = path.join(logDir, `masterbus-signalk-${hour}.jsonl`)
  stream = fs.createWriteStream(file, { flags: 'a', encoding: 'utf8' })
  console.error(`logging MasterBus Signal K deltas to ${file}`)
  return stream
}

function updateSource(update) {
  return update?.$source || update?.source?.label || update?.source?.src || null
}

function isMasterbusDelta(delta) {
  for (const update of delta?.updates || []) {
    const source = updateSource(update)
    if (source === 'masterbus' || String(source).startsWith('masterbus.')) return true
  }
  return false
}

function writeDelta(delta) {
  if (!isMasterbusDelta(delta)) return
  const receivedAt = new Date()
  openStream(receivedAt).write(JSON.stringify({ receivedAt: receivedAt.toISOString(), delta }) + '\n')
  buffered++
}

function connect() {
  ws = new WebSocket(url)
  ws.on('open', () => {
    console.error(`connected ${url}`)
    ws.send(JSON.stringify({ context: 'vessels.self', subscribe: [{ path: '*', period: 1000 }] }))
  })
  ws.on('message', data => {
    try { writeDelta(JSON.parse(data.toString())) } catch (e) { console.error(`bad message: ${e.message}`) }
  })
  ws.on('close', () => {
    console.error('websocket closed')
    if (!shuttingDown) setTimeout(connect, 5000)
  })
  ws.on('error', e => console.error(`websocket error: ${e.message}`))
}

setInterval(() => {
  if (stream) stream.write('', () => {})
  if (buffered) {
    console.error(`masterbus log lines written=${buffered}`)
    buffered = 0
  }
}, flushMs)

async function shutdown() {
  shuttingDown = true
  try { ws?.close() } catch {}
  await new Promise(resolve => stream ? stream.end(resolve) : resolve())
}
process.on('SIGTERM', () => shutdown().finally(() => process.exit(0)))
process.on('SIGINT', () => shutdown().finally(() => process.exit(0)))
connect()
