import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'

const converter = path.resolve('scripts/masterbus-native-jsonl-to-copy.mjs')
const importer = path.resolve('scripts/import-masterbus-native-v1-copy.mjs')
function event(overrides) {
  return JSON.stringify({ schema: 'masterbus-native-event-v1', observedAt: '2026-07-21T07:19:09.090Z', device: '33AC6A', field: 7, class: 'Alpha', instance: 'alpha-stbd', group: 'alternator', name: 'Sense voltage', unit: 'V', value: { Float: 13.793 }, ...overrides })
}

test('converts native decoded MasterBus events without Signal K paths', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'masterbus-native-test-'))
  const typedDir = path.join(dir, 'typed')
  const input = [
    event({}),
    event({ field: 32, name: 'Alternator temp.', unit: '°C', value: { Float: 67 } }),
    event({ device: '51CBE6', field: 1, class: 'BAT', instance: 'house-batt', group: 'battery', name: 'State of charge', unit: '%', value: { Float: 61.8 } }),
    event({ device: '313BAF', field: 2, class: 'Solar', instance: 'aft-solars', group: 'general', name: 'Total energy', unit: 'kWh', value: { Float: 2.5 } })
  ].join('\n') + '\n'
  const result = spawnSync(process.execPath, [converter, '--log-file-id', '9', '--typed-dir', typedDir], { input, encoding: 'utf8' })
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stderr, /"alternator":2/)
  assert.match(result.stderr, /"battery":1/)
  assert.match(result.stderr, /"solar":1/)
  const alternator = fs.readFileSync(path.join(typedDir, 'masterbus_alternator_stage_v1.tsv'), 'utf8').trim().split('\n').map(line => line.split('\t'))
  assert.equal(alternator[0][0], '2026-07-21T07:19:09.090Z')
  assert.equal(alternator[0][1], 'alpha-stbd')
  assert.equal(alternator[0][3], 'masterbus-native:33AC6A')
  assert.equal(alternator[0][6], '13.793')
  assert.equal(alternator[1][11], '340.15')
  const battery = fs.readFileSync(path.join(typedDir, 'masterbus_battery_stage_v1.tsv'), 'utf8').trim().split('\t')
  assert.equal(battery[9], '0.618')
  const solar = fs.readFileSync(path.join(typedDir, 'masterbus_solar_stage_v1.tsv'), 'utf8').trim().split('\t')
  assert.equal(solar[9], '9000000')
})

test('native MasterBus importer requires bounded input and exposes dry-run batch mode', () => {
  const help = spawnSync(process.execPath, [importer, '--help'], { encoding: 'utf8' })
  assert.equal(help.status, 0)
  assert.match(help.stdout, /--sample-lines/)
  assert.match(help.stdout, /--allow-full-file/)
  assert.match(help.stdout, /--dry-run/)
})
