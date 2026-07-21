import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import { spawnSync } from 'node:child_process'

const script = 'scripts/import-n2k-v2-copy.mjs'
const source = fs.readFileSync(script, 'utf8')

test('N2K v2 wrapper exposes safe COPY/import workflow in help', () => {
  const result = spawnSync(process.execPath, [script, '--help'], { encoding: 'utf8' })
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /--raw-file PATH/)
  assert.match(result.stdout, /--sample-lines N/)
  assert.match(result.stdout, /--allow-full-file/)
  assert.match(result.stdout, /--research-mode MODE/)
  assert.match(result.stdout, /--decoder MODE/)
  assert.match(result.stdout, /--rust-importer CMD/)
  assert.match(result.stdout, /--max-runtime-sec N/)
  assert.match(result.stdout, /safe v2 relational\/COPY path/)
})

test('N2K v2 wrapper orchestrates analyzer, converter, COPY and merge', () => {
  assert.match(source, /analyzer-jsonl-to-n2k-copy\.mjs/)
  assert.match(source, /tools\/n2k-rust-importer\/target\/release\/n2k-rust-importer/)
  assert.match(source, /decoder === 'rust'/)
  assert.match(source, /INSERT INTO n2k_raw_files_v2/)
  assert.match(source, /copyCommand\('n2k_frames_stage_v2'/)
  assert.match(source, /researchMode = arg\('--research-mode'\) \|\| 'none'/)
  assert.match(source, /refusing a complete import without --allow-full-file/)
  assert.match(source, /N2K_IMPORT_MAX_INPUT_BYTES/)
  assert.match(source, /n2k_rudder_127245_stage_v2/)
  assert.match(source, /n2k_environment_130310_stage_v2/)
  assert.match(source, /n2k_temperature_ext_130316_stage_v2/)
  assert.match(source, /n2k_switch_bank_status_127501_stage_v2/)
  assert.match(source, /n2k_heading_track_control_127237_stage_v2/)
  assert.match(source, /n2k_navigation_data_129284_stage_v2/)
  assert.match(source, /n2k_route_waypoint_129285_stage_v2/)
  assert.match(source, /n2k_ais_class_a_position_129038_stage_v2/)
  assert.match(source, /n2k_ais_class_b_position_129039_stage_v2/)
  assert.match(source, /n2k_ais_class_a_static_129794_stage_v2/)
  assert.match(source, /n2k_ais_class_b_static_a_129809_stage_v2/)
  assert.match(source, /n2k_ais_class_b_static_b_129810_stage_v2/)
  assert.match(source, /n2k_gnss_dops_129539_stage_v2/)
  assert.match(source, /n2k_gnss_satellites_129540_stage_v2/)
  assert.match(source, /SELECT n2k_merge_staged_file_v2\(\$\{rawFileId\}\)/)
})
