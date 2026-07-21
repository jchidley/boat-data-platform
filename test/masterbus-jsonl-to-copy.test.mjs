import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'

const script = path.resolve('scripts/masterbus-jsonl-to-copy.mjs')

function runFixture(input) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'masterbus-copy-test-'))
  const typedDir = path.join(dir, 'typed')
  const result = spawnSync(process.execPath, [script, '--log-file-id', '7', '--typed-dir', typedDir], { input, encoding: 'utf8' })
  return { typedDir, result }
}

test('converts replayed MasterBus Signal K JSONL to typed COPY TSV', () => {
  const input = JSON.stringify({
    receivedAt: '2026-07-04T12:00:00.500Z',
    delta: {
      context: 'vessels.self',
      updates: [{
        timestamp: '2026-07-04T12:00:00.000Z',
        $source: 'masterbus',
        values: [
          { path: 'electrical.alternators.alpha-port.senseVoltage', value: 13.6 },
          { path: 'electrical.alternators.alpha-port.fieldCurrent', value: 1.2 },
          { path: 'electrical.batteries.house-batt.voltage', value: 13.7 },
          { path: 'electrical.batteries.house-batt.capacity.stateOfCharge', value: 0.94 },
          { path: 'electrical.inverters.combimaster.ac.power', value: 184 },
          { path: 'electrical.inverters.combimaster.enabled', value: true },
          { path: 'electrical.chargers.combimaster.acin.currentLimit', value: 30 },
          { path: 'electrical.solar.aft-solars.chargeCurrent', value: 12.5 },
          { path: 'electrical.solar.aft-solars.panelVoltage', value: 37.3 }
        ]
      }]
    }
  }) + '\n'

  const { typedDir, result } = runFixture(input)
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stderr, /"alternator":1/)
  assert.match(result.stderr, /"battery":1/)
  assert.match(result.stderr, /"inverterCharger":1/)
  assert.match(result.stderr, /"solar":1/)

  const alternator = fs.readFileSync(path.join(typedDir, 'masterbus_alternator_stage_v1.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(alternator, ['2026-07-04T12:00:00.000Z', 'alpha-port', '\\N', 'masterbus', '7', '1', '13.6', '\\N', '\\N', '\\N', '1.2', '\\N', '\\N'])

  const battery = fs.readFileSync(path.join(typedDir, 'masterbus_battery_stage_v1.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(battery, ['2026-07-04T12:00:00.000Z', 'house-batt', '\\N', 'masterbus', '7', '1', '13.7', '\\N', '\\N', '0.94', '\\N'])

  const inverter = fs.readFileSync(path.join(typedDir, 'masterbus_inverter_charger_stage_v1.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(inverter, ['2026-07-04T12:00:00.000Z', 'combimaster', '\\N', 'masterbus', '7', '1', 'true', '\\N', '\\N', '\\N', '30', '\\N', '\\N', '184', '\\N', '\\N', '\\N'])

  const solar = fs.readFileSync(path.join(typedDir, 'masterbus_solar_stage_v1.tsv'), 'utf8').trim().split('\t')
  assert.deepEqual(solar, ['2026-07-04T12:00:00.000Z', 'aft-solars', '\\N', 'masterbus', '7', '1', '\\N', '37.3', '12.5', '\\N'])
})
