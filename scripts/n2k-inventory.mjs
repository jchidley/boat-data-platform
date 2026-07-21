#!/usr/bin/env node
import { makePool } from './db.mjs'
const pool = makePool('grafana')
const r = await pool.query(`select pgn, description, frames, sources,
  first_seen, last_seen
  from v_pgn_catalog_seen order by frames desc limit $1`, [Number(process.argv[2]||80)])
for (const row of r.rows) console.log(`${row.pgn}\t${row.frames}\tsrc=${(row.sources || []).join(',')}\t${row.description || ''}\t${row.first_seen?.toISOString()}\t${row.last_seen?.toISOString()}`)
await pool.end()
