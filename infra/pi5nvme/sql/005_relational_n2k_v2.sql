-- Relational N2K schema v2: PGN-shaped canonical SQL storage.
--
-- Raw candump logs remain the source of truth. These tables are derived and
-- may be rebuilt from scratch. The schema models NMEA 2000 frame envelopes and
-- typed PGN/message shapes rather than analyzer JSON documents.

CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE IF NOT EXISTS n2k_raw_files_v2 (
  raw_file_id bigserial PRIMARY KEY,
  path text NOT NULL UNIQUE,
  size_bytes bigint NOT NULL,
  mtime timestamptz NOT NULL,
  sha256 text,
  first_edge_time timestamptz,
  last_edge_time timestamptz,
  frame_count bigint,
  import_status text NOT NULL DEFAULT 'new',
  error_summary text,
  mirrored_at timestamptz NOT NULL DEFAULT now(),
  imported_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT n2k_raw_files_v2_status_check CHECK (import_status IN ('new', 'staged', 'imported', 'failed', 'ignored'))
);

CREATE TABLE IF NOT EXISTS n2k_import_runs_v2 (
  import_run_id bigserial PRIMARY KEY,
  raw_file_id bigint REFERENCES n2k_raw_files_v2(raw_file_id),
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  status text NOT NULL DEFAULT 'running',
  tool_version text,
  error_summary text,
  evidence jsonb,
  CONSTRAINT n2k_import_runs_v2_status_check CHECK (status IN ('running', 'succeeded', 'failed', 'aborted'))
);

CREATE TABLE IF NOT EXISTS n2k_pgn_definitions_v2 (
  pgn integer PRIMARY KEY,
  description text,
  model_status text NOT NULL DEFAULT 'unmodelled',
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT n2k_pgn_definitions_v2_model_status_check CHECK (model_status IN ('typed', 'summary_only', 'research', 'unmodelled'))
);

CREATE TABLE IF NOT EXISTS n2k_devices_v2 (
  device_id bigserial PRIMARY KEY,
  stable_label text,
  manufacturer text,
  model text,
  serial text,
  unique_number bigint,
  device_instance integer,
  system_instance integer,
  first_seen timestamptz,
  last_seen timestamptz,
  notes text,
  UNIQUE NULLS NOT DISTINCT (manufacturer, model, serial, unique_number, device_instance, system_instance)
);

CREATE TABLE IF NOT EXISTS n2k_source_observations_v2 (
  observed_at timestamptz NOT NULL,
  source_address smallint NOT NULL,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  manufacturer_code integer,
  device_class integer,
  device_function integer,
  device_instance integer,
  system_instance integer,
  unique_number bigint,
  device_name bigint,
  raw_file_id bigint REFERENCES n2k_raw_files_v2(raw_file_id),
  PRIMARY KEY (observed_at, source_address)
);
SELECT create_hypertable('n2k_source_observations_v2', 'observed_at', if_not_exists => TRUE);

-- Typed PGN tables carry direct raw-file and message-position provenance.

CREATE TABLE IF NOT EXISTS n2k_position_rapid_129025_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  latitude_deg double precision NOT NULL,
  longitude_deg double precision NOT NULL,
  PRIMARY KEY (time, raw_file_id, message_index),
  CONSTRAINT n2k_position_rapid_129025_lat_check CHECK (latitude_deg BETWEEN -90 AND 90),
  CONSTRAINT n2k_position_rapid_129025_lon_check CHECK (longitude_deg BETWEEN -180 AND 180)
);
SELECT create_hypertable('n2k_position_rapid_129025_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_position_rapid_129025_source_time_idx ON n2k_position_rapid_129025_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_cog_sog_129026_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  sequence_id smallint,
  reference text,
  cog_rad double precision,
  sog_ms double precision,
  PRIMARY KEY (time, raw_file_id, message_index),
  CONSTRAINT n2k_cog_sog_129026_cog_check CHECK (cog_rad IS NULL OR (cog_rad >= 0 AND cog_rad < 6.283185307179586)),
  CONSTRAINT n2k_cog_sog_129026_sog_check CHECK (sog_ms IS NULL OR sog_ms >= 0)
);
SELECT create_hypertable('n2k_cog_sog_129026_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_cog_sog_129026_source_time_idx ON n2k_cog_sog_129026_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_gnss_position_129029_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  sequence_id smallint,
  days_since_1970 integer,
  seconds_since_midnight double precision,
  latitude_deg double precision,
  longitude_deg double precision,
  altitude_m double precision,
  gnss_type text,
  method text,
  integrity text,
  satellites smallint,
  hdop double precision,
  pdop double precision,
  geoidal_separation_m double precision,
  reference_stations smallint,
  PRIMARY KEY (time, raw_file_id, message_index),
  CONSTRAINT n2k_gnss_position_129029_lat_check CHECK (latitude_deg IS NULL OR latitude_deg BETWEEN -90 AND 90),
  CONSTRAINT n2k_gnss_position_129029_lon_check CHECK (longitude_deg IS NULL OR longitude_deg BETWEEN -180 AND 180)
);
SELECT create_hypertable('n2k_gnss_position_129029_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_gnss_position_129029_source_time_idx ON n2k_gnss_position_129029_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_heading_127250_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  sequence_id smallint,
  heading_rad double precision,
  deviation_rad double precision,
  variation_rad double precision,
  reference text,
  PRIMARY KEY (time, raw_file_id, message_index),
  CONSTRAINT n2k_heading_127250_heading_check CHECK (heading_rad IS NULL OR (heading_rad >= 0 AND heading_rad < 6.283185307179586))
);
SELECT create_hypertable('n2k_heading_127250_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_heading_127250_source_time_idx ON n2k_heading_127250_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_rudder_127245_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  instance smallint,
  direction_order text,
  angle_order_rad double precision,
  position_rad double precision,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_rudder_127245_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_rudder_127245_source_time_idx ON n2k_rudder_127245_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_heading_track_control_127237_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  rudder_limit_exceeded text,
  off_heading_limit_exceeded text,
  off_track_limit_exceeded text,
  override text,
  steering_mode text,
  turn_mode text,
  heading_reference text,
  commanded_rudder_direction text,
  commanded_rudder_angle_rad double precision,
  heading_to_steer_rad double precision,
  track_rad double precision,
  rudder_limit_rad double precision,
  off_heading_limit_rad double precision,
  radius_of_turn_order_m double precision,
  rate_of_turn_order_rad_s double precision,
  off_track_limit_m double precision,
  vessel_heading_rad double precision,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_heading_track_control_127237_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_heading_track_control_127237_source_time_idx ON n2k_heading_track_control_127237_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_rate_of_turn_127251_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  sid smallint,
  rate_rad_s double precision,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_rate_of_turn_127251_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_rate_of_turn_127251_source_time_idx ON n2k_rate_of_turn_127251_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_switch_bank_status_127501_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  instance smallint,
  indicator1 text,
  indicator2 text,
  indicator3 text,
  indicator4 text,
  indicator5 text,
  indicator6 text,
  indicator7 text,
  indicator8 text,
  indicator9 text,
  indicator10 text,
  indicator11 text,
  indicator12 text,
  indicator13 text,
  indicator14 text,
  indicator15 text,
  indicator16 text,
  indicator17 text,
  indicator18 text,
  indicator19 text,
  indicator20 text,
  indicator21 text,
  indicator22 text,
  indicator23 text,
  indicator24 text,
  indicator25 text,
  indicator26 text,
  indicator27 text,
  indicator28 text,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_switch_bank_status_127501_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_switch_bank_status_127501_source_time_idx ON n2k_switch_bank_status_127501_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_attitude_127257_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  sid smallint,
  yaw_rad double precision,
  pitch_rad double precision,
  roll_rad double precision,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_attitude_127257_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_attitude_127257_source_time_idx ON n2k_attitude_127257_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_magnetic_variation_127258_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  sid smallint,
  source text,
  variation_rad double precision,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_magnetic_variation_127258_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_magnetic_variation_127258_source_time_idx ON n2k_magnetic_variation_127258_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_water_speed_128259_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  speed_water_referenced_ms double precision,
  speed_ground_referenced_ms double precision,
  speed_water_type text,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_water_speed_128259_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_water_speed_128259_source_time_idx ON n2k_water_speed_128259_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_water_depth_128267_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  sid smallint,
  depth_below_transducer_m double precision,
  offset_m double precision,
  range_m double precision,
  PRIMARY KEY (time, raw_file_id, message_index),
  CONSTRAINT n2k_water_depth_128267_depth_check CHECK (depth_below_transducer_m IS NULL OR depth_below_transducer_m >= 0)
);
SELECT create_hypertable('n2k_water_depth_128267_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_water_depth_128267_source_time_idx ON n2k_water_depth_128267_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_distance_log_128275_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  days_since_1970 integer,
  seconds_since_midnight double precision,
  log_m double precision,
  trip_log_m double precision,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_distance_log_128275_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_distance_log_128275_source_time_idx ON n2k_distance_log_128275_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_navigation_data_129284_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  sid smallint,
  distance_to_waypoint_m double precision,
  course_bearing_reference text,
  perpendicular_crossed text,
  arrival_circle_entered text,
  calculation_type text,
  eta_seconds_since_midnight double precision,
  eta_days_since_1970 integer,
  bearing_origin_to_destination_rad double precision,
  bearing_position_to_destination_rad double precision,
  origin_waypoint_number integer,
  destination_waypoint_number integer,
  destination_latitude_deg double precision,
  destination_longitude_deg double precision,
  waypoint_closing_velocity_ms double precision,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_navigation_data_129284_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_navigation_data_129284_source_time_idx ON n2k_navigation_data_129284_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_route_waypoint_129285_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  start_rps integer,
  item_count integer,
  database_id integer,
  route_id integer,
  navigation_direction text,
  supplementary_data_available text,
  route_name text,
  waypoint_index smallint NOT NULL,
  waypoint_id integer,
  waypoint_name text,
  waypoint_latitude_deg double precision,
  waypoint_longitude_deg double precision,
  PRIMARY KEY (time, raw_file_id, message_index, waypoint_index)
);
SELECT create_hypertable('n2k_route_waypoint_129285_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_route_waypoint_129285_source_time_idx ON n2k_route_waypoint_129285_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_ais_class_a_position_129038_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  message_id text,
  repeat_indicator text,
  user_id bigint,
  longitude_deg double precision,
  latitude_deg double precision,
  position_accuracy text,
  raim text,
  time_stamp text,
  cog_rad double precision,
  sog_ms double precision,
  communication_state text,
  ais_transceiver_information text,
  heading_rad double precision,
  rate_of_turn_rad_s double precision,
  nav_status text,
  special_maneuver_indicator text,
  sequence_id smallint,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_ais_class_a_position_129038_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_ais_class_a_position_129038_user_time_idx ON n2k_ais_class_a_position_129038_v2 (user_id, time DESC);

CREATE TABLE IF NOT EXISTS n2k_ais_class_b_position_129039_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  message_id text,
  repeat_indicator text,
  user_id bigint,
  longitude_deg double precision,
  latitude_deg double precision,
  position_accuracy text,
  raim text,
  time_stamp text,
  cog_rad double precision,
  sog_ms double precision,
  communication_state text,
  ais_transceiver_information text,
  heading_rad double precision,
  unit_type text,
  integrated_display text,
  dsc text,
  band text,
  can_handle_msg_22 text,
  ais_mode text,
  ais_communication_state text,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_ais_class_b_position_129039_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_ais_class_b_position_129039_user_time_idx ON n2k_ais_class_b_position_129039_v2 (user_id, time DESC);

CREATE TABLE IF NOT EXISTS n2k_ais_class_a_static_129794_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  message_id text,
  repeat_indicator text,
  user_id bigint,
  imo_number bigint,
  callsign text,
  name text,
  ship_type text,
  length_m double precision,
  beam_m double precision,
  position_reference_starboard_m double precision,
  position_reference_bow_m double precision,
  eta_days_since_1970 integer,
  eta_seconds_since_midnight double precision,
  draft_m double precision,
  destination text,
  ais_version_indicator text,
  gnss_type text,
  dte text,
  ais_transceiver_information text,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_ais_class_a_static_129794_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_ais_class_a_static_129794_user_time_idx ON n2k_ais_class_a_static_129794_v2 (user_id, time DESC);

CREATE TABLE IF NOT EXISTS n2k_ais_class_b_static_a_129809_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  message_id text,
  repeat_indicator text,
  user_id bigint,
  name text,
  ais_transceiver_information text,
  sequence_id smallint,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_ais_class_b_static_a_129809_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_ais_class_b_static_a_129809_user_time_idx ON n2k_ais_class_b_static_a_129809_v2 (user_id, time DESC);

CREATE TABLE IF NOT EXISTS n2k_ais_class_b_static_b_129810_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  message_id text,
  repeat_indicator text,
  user_id bigint,
  ship_type text,
  vendor_id text,
  callsign text,
  length_m double precision,
  beam_m double precision,
  position_reference_starboard_m double precision,
  position_reference_bow_m double precision,
  mothership_user_id bigint,
  gnss_type text,
  ais_transceiver_information text,
  sequence_id smallint,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_ais_class_b_static_b_129810_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_ais_class_b_static_b_129810_user_time_idx ON n2k_ais_class_b_static_b_129810_v2 (user_id, time DESC);

CREATE TABLE IF NOT EXISTS n2k_gnss_dops_129539_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  sid smallint,
  desired_mode text,
  actual_mode text,
  hdop double precision,
  vdop double precision,
  tdop double precision,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_gnss_dops_129539_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_gnss_dops_129539_source_time_idx ON n2k_gnss_dops_129539_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_gnss_satellites_129540_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  sid smallint,
  range_residual_mode text,
  sats_in_view smallint,
  satellite_index smallint NOT NULL,
  prn smallint,
  elevation_rad double precision,
  azimuth_rad double precision,
  snr_db double precision,
  range_residual_m double precision,
  status text,
  PRIMARY KEY (time, raw_file_id, message_index, satellite_index)
);
SELECT create_hypertable('n2k_gnss_satellites_129540_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_gnss_satellites_129540_source_time_idx ON n2k_gnss_satellites_129540_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_wind_130306_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  sid smallint,
  wind_speed_ms double precision,
  wind_angle_rad double precision,
  reference text,
  PRIMARY KEY (time, raw_file_id, message_index),
  CONSTRAINT n2k_wind_130306_speed_check CHECK (wind_speed_ms IS NULL OR wind_speed_ms >= 0)
);
SELECT create_hypertable('n2k_wind_130306_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_wind_130306_source_time_idx ON n2k_wind_130306_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_environment_130310_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  sid smallint,
  water_temperature_k double precision,
  outside_ambient_air_temperature_k double precision,
  atmospheric_pressure_pa double precision,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_environment_130310_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_environment_130310_source_time_idx ON n2k_environment_130310_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_environment_130311_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  sid smallint,
  temperature_source text,
  humidity_source text,
  temperature_k double precision,
  humidity_ratio double precision,
  atmospheric_pressure_pa double precision,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_environment_130311_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_environment_130311_source_time_idx ON n2k_environment_130311_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_temperature_130312_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  sid smallint,
  instance smallint,
  source text,
  actual_temperature_k double precision,
  set_temperature_k double precision,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_temperature_130312_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_temperature_130312_source_time_idx ON n2k_temperature_130312_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_pressure_130314_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  sid smallint,
  instance smallint,
  source text,
  pressure_pa double precision,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_pressure_130314_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_pressure_130314_source_time_idx ON n2k_pressure_130314_v2 (source_address, time DESC);

CREATE TABLE IF NOT EXISTS n2k_temperature_ext_130316_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  device_id bigint REFERENCES n2k_devices_v2(device_id),
  sid smallint,
  instance smallint,
  source text,
  temperature_k double precision,
  set_temperature_k double precision,
  PRIMARY KEY (time, raw_file_id, message_index)
);
SELECT create_hypertable('n2k_temperature_ext_130316_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_temperature_ext_130316_source_time_idx ON n2k_temperature_ext_130316_v2 (source_address, time DESC);

-- Research fallback for unknown/proprietary PGNs. This is not the primary app
-- query model and should not receive a GIN index during ingest.
CREATE TABLE IF NOT EXISTS n2k_research_fields_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  pgn integer NOT NULL,
  source_address smallint,
  field_name text NOT NULL,
  value_double double precision,
  value_text text,
  value_bool boolean,
  PRIMARY KEY (time, raw_file_id, message_index, field_name),
  CONSTRAINT n2k_research_fields_v2_one_value_check CHECK (
    ((value_double IS NOT NULL)::integer +
     (value_text IS NOT NULL)::integer +
     (value_bool IS NOT NULL)::integer) <= 1
  )
);
SELECT create_hypertable('n2k_research_fields_v2', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS n2k_research_fields_v2_pgn_time_idx ON n2k_research_fields_v2 (pgn, time DESC);

-- Direct provenance lookups must not scan time-first hypertable keys.
DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'n2k_position_rapid_129025_v2', 'n2k_cog_sog_129026_v2',
    'n2k_gnss_position_129029_v2', 'n2k_heading_127250_v2',
    'n2k_rudder_127245_v2', 'n2k_heading_track_control_127237_v2',
    'n2k_rate_of_turn_127251_v2', 'n2k_switch_bank_status_127501_v2',
    'n2k_attitude_127257_v2', 'n2k_magnetic_variation_127258_v2',
    'n2k_water_speed_128259_v2', 'n2k_water_depth_128267_v2',
    'n2k_distance_log_128275_v2', 'n2k_navigation_data_129284_v2',
    'n2k_route_waypoint_129285_v2', 'n2k_ais_class_a_position_129038_v2',
    'n2k_ais_class_b_position_129039_v2', 'n2k_ais_class_a_static_129794_v2',
    'n2k_ais_class_b_static_a_129809_v2', 'n2k_ais_class_b_static_b_129810_v2',
    'n2k_gnss_dops_129539_v2', 'n2k_gnss_satellites_129540_v2',
    'n2k_wind_130306_v2', 'n2k_environment_130310_v2',
    'n2k_environment_130311_v2', 'n2k_temperature_130312_v2',
    'n2k_pressure_130314_v2', 'n2k_temperature_ext_130316_v2',
    'n2k_research_fields_v2'
  ] LOOP
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I (raw_file_id, message_index)',
      table_name || '_provenance_idx', table_name);
  END LOOP;
END $$;

CREATE TABLE IF NOT EXISTS n2k_file_pgn_summary_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  pgn integer NOT NULL,
  source_key smallint NOT NULL DEFAULT -1,
  source_address smallint,
  frame_count bigint NOT NULL,
  first_time timestamptz,
  last_time timestamptz,
  PRIMARY KEY (raw_file_id, pgn, source_key),
  CONSTRAINT n2k_file_pgn_summary_v2_source_key_check CHECK (
    (source_address IS NULL AND source_key = -1) OR
    (source_address IS NOT NULL AND source_key = source_address)
  )
);

CREATE TABLE IF NOT EXISTS n2k_file_source_summary_v2 (
  raw_file_id bigint NOT NULL REFERENCES n2k_raw_files_v2(raw_file_id),
  source_address smallint NOT NULL,
  frame_count bigint NOT NULL,
  first_time timestamptz,
  last_time timestamptz,
  pgns integer[] NOT NULL,
  PRIMARY KEY (raw_file_id, source_address)
);

-- Staging tables for PostgreSQL COPY. Keep them unlogged/disposable. Real
-- imports should add one staging table per typed PGN; this generic research
-- stage is only for unmapped/proprietary PGNs.
CREATE UNLOGGED TABLE IF NOT EXISTS n2k_frames_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  pgn integer NOT NULL,
  source_address smallint,
  destination_address smallint,
  priority smallint,
  can_id integer
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_position_rapid_129025_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  latitude_deg double precision,
  longitude_deg double precision
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_cog_sog_129026_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  sequence_id smallint,
  reference text,
  cog_rad double precision,
  sog_ms double precision
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_gnss_position_129029_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  sequence_id smallint,
  days_since_1970 integer,
  seconds_since_midnight double precision,
  latitude_deg double precision,
  longitude_deg double precision,
  altitude_m double precision,
  gnss_type text,
  method text,
  integrity text,
  satellites smallint,
  hdop double precision,
  pdop double precision,
  geoidal_separation_m double precision,
  reference_stations smallint
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_heading_127250_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  sequence_id smallint,
  heading_rad double precision,
  deviation_rad double precision,
  variation_rad double precision,
  reference text
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_rudder_127245_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  instance smallint,
  direction_order text,
  angle_order_rad double precision,
  position_rad double precision
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_heading_track_control_127237_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  rudder_limit_exceeded text,
  off_heading_limit_exceeded text,
  off_track_limit_exceeded text,
  override text,
  steering_mode text,
  turn_mode text,
  heading_reference text,
  commanded_rudder_direction text,
  commanded_rudder_angle_rad double precision,
  heading_to_steer_rad double precision,
  track_rad double precision,
  rudder_limit_rad double precision,
  off_heading_limit_rad double precision,
  radius_of_turn_order_m double precision,
  rate_of_turn_order_rad_s double precision,
  off_track_limit_m double precision,
  vessel_heading_rad double precision
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_rate_of_turn_127251_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  sid smallint,
  rate_rad_s double precision
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_switch_bank_status_127501_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  instance smallint,
  indicator1 text,
  indicator2 text,
  indicator3 text,
  indicator4 text,
  indicator5 text,
  indicator6 text,
  indicator7 text,
  indicator8 text,
  indicator9 text,
  indicator10 text,
  indicator11 text,
  indicator12 text,
  indicator13 text,
  indicator14 text,
  indicator15 text,
  indicator16 text,
  indicator17 text,
  indicator18 text,
  indicator19 text,
  indicator20 text,
  indicator21 text,
  indicator22 text,
  indicator23 text,
  indicator24 text,
  indicator25 text,
  indicator26 text,
  indicator27 text,
  indicator28 text
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_attitude_127257_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  sid smallint,
  yaw_rad double precision,
  pitch_rad double precision,
  roll_rad double precision
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_magnetic_variation_127258_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  sid smallint,
  source text,
  variation_rad double precision
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_water_speed_128259_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  speed_water_referenced_ms double precision,
  speed_ground_referenced_ms double precision,
  speed_water_type text
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_water_depth_128267_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  sid smallint,
  depth_below_transducer_m double precision,
  offset_m double precision,
  range_m double precision
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_distance_log_128275_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  days_since_1970 integer,
  seconds_since_midnight double precision,
  log_m double precision,
  trip_log_m double precision
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_navigation_data_129284_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  sid smallint,
  distance_to_waypoint_m double precision,
  course_bearing_reference text,
  perpendicular_crossed text,
  arrival_circle_entered text,
  calculation_type text,
  eta_seconds_since_midnight double precision,
  eta_days_since_1970 integer,
  bearing_origin_to_destination_rad double precision,
  bearing_position_to_destination_rad double precision,
  origin_waypoint_number integer,
  destination_waypoint_number integer,
  destination_latitude_deg double precision,
  destination_longitude_deg double precision,
  waypoint_closing_velocity_ms double precision
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_route_waypoint_129285_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  start_rps integer,
  item_count integer,
  database_id integer,
  route_id integer,
  navigation_direction text,
  supplementary_data_available text,
  route_name text,
  waypoint_index smallint NOT NULL,
  waypoint_id integer,
  waypoint_name text,
  waypoint_latitude_deg double precision,
  waypoint_longitude_deg double precision
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_ais_class_a_position_129038_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  message_id text,
  repeat_indicator text,
  user_id bigint,
  longitude_deg double precision,
  latitude_deg double precision,
  position_accuracy text,
  raim text,
  time_stamp text,
  cog_rad double precision,
  sog_ms double precision,
  communication_state text,
  ais_transceiver_information text,
  heading_rad double precision,
  rate_of_turn_rad_s double precision,
  nav_status text,
  special_maneuver_indicator text,
  sequence_id smallint
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_ais_class_b_position_129039_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  message_id text,
  repeat_indicator text,
  user_id bigint,
  longitude_deg double precision,
  latitude_deg double precision,
  position_accuracy text,
  raim text,
  time_stamp text,
  cog_rad double precision,
  sog_ms double precision,
  communication_state text,
  ais_transceiver_information text,
  heading_rad double precision,
  unit_type text,
  integrated_display text,
  dsc text,
  band text,
  can_handle_msg_22 text,
  ais_mode text,
  ais_communication_state text
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_ais_class_a_static_129794_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  message_id text,
  repeat_indicator text,
  user_id bigint,
  imo_number bigint,
  callsign text,
  name text,
  ship_type text,
  length_m double precision,
  beam_m double precision,
  position_reference_starboard_m double precision,
  position_reference_bow_m double precision,
  eta_days_since_1970 integer,
  eta_seconds_since_midnight double precision,
  draft_m double precision,
  destination text,
  ais_version_indicator text,
  gnss_type text,
  dte text,
  ais_transceiver_information text
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_ais_class_b_static_a_129809_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  message_id text,
  repeat_indicator text,
  user_id bigint,
  name text,
  ais_transceiver_information text,
  sequence_id smallint
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_ais_class_b_static_b_129810_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  message_id text,
  repeat_indicator text,
  user_id bigint,
  ship_type text,
  vendor_id text,
  callsign text,
  length_m double precision,
  beam_m double precision,
  position_reference_starboard_m double precision,
  position_reference_bow_m double precision,
  mothership_user_id bigint,
  gnss_type text,
  ais_transceiver_information text,
  sequence_id smallint
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_gnss_dops_129539_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  sid smallint,
  desired_mode text,
  actual_mode text,
  hdop double precision,
  vdop double precision,
  tdop double precision
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_gnss_satellites_129540_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  sid smallint,
  range_residual_mode text,
  sats_in_view smallint,
  satellite_index smallint NOT NULL,
  prn smallint,
  elevation_rad double precision,
  azimuth_rad double precision,
  snr_db double precision,
  range_residual_m double precision,
  status text
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_wind_130306_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  sid smallint,
  wind_speed_ms double precision,
  wind_angle_rad double precision,
  reference text
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_environment_130310_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  sid smallint,
  water_temperature_k double precision,
  outside_ambient_air_temperature_k double precision,
  atmospheric_pressure_pa double precision
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_environment_130311_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  sid smallint,
  temperature_source text,
  humidity_source text,
  temperature_k double precision,
  humidity_ratio double precision,
  atmospheric_pressure_pa double precision
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_temperature_130312_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  sid smallint,
  instance smallint,
  source text,
  actual_temperature_k double precision,
  set_temperature_k double precision
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_pressure_130314_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  sid smallint,
  instance smallint,
  source text,
  pressure_pa double precision
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_temperature_ext_130316_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  source_address smallint,
  sid smallint,
  instance smallint,
  source text,
  temperature_k double precision,
  set_temperature_k double precision
);

CREATE UNLOGGED TABLE IF NOT EXISTS n2k_research_fields_stage_v2 (
  raw_file_id bigint NOT NULL,
  message_index integer NOT NULL,
  time timestamptz NOT NULL,
  pgn integer NOT NULL,
  source_address smallint,
  field_name text NOT NULL,
  value_double double precision,
  value_text text,
  value_bool boolean
);

-- Example set-based summary refresh after COPY/merge:
--
-- INSERT INTO n2k_file_pgn_summary_v2(raw_file_id, pgn, source_key, source_address, frame_count, first_time, last_time)
-- SELECT raw_file_id, pgn, coalesce(source_address, -1), source_address, count(*), min(time), max(time)
-- FROM n2k_frames_stage_v2
-- WHERE raw_file_id = $1
-- GROUP BY raw_file_id, pgn, source_address
-- ON CONFLICT (raw_file_id, pgn, source_key) DO UPDATE SET
--   frame_count = EXCLUDED.frame_count,
--   first_time = EXCLUDED.first_time,
--   last_time = EXCLUDED.last_time;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO boat_ingest;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO boat_ingest;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana_reader;
