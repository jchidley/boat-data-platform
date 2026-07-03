#!/usr/bin/env node
import fs from 'node:fs'
import net from 'node:net'
import path from 'node:path'
import { spawn } from 'node:child_process'

const listenPort = Number(process.env.LISTEN_PORT || 20200)
const fanoutPort = Number(process.env.FANOUT_PORT || 20201)
const destDir = process.env.DEST_DIR || '/srv/boat/raw-n2k/live'
const iface = process.env.IFACE || 'can0'
const compressor = process.env.COMPRESSOR || 'gzip'

const validCandump = /^\([0-9]+\.[0-9]+\)\s+\S+\s+[0-9A-Fa-f]+#/ 
const subscribers = new Set()
let currentSegment = null
let outStream = null
let outPath = null

fs.mkdirSync(destDir, { recursive: true })

function segmentName(date = new Date()) {
  const yyyy = String(date.getUTCFullYear())
  const mm = String(date.getUTCMonth() + 1).padStart(2, '0')
  const dd = String(date.getUTCDate()).padStart(2, '0')
  const hh = String(date.getUTCHours()).padStart(2, '0')
  return `${yyyy}${mm}${dd}T${hh}0000Z`
}

function openSegment(seg) {
  currentSegment = seg
  outPath = path.join(destDir, `${iface}-${seg}.candump.log.tmp`)
  outStream = fs.createWriteStream(outPath, { flags: 'a' })
}

function compressComplete(file) {
  if (compressor === 'none') return
  const args = compressor === 'zstd' ? ['-q', '--rm', file] : ['-n', '-f', file]
  const cmd = compressor === 'zstd' ? 'zstd' : 'gzip'
  const child = spawn(cmd, args, { stdio: 'ignore' })
  child.on('error', err => console.error(`compression failed to start for ${file}: ${err.message}`))
  child.on('exit', code => {
    if (code) console.error(`compression exited ${code} for ${file}`)
  })
}

function rotateIfNeeded() {
  const seg = segmentName()
  if (seg === currentSegment) return
  const previous = outPath
  if (outStream) outStream.end()
  if (previous && previous.endsWith('.tmp')) {
    const complete = previous.slice(0, -4)
    try {
      fs.renameSync(previous, complete)
      compressComplete(complete)
    } catch (err) {
      console.error(`failed to rotate ${previous}: ${err.message}`)
    }
  }
  openSegment(seg)
}

function broadcast(line) {
  const data = `${line}\n`
  for (const socket of [...subscribers]) {
    if (socket.destroyed) {
      subscribers.delete(socket)
      continue
    }
    socket.write(data)
  }
}

function handleLine(line) {
  if (!validCandump.test(line)) return
  rotateIfNeeded()
  outStream.write(`${line}\n`)
  broadcast(line)
}

function handlePublisher(socket) {
  console.error(`publisher connected from ${socket.remoteAddress}:${socket.remotePort}`)
  let buffer = ''
  socket.setEncoding('utf8')
  socket.on('data', chunk => {
    buffer += chunk
    let nl
    while ((nl = buffer.indexOf('\n')) >= 0) {
      let line = buffer.slice(0, nl)
      buffer = buffer.slice(nl + 1)
      if (line.endsWith('\r')) line = line.slice(0, -1)
      if (line) handleLine(line)
    }
  })
  socket.on('close', () => console.error(`publisher disconnected from ${socket.remoteAddress}:${socket.remotePort}`))
  socket.on('error', err => console.error(`publisher socket error: ${err.message}`))
}

function handleSubscriber(socket) {
  console.error(`fanout subscriber connected from ${socket.remoteAddress}:${socket.remotePort}`)
  subscribers.add(socket)
  // This is a read-only fanout. Discard any client writes so Signal K/canboat
  // output events can never be forwarded back to the NMEA 2000 acquisition edge.
  socket.on('data', () => {})
  socket.on('close', () => {
    subscribers.delete(socket)
    console.error(`fanout subscriber disconnected from ${socket.remoteAddress}:${socket.remotePort}`)
  })
  socket.on('error', err => {
    subscribers.delete(socket)
    console.error(`fanout subscriber socket error: ${err.message}`)
  })
}

openSegment(segmentName())

net.createServer(handlePublisher).listen(listenPort, '0.0.0.0', () => {
  console.error(`raw N2K receiver listening on 0.0.0.0:${listenPort}, writing ${destDir}`)
})

net.createServer(handleSubscriber).listen(fanoutPort, '127.0.0.1', () => {
  console.error(`raw N2K candump fanout listening on 127.0.0.1:${fanoutPort}`)
})

process.on('SIGTERM', () => {
  for (const socket of subscribers) socket.destroy()
  if (outStream) outStream.end(() => process.exit(0))
  else process.exit(0)
})
