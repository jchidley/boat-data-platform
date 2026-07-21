-- MasterBus history schema v1.
--
-- MasterBus is not recoverable from picanm NMEA 2000 candump logs. Preserve
-- append-only masterbus-native-event-v1 logs captured before Signal K mapping,
-- then load typed electrical tables from those logs. These SQL tables are
-- derived and rebuildable from native events plus MasterBus config snapshots.

CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE IF NOT EXISTS masterbus_log_files_v1 (
  masterbus_log_file_id bigserial PRIMARY KEY,
  path text NOT NULL UNIQUE,
  size_bytes bigint NOT NULL,
  mtime timestamptz NOT NULL,
  sha256 text,
  first_event_time timestamptz,
  last_event_time timestamptz,
  line_count bigint,
  import_status text NOT NULL DEFAULT 'new',
  imported_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT masterbus_log_files_v1_status_check CHECK (import_status IN ('new', 'staged', 'imported', 'failed', 'ignored'))
);

CREATE TABLE IF NOT EXISTS masterbus_devices_v1 (
  masterbus_device_id bigserial PRIMARY KEY,
  stable_key text NOT NULL UNIQUE,
  display_name text,
  device_type text,
  masterbus_address text,
  signal_k_prefix text,
  first_seen timestamptz,
  last_seen timestamptz,
  notes text
);

CREATE TABLE IF NOT EXISTS masterbus_alternator_samples_v1 (
  time timestamptz NOT NULL,
  alternator_key text NOT NULL,
  masterbus_device_id bigint REFERENCES masterbus_devices_v1(masterbus_device_id),
  source text NOT NULL DEFAULT 'masterbus',
  raw_log_file_id bigint REFERENCES masterbus_log_files_v1(masterbus_log_file_id),
  raw_line_number integer,
  sense_voltage_v double precision,
  alternator_voltage_v double precision,
  voltage_v double precision,
  current_a double precision,
  field_current_a double precision,
  alternator_temperature_k double precision,
  temperature_k double precision,
  PRIMARY KEY (time, alternator_key)
);
SELECT create_hypertable('masterbus_alternator_samples_v1', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS masterbus_alternator_samples_v1_key_time_idx ON masterbus_alternator_samples_v1 (alternator_key, time DESC);

CREATE TABLE IF NOT EXISTS masterbus_battery_samples_v1 (
  time timestamptz NOT NULL,
  battery_key text NOT NULL,
  masterbus_device_id bigint REFERENCES masterbus_devices_v1(masterbus_device_id),
  source text NOT NULL DEFAULT 'masterbus',
  raw_log_file_id bigint REFERENCES masterbus_log_files_v1(masterbus_log_file_id),
  raw_line_number integer,
  voltage_v double precision,
  current_a double precision,
  temperature_k double precision,
  state_of_charge_ratio double precision,
  time_remaining_s double precision,
  PRIMARY KEY (time, battery_key)
);
SELECT create_hypertable('masterbus_battery_samples_v1', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS masterbus_battery_samples_v1_key_time_idx ON masterbus_battery_samples_v1 (battery_key, time DESC);

CREATE TABLE IF NOT EXISTS masterbus_inverter_charger_samples_v1 (
  time timestamptz NOT NULL,
  device_key text NOT NULL,
  masterbus_device_id bigint REFERENCES masterbus_devices_v1(masterbus_device_id),
  source text NOT NULL DEFAULT 'masterbus',
  raw_log_file_id bigint REFERENCES masterbus_log_files_v1(masterbus_log_file_id),
  raw_line_number integer,
  inverter_enabled boolean,
  charger_enabled boolean,
  ac_in_voltage_v double precision,
  ac_in_current_a double precision,
  ac_in_current_limit_a double precision,
  ac_in_frequency_hz double precision,
  ac_out_voltage_v double precision,
  ac_out_power_w double precision,
  ac_out_frequency_hz double precision,
  dc_voltage_v double precision,
  dc_current_a double precision,
  PRIMARY KEY (time, device_key)
);
SELECT create_hypertable('masterbus_inverter_charger_samples_v1', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS masterbus_inverter_charger_samples_v1_key_time_idx ON masterbus_inverter_charger_samples_v1 (device_key, time DESC);

CREATE TABLE IF NOT EXISTS masterbus_solar_samples_v1 (
  time timestamptz NOT NULL,
  controller_key text NOT NULL,
  masterbus_device_id bigint REFERENCES masterbus_devices_v1(masterbus_device_id),
  source text NOT NULL DEFAULT 'masterbus',
  raw_log_file_id bigint REFERENCES masterbus_log_files_v1(masterbus_log_file_id),
  raw_line_number integer,
  battery_voltage_v double precision,
  panel_voltage_v double precision,
  charge_current_a double precision,
  yield_total_wh double precision,
  PRIMARY KEY (time, controller_key)
);
SELECT create_hypertable('masterbus_solar_samples_v1', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS masterbus_solar_samples_v1_key_time_idx ON masterbus_solar_samples_v1 (controller_key, time DESC);

-- Unlogged COPY staging tables. These are disposable import targets for replay
-- from native decoded MasterBus event logs. Mapped Signal K JSONL is fallback
-- comparison input only.
CREATE UNLOGGED TABLE IF NOT EXISTS masterbus_alternator_stage_v1 (LIKE masterbus_alternator_samples_v1 INCLUDING DEFAULTS);
CREATE UNLOGGED TABLE IF NOT EXISTS masterbus_battery_stage_v1 (LIKE masterbus_battery_samples_v1 INCLUDING DEFAULTS);
CREATE UNLOGGED TABLE IF NOT EXISTS masterbus_inverter_charger_stage_v1 (LIKE masterbus_inverter_charger_samples_v1 INCLUDING DEFAULTS);
CREATE UNLOGGED TABLE IF NOT EXISTS masterbus_solar_stage_v1 (LIKE masterbus_solar_samples_v1 INCLUDING DEFAULTS);

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO boat_ingest;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO boat_ingest;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana_reader;
