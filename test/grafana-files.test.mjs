import assert from 'node:assert/strict'
import fs from 'node:fs'
import test from 'node:test'

test('Grafana history provisioning is repository-controlled and bounded', () => {
  const dashboard = JSON.parse(fs.readFileSync('infra/pi5nvme/grafana/dashboards/boat-history.json', 'utf8'))
  assert.equal(dashboard.uid, 'boat-typed-history')
  assert.equal(dashboard.time.from, 'now-30d')
  assert.equal(dashboard.time.to, 'now')
  assert.ok(dashboard.panels.length >= 5)
  const targets = dashboard.panels.flatMap(panel => panel.targets ?? [])
  const sql = targets.map(target => target.rawSql ?? '').join('\n')
  for (const target of targets) {
    assert.match(target.rawSql ?? '', /\$__timeFilter\((?:time|started_at|event_time)\)/)
    assert.match(target.rawSql ?? '', /LIMIT \d+/)
  }

  const completedRuntime = dashboard.panels.find(panel => panel.title === 'Completed runtime — closed intervals only')
  assert.ok(completedRuntime)
  const completedSql = completedRuntime.targets[0].rawSql
  assert.match(completedSql, /VALUES \('port'::text\), \('starboard'::text\)/)
  assert.match(completedSql, /coalesce\(/i)
  assert.match(completedSql, /end_reason <> 'open'/)
  assert.doesNotMatch(completedSql, /extract\(epoch FROM now\(\)/i)

  const openIntervals = dashboard.panels.find(panel => panel.title === 'Open engine intervals')
  assert.ok(openIntervals)
  const openSql = openIntervals.targets[0].rawSql
  assert.match(openSql, /end_reason = 'open'/)
  assert.match(openSql, /start_evidence_time/)
  assert.match(openSql, /start_raw_log_file_id/)

  assert.match(sql, /\$__timeFilter\(time\)/)
  assert.match(sql, /raw_log_file_id/)
  assert.match(sql, /masterbus_engine_transitions_v1/)
  assert.doesNotMatch(sql, /signal_k_measurements|boat_data_summaries/)
})
