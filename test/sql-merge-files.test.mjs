import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'

const n2kSchemaSql = fs.readFileSync('infra/pi5nvme/sql/005_relational_n2k_v2.sql', 'utf8')
const n2kSql = fs.readFileSync('infra/pi5nvme/sql/007_n2k_v2_merge.sql', 'utf8')
const masterbusSchemaSql = fs.readFileSync('infra/pi5nvme/sql/006_masterbus_v1.sql', 'utf8')
const masterbusSql = fs.readFileSync('infra/pi5nvme/sql/008_masterbus_v1_merge.sql', 'utf8')
const inventoryViewsSql = fs.readFileSync('infra/pi5nvme/sql/009_inventory_views.sql', 'utf8')
const cleanupSql = fs.readFileSync('infra/pi5nvme/sql/010_end_state_cleanup.sql', 'utf8')
const engineSql = fs.readFileSync('infra/pi5nvme/sql/011_masterbus_engine_history_v1.sql', 'utf8')

test('active SQL defines summary-backed N2K views and end-state cleanup', () => {
  assert.match(inventoryViewsSql, /FROM n2k_file_pgn_summary_v2/)
  assert.match(inventoryViewsSql, /FROM n2k_file_source_summary_v2/)
  assert.doesNotMatch(inventoryViewsSql, /n2k_frames_v2/)
  for (const object of [
    'signal_k_measurements',
    'raw_n2k_log_files',
    'masterbus_snapshots',
    'data_quality_observations',
    'boat_data_summaries',
    'n2k_device_pgn_summary_v2'
  ]) assert.match(cleanupSql, new RegExp(`DROP TABLE IF EXISTS public\\.${object}`))
})

test('N2K v2 schema uses direct typed provenance and grants staging privileges', () => {
  assert.match(n2kSchemaSql, /raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2\(raw_file_id\)/)
  assert.match(n2kSchemaSql, /message_index integer NOT NULL/)
  assert.doesNotMatch(n2kSchemaSql, /CREATE TABLE IF NOT EXISTS n2k_frames_v2/)
  assert.doesNotMatch(n2kSchemaSql, /frame_id/)
  assert.match(n2kSchemaSql, /GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO boat_ingest;/)
})

test('nested PGN rows use source-list position rather than mutable child identity', () => {
  assert.match(n2kSchemaSql, /n2k_route_waypoint_129285_v2[\s\S]*PRIMARY KEY \(time, raw_file_id, message_index, waypoint_index\)/)
  assert.match(n2kSchemaSql, /n2k_gnss_satellites_129540_v2[\s\S]*PRIMARY KEY \(time, raw_file_id, message_index, satellite_index\)/)
  assert.match(n2kSql, /ON CONFLICT \(time, raw_file_id, message_index, waypoint_index\) DO UPDATE/)
  assert.match(n2kSql, /ON CONFLICT \(time, raw_file_id, message_index, satellite_index\) DO UPDATE/)
})

test('N2K v2 merge SQL covers direct-provenance typed PGNs, summaries, and status', () => {
  assert.match(n2kSql, /CREATE OR REPLACE FUNCTION n2k_merge_staged_file_v2\(p_raw_file_id bigint\)/)
  for (const table of [
    'n2k_position_rapid_129025_v2',
    'n2k_cog_sog_129026_v2',
    'n2k_gnss_position_129029_v2',
    'n2k_heading_127250_v2',
    'n2k_rudder_127245_v2',
    'n2k_heading_track_control_127237_v2',
    'n2k_rate_of_turn_127251_v2',
    'n2k_switch_bank_status_127501_v2',
    'n2k_attitude_127257_v2',
    'n2k_magnetic_variation_127258_v2',
    'n2k_water_speed_128259_v2',
    'n2k_water_depth_128267_v2',
    'n2k_distance_log_128275_v2',
    'n2k_navigation_data_129284_v2',
    'n2k_route_waypoint_129285_v2',
    'n2k_ais_class_a_position_129038_v2',
    'n2k_ais_class_b_position_129039_v2',
    'n2k_ais_class_a_static_129794_v2',
    'n2k_ais_class_b_static_a_129809_v2',
    'n2k_ais_class_b_static_b_129810_v2',
    'n2k_gnss_dops_129539_v2',
    'n2k_gnss_satellites_129540_v2',
    'n2k_wind_130306_v2',
    'n2k_environment_130310_v2',
    'n2k_environment_130311_v2',
    'n2k_temperature_130312_v2',
    'n2k_pressure_130314_v2',
    'n2k_temperature_ext_130316_v2',
    'n2k_research_fields_v2',
    'n2k_file_pgn_summary_v2',
    'n2k_file_source_summary_v2'
  ]) assert.match(n2kSql, new RegExp(`INSERT INTO ${table}`))
  assert.match(n2kSql, /import_status = 'imported'/)
  assert.match(n2kSql, /ON CONFLICT \(time, raw_file_id, message_index\)/)
  assert.match(n2kSql, /FROM n2k_frames_stage_v2/)
  assert.doesNotMatch(n2kSql, /n2k_frames_v2|frame_id/)
})

test('engine history SQL is native-source, deterministic, indexed, and gap-aware', () => {
  assert.match(engineSql, /masterbus_engine_transitions_v1/)
  assert.match(engineSql, /masterbus_engine_runtime_intervals_v1/)
  assert.match(engineSql, /rebuild_masterbus_engine_history_v1/)
  assert.match(engineSql, /alpha-port/)
  assert.match(engineSql, /alpha-stbd/)
  assert.match(engineSql, /p_threshold_v double precision DEFAULT 13\.25/)
  assert.match(engineSql, /p_start_debounce_seconds double precision DEFAULT 10/)
  assert.match(engineSql, /p_stop_debounce_seconds double precision DEFAULT 30/)
  assert.match(engineSql, /data_gap/)
  assert.match(engineSql, /TRUNCATE public\.masterbus_engine_runtime_intervals_v1/)
  assert.match(engineSql, /LOCK TABLE public\.masterbus_alternator_samples_v1 IN SHARE MODE/)
  assert.match(engineSql, /ORDER BY time, raw_log_file_id NULLS LAST, raw_line_number NULLS LAST, source/)
  assert.match(engineSql, /start_raw_line_number integer/)
  assert.match(engineSql, /end_raw_line_number integer/)
  assert.match(engineSql, /CREATE INDEX IF NOT EXISTS masterbus_engine_transitions_v1_time_idx/)
  assert.match(engineSql, /masterbus_alternator_samples_v1_time_idx/)
  assert.match(engineSql, /IF EXISTS \(SELECT FROM pg_roles WHERE rolname = 'grafana_reader'\)/)
  assert.match(engineSql, /v_masterbus_engine_runtime_summary_v1/)
  assert.doesNotMatch(engineSql, /propulsion\.port\.state|signalk-two-engine-state/)
})

test('MasterBus v1 merge SQL covers typed tables and import status', () => {
  assert.match(masterbusSchemaSql, /GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO boat_ingest;/)
  assert.match(masterbusSql, /CREATE OR REPLACE FUNCTION masterbus_merge_staged_log_v1\(p_log_file_id bigint\)/)
  for (const table of [
    'masterbus_alternator_samples_v1',
    'masterbus_battery_samples_v1',
    'masterbus_inverter_charger_samples_v1',
    'masterbus_solar_samples_v1'
  ]) assert.match(masterbusSql, new RegExp(`INSERT INTO ${table}`))
  assert.match(masterbusSql, /ON CONFLICT \(time, alternator_key\)/)
  assert.match(masterbusSql, /import_status = 'imported'/)
  assert.match(masterbusSql, /coalesce\(EXCLUDED\.sense_voltage_v/)
  assert.match(masterbusSql, /GROUP BY time, alternator_key, source, raw_log_file_id/)
  assert.match(masterbusSql, /bool_or\(inverter_enabled\)/)
  assert.doesNotMatch(masterbusSql, /line_count\s*=/)
})
