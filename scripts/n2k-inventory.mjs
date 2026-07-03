#!/usr/bin/env node
import { makePool } from './db.mjs'
const pool = makePool('grafana')
const r = await pool.query(`select pgn, description, count(*) frames, array_agg(distinct src order by src) srcs,
  min(time) first_seen, max(time) last_seen
  from n2k_decoded_messages group by pgn, description order by frames desc limit $1`, [Number(process.argv[2]||80)])
for (const row of r.rows) console.log(`${row.pgn}\t${row.frames}\tsrc=${row.srcs.join(',')}\t${row.description}\t${row.first_seen?.toISOString()}\t${row.last_seen?.toISOString()}`)
await pool.end()
