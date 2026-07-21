import assert from 'node:assert/strict'
import fs from 'node:fs'
import test from 'node:test'

test('Grafana history provisioning is repository-controlled and bounded', () => {
  const dashboard = JSON.parse(fs.readFileSync('infra/pi5nvme/grafana/dashboards/boat-history.json', 'utf8'))
  assert.equal(dashboard.uid, 'boat-typed-history')
  assert.equal(dashboard.time.from, 'now-24h')
  assert.equal(dashboard.time.to, 'now')
  assert.ok(dashboard.panels.length >= 4)
  const targets = dashboard.panels.flatMap(panel => panel.targets ?? [])
  const sql = targets.map(target => target.rawSql ?? '').join('\n')
  for (const target of targets) {
    assert.match(target.rawSql, /\$__timeFilter\((?:time|started_at|event_time)\)/)
    assert.match(target.rawSql, /LIMIT \d+/)
  }
  assert.match(sql, /\$__timeFilter\(time\)/)
  assert.match(sql, /raw_log_file_id/)
  assert.match(sql, /masterbus_engine_transitions_v1/)
  assert.doesNotMatch(sql, /signal_k_measurements|boat_data_summaries/)
})
