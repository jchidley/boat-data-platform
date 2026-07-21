import assert from 'node:assert/strict'
import fs from 'node:fs'
import test from 'node:test'

test('Grafana history provisioning is repository-controlled and bounded', () => {
  const dashboard = JSON.parse(fs.readFileSync('infra/pi5nvme/grafana/dashboards/boat-history.json', 'utf8'))
  assert.equal(dashboard.uid, 'boat-typed-history')
  assert.ok(dashboard.panels.length >= 4)
  const sql = dashboard.panels.flatMap(panel => panel.targets ?? []).map(target => target.rawSql ?? '').join('\n')
  assert.match(sql, /\$__timeFilter\(time\)/)
  assert.match(sql, /LIMIT 10000|LIMIT 200/)
  assert.match(sql, /raw_log_file_id/)
  assert.match(sql, /masterbus_engine_transitions_v1/)
  assert.doesNotMatch(sql, /signal_k_measurements|boat_data_summaries/)
})
