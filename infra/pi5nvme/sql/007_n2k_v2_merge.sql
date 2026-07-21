-- N2K v2 staging merge helpers.
--
-- COPY TSV files into the *_stage_v2 tables first, then call:
--
--   SELECT n2k_merge_staged_file_v2(<raw_file_id>);
--
-- This function is intentionally set-based: PostgreSQL owns the merge,
-- duplicate handling, summaries, and import-status update. Raw candump logs
-- remain the source of truth; these tables are rebuildable derived state.

CREATE OR REPLACE FUNCTION n2k_merge_staged_file_v2(p_raw_file_id bigint)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_run_id bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM n2k_raw_files_v2 WHERE raw_file_id = p_raw_file_id) THEN
    RAISE EXCEPTION 'n2k_raw_files_v2 row % does not exist', p_raw_file_id;
  END IF;

  INSERT INTO n2k_import_runs_v2(raw_file_id, status, evidence)
  VALUES (p_raw_file_id, 'running', jsonb_build_object('merge_function', 'n2k_merge_staged_file_v2'))
  RETURNING import_run_id INTO v_run_id;

  UPDATE n2k_raw_files_v2
  SET import_status = 'staged', updated_at = now(), error_summary = NULL
  WHERE raw_file_id = p_raw_file_id;

  INSERT INTO n2k_frames_v2(raw_file_id, message_index, time, pgn, source_address, destination_address, priority, can_id)
  SELECT raw_file_id, message_index, time, pgn, source_address, destination_address, priority, can_id
  FROM n2k_frames_stage_v2
  WHERE raw_file_id = p_raw_file_id
  ON CONFLICT (raw_file_id, message_index) DO UPDATE SET
    time = EXCLUDED.time,
    pgn = EXCLUDED.pgn,
    source_address = EXCLUDED.source_address,
    destination_address = EXCLUDED.destination_address,
    priority = EXCLUDED.priority,
    can_id = EXCLUDED.can_id;

  INSERT INTO n2k_position_rapid_129025_v2(frame_id, time, source_address, device_id, latitude_deg, longitude_deg)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.latitude_deg, s.longitude_deg
  FROM n2k_position_rapid_129025_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id AND s.latitude_deg IS NOT NULL AND s.longitude_deg IS NOT NULL
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    latitude_deg = EXCLUDED.latitude_deg,
    longitude_deg = EXCLUDED.longitude_deg;

  INSERT INTO n2k_cog_sog_129026_v2(frame_id, time, source_address, device_id, sequence_id, reference, cog_rad, sog_ms)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.sequence_id, s.reference, s.cog_rad, s.sog_ms
  FROM n2k_cog_sog_129026_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    sequence_id = EXCLUDED.sequence_id,
    reference = EXCLUDED.reference,
    cog_rad = EXCLUDED.cog_rad,
    sog_ms = EXCLUDED.sog_ms;

  INSERT INTO n2k_gnss_position_129029_v2(frame_id, time, source_address, device_id, sequence_id, days_since_1970, seconds_since_midnight, latitude_deg, longitude_deg, altitude_m, gnss_type, method, integrity, satellites, hdop, pdop, geoidal_separation_m, reference_stations)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.sequence_id, s.days_since_1970, s.seconds_since_midnight, s.latitude_deg, s.longitude_deg, s.altitude_m, s.gnss_type, s.method, s.integrity, s.satellites, s.hdop, s.pdop, s.geoidal_separation_m, s.reference_stations
  FROM n2k_gnss_position_129029_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    sequence_id = EXCLUDED.sequence_id,
    days_since_1970 = EXCLUDED.days_since_1970,
    seconds_since_midnight = EXCLUDED.seconds_since_midnight,
    latitude_deg = EXCLUDED.latitude_deg,
    longitude_deg = EXCLUDED.longitude_deg,
    altitude_m = EXCLUDED.altitude_m,
    gnss_type = EXCLUDED.gnss_type,
    method = EXCLUDED.method,
    integrity = EXCLUDED.integrity,
    satellites = EXCLUDED.satellites,
    hdop = EXCLUDED.hdop,
    pdop = EXCLUDED.pdop,
    geoidal_separation_m = EXCLUDED.geoidal_separation_m,
    reference_stations = EXCLUDED.reference_stations;

  INSERT INTO n2k_heading_127250_v2(frame_id, time, source_address, device_id, sequence_id, heading_rad, deviation_rad, variation_rad, reference)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.sequence_id, s.heading_rad, s.deviation_rad, s.variation_rad, s.reference
  FROM n2k_heading_127250_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    sequence_id = EXCLUDED.sequence_id,
    heading_rad = EXCLUDED.heading_rad,
    deviation_rad = EXCLUDED.deviation_rad,
    variation_rad = EXCLUDED.variation_rad,
    reference = EXCLUDED.reference;

  INSERT INTO n2k_rudder_127245_v2(frame_id, time, source_address, device_id, instance, direction_order, angle_order_rad, position_rad)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.instance, s.direction_order, s.angle_order_rad, s.position_rad
  FROM n2k_rudder_127245_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    instance = EXCLUDED.instance,
    direction_order = EXCLUDED.direction_order,
    angle_order_rad = EXCLUDED.angle_order_rad,
    position_rad = EXCLUDED.position_rad;

  INSERT INTO n2k_heading_track_control_127237_v2(frame_id, time, source_address, device_id, rudder_limit_exceeded, off_heading_limit_exceeded, off_track_limit_exceeded, override, steering_mode, turn_mode, heading_reference, commanded_rudder_direction, commanded_rudder_angle_rad, heading_to_steer_rad, track_rad, rudder_limit_rad, off_heading_limit_rad, radius_of_turn_order_m, rate_of_turn_order_rad_s, off_track_limit_m, vessel_heading_rad)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.rudder_limit_exceeded, s.off_heading_limit_exceeded, s.off_track_limit_exceeded, s.override, s.steering_mode, s.turn_mode, s.heading_reference, s.commanded_rudder_direction, s.commanded_rudder_angle_rad, s.heading_to_steer_rad, s.track_rad, s.rudder_limit_rad, s.off_heading_limit_rad, s.radius_of_turn_order_m, s.rate_of_turn_order_rad_s, s.off_track_limit_m, s.vessel_heading_rad
  FROM n2k_heading_track_control_127237_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    rudder_limit_exceeded = EXCLUDED.rudder_limit_exceeded,
    off_heading_limit_exceeded = EXCLUDED.off_heading_limit_exceeded,
    off_track_limit_exceeded = EXCLUDED.off_track_limit_exceeded,
    override = EXCLUDED.override,
    steering_mode = EXCLUDED.steering_mode,
    turn_mode = EXCLUDED.turn_mode,
    heading_reference = EXCLUDED.heading_reference,
    commanded_rudder_direction = EXCLUDED.commanded_rudder_direction,
    commanded_rudder_angle_rad = EXCLUDED.commanded_rudder_angle_rad,
    heading_to_steer_rad = EXCLUDED.heading_to_steer_rad,
    track_rad = EXCLUDED.track_rad,
    rudder_limit_rad = EXCLUDED.rudder_limit_rad,
    off_heading_limit_rad = EXCLUDED.off_heading_limit_rad,
    radius_of_turn_order_m = EXCLUDED.radius_of_turn_order_m,
    rate_of_turn_order_rad_s = EXCLUDED.rate_of_turn_order_rad_s,
    off_track_limit_m = EXCLUDED.off_track_limit_m,
    vessel_heading_rad = EXCLUDED.vessel_heading_rad;

  INSERT INTO n2k_rate_of_turn_127251_v2(frame_id, time, source_address, device_id, sid, rate_rad_s)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.sid, s.rate_rad_s
  FROM n2k_rate_of_turn_127251_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    sid = EXCLUDED.sid,
    rate_rad_s = EXCLUDED.rate_rad_s;

  INSERT INTO n2k_switch_bank_status_127501_v2(frame_id, time, source_address, device_id, instance, indicator1, indicator2, indicator3, indicator4, indicator5, indicator6, indicator7, indicator8, indicator9, indicator10, indicator11, indicator12, indicator13, indicator14, indicator15, indicator16, indicator17, indicator18, indicator19, indicator20, indicator21, indicator22, indicator23, indicator24, indicator25, indicator26, indicator27, indicator28)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.instance, s.indicator1, s.indicator2, s.indicator3, s.indicator4, s.indicator5, s.indicator6, s.indicator7, s.indicator8, s.indicator9, s.indicator10, s.indicator11, s.indicator12, s.indicator13, s.indicator14, s.indicator15, s.indicator16, s.indicator17, s.indicator18, s.indicator19, s.indicator20, s.indicator21, s.indicator22, s.indicator23, s.indicator24, s.indicator25, s.indicator26, s.indicator27, s.indicator28
  FROM n2k_switch_bank_status_127501_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    instance = EXCLUDED.instance,
    indicator1 = EXCLUDED.indicator1,
    indicator2 = EXCLUDED.indicator2,
    indicator3 = EXCLUDED.indicator3,
    indicator4 = EXCLUDED.indicator4,
    indicator5 = EXCLUDED.indicator5,
    indicator6 = EXCLUDED.indicator6,
    indicator7 = EXCLUDED.indicator7,
    indicator8 = EXCLUDED.indicator8,
    indicator9 = EXCLUDED.indicator9,
    indicator10 = EXCLUDED.indicator10,
    indicator11 = EXCLUDED.indicator11,
    indicator12 = EXCLUDED.indicator12,
    indicator13 = EXCLUDED.indicator13,
    indicator14 = EXCLUDED.indicator14,
    indicator15 = EXCLUDED.indicator15,
    indicator16 = EXCLUDED.indicator16,
    indicator17 = EXCLUDED.indicator17,
    indicator18 = EXCLUDED.indicator18,
    indicator19 = EXCLUDED.indicator19,
    indicator20 = EXCLUDED.indicator20,
    indicator21 = EXCLUDED.indicator21,
    indicator22 = EXCLUDED.indicator22,
    indicator23 = EXCLUDED.indicator23,
    indicator24 = EXCLUDED.indicator24,
    indicator25 = EXCLUDED.indicator25,
    indicator26 = EXCLUDED.indicator26,
    indicator27 = EXCLUDED.indicator27,
    indicator28 = EXCLUDED.indicator28;

  INSERT INTO n2k_attitude_127257_v2(frame_id, time, source_address, device_id, sid, yaw_rad, pitch_rad, roll_rad)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.sid, s.yaw_rad, s.pitch_rad, s.roll_rad
  FROM n2k_attitude_127257_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    sid = EXCLUDED.sid,
    yaw_rad = EXCLUDED.yaw_rad,
    pitch_rad = EXCLUDED.pitch_rad,
    roll_rad = EXCLUDED.roll_rad;

  INSERT INTO n2k_magnetic_variation_127258_v2(frame_id, time, source_address, device_id, sid, source, variation_rad)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.sid, s.source, s.variation_rad
  FROM n2k_magnetic_variation_127258_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    sid = EXCLUDED.sid,
    source = EXCLUDED.source,
    variation_rad = EXCLUDED.variation_rad;

  INSERT INTO n2k_water_speed_128259_v2(frame_id, time, source_address, device_id, speed_water_referenced_ms, speed_ground_referenced_ms, speed_water_type)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.speed_water_referenced_ms, s.speed_ground_referenced_ms, s.speed_water_type
  FROM n2k_water_speed_128259_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    speed_water_referenced_ms = EXCLUDED.speed_water_referenced_ms,
    speed_ground_referenced_ms = EXCLUDED.speed_ground_referenced_ms,
    speed_water_type = EXCLUDED.speed_water_type;

  INSERT INTO n2k_water_depth_128267_v2(frame_id, time, source_address, device_id, sid, depth_below_transducer_m, offset_m, range_m)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.sid, s.depth_below_transducer_m, s.offset_m, s.range_m
  FROM n2k_water_depth_128267_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    sid = EXCLUDED.sid,
    depth_below_transducer_m = EXCLUDED.depth_below_transducer_m,
    offset_m = EXCLUDED.offset_m,
    range_m = EXCLUDED.range_m;

  INSERT INTO n2k_distance_log_128275_v2(frame_id, time, source_address, device_id, days_since_1970, seconds_since_midnight, log_m, trip_log_m)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.days_since_1970, s.seconds_since_midnight, s.log_m, s.trip_log_m
  FROM n2k_distance_log_128275_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    days_since_1970 = EXCLUDED.days_since_1970,
    seconds_since_midnight = EXCLUDED.seconds_since_midnight,
    log_m = EXCLUDED.log_m,
    trip_log_m = EXCLUDED.trip_log_m;

  INSERT INTO n2k_navigation_data_129284_v2(frame_id, time, source_address, device_id, sid, distance_to_waypoint_m, course_bearing_reference, perpendicular_crossed, arrival_circle_entered, calculation_type, eta_seconds_since_midnight, eta_days_since_1970, bearing_origin_to_destination_rad, bearing_position_to_destination_rad, origin_waypoint_number, destination_waypoint_number, destination_latitude_deg, destination_longitude_deg, waypoint_closing_velocity_ms)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.sid, s.distance_to_waypoint_m, s.course_bearing_reference, s.perpendicular_crossed, s.arrival_circle_entered, s.calculation_type, s.eta_seconds_since_midnight, s.eta_days_since_1970, s.bearing_origin_to_destination_rad, s.bearing_position_to_destination_rad, s.origin_waypoint_number, s.destination_waypoint_number, s.destination_latitude_deg, s.destination_longitude_deg, s.waypoint_closing_velocity_ms
  FROM n2k_navigation_data_129284_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    sid = EXCLUDED.sid,
    distance_to_waypoint_m = EXCLUDED.distance_to_waypoint_m,
    course_bearing_reference = EXCLUDED.course_bearing_reference,
    perpendicular_crossed = EXCLUDED.perpendicular_crossed,
    arrival_circle_entered = EXCLUDED.arrival_circle_entered,
    calculation_type = EXCLUDED.calculation_type,
    eta_seconds_since_midnight = EXCLUDED.eta_seconds_since_midnight,
    eta_days_since_1970 = EXCLUDED.eta_days_since_1970,
    bearing_origin_to_destination_rad = EXCLUDED.bearing_origin_to_destination_rad,
    bearing_position_to_destination_rad = EXCLUDED.bearing_position_to_destination_rad,
    origin_waypoint_number = EXCLUDED.origin_waypoint_number,
    destination_waypoint_number = EXCLUDED.destination_waypoint_number,
    destination_latitude_deg = EXCLUDED.destination_latitude_deg,
    destination_longitude_deg = EXCLUDED.destination_longitude_deg,
    waypoint_closing_velocity_ms = EXCLUDED.waypoint_closing_velocity_ms;

  INSERT INTO n2k_route_waypoint_129285_v2(frame_id, time, source_address, device_id, start_rps, item_count, database_id, route_id, navigation_direction, supplementary_data_available, route_name, waypoint_index, waypoint_id, waypoint_name, waypoint_latitude_deg, waypoint_longitude_deg)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.start_rps, s.item_count, s.database_id, s.route_id, s.navigation_direction, s.supplementary_data_available, s.route_name, s.waypoint_index, s.waypoint_id, s.waypoint_name, s.waypoint_latitude_deg, s.waypoint_longitude_deg
  FROM n2k_route_waypoint_129285_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id, waypoint_index) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    start_rps = EXCLUDED.start_rps,
    item_count = EXCLUDED.item_count,
    database_id = EXCLUDED.database_id,
    route_id = EXCLUDED.route_id,
    navigation_direction = EXCLUDED.navigation_direction,
    supplementary_data_available = EXCLUDED.supplementary_data_available,
    route_name = EXCLUDED.route_name,
    waypoint_id = EXCLUDED.waypoint_id,
    waypoint_name = EXCLUDED.waypoint_name,
    waypoint_latitude_deg = EXCLUDED.waypoint_latitude_deg,
    waypoint_longitude_deg = EXCLUDED.waypoint_longitude_deg;

  INSERT INTO n2k_ais_class_a_position_129038_v2(frame_id, time, source_address, device_id, message_id, repeat_indicator, user_id, longitude_deg, latitude_deg, position_accuracy, raim, time_stamp, cog_rad, sog_ms, communication_state, ais_transceiver_information, heading_rad, rate_of_turn_rad_s, nav_status, special_maneuver_indicator, sequence_id)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.message_id, s.repeat_indicator, s.user_id, s.longitude_deg, s.latitude_deg, s.position_accuracy, s.raim, s.time_stamp, s.cog_rad, s.sog_ms, s.communication_state, s.ais_transceiver_information, s.heading_rad, s.rate_of_turn_rad_s, s.nav_status, s.special_maneuver_indicator, s.sequence_id
  FROM n2k_ais_class_a_position_129038_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address, message_id = EXCLUDED.message_id, repeat_indicator = EXCLUDED.repeat_indicator, user_id = EXCLUDED.user_id, longitude_deg = EXCLUDED.longitude_deg, latitude_deg = EXCLUDED.latitude_deg, position_accuracy = EXCLUDED.position_accuracy, raim = EXCLUDED.raim, time_stamp = EXCLUDED.time_stamp, cog_rad = EXCLUDED.cog_rad, sog_ms = EXCLUDED.sog_ms, communication_state = EXCLUDED.communication_state, ais_transceiver_information = EXCLUDED.ais_transceiver_information, heading_rad = EXCLUDED.heading_rad, rate_of_turn_rad_s = EXCLUDED.rate_of_turn_rad_s, nav_status = EXCLUDED.nav_status, special_maneuver_indicator = EXCLUDED.special_maneuver_indicator, sequence_id = EXCLUDED.sequence_id;

  INSERT INTO n2k_ais_class_b_position_129039_v2(frame_id, time, source_address, device_id, message_id, repeat_indicator, user_id, longitude_deg, latitude_deg, position_accuracy, raim, time_stamp, cog_rad, sog_ms, communication_state, ais_transceiver_information, heading_rad, unit_type, integrated_display, dsc, band, can_handle_msg_22, ais_mode, ais_communication_state)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.message_id, s.repeat_indicator, s.user_id, s.longitude_deg, s.latitude_deg, s.position_accuracy, s.raim, s.time_stamp, s.cog_rad, s.sog_ms, s.communication_state, s.ais_transceiver_information, s.heading_rad, s.unit_type, s.integrated_display, s.dsc, s.band, s.can_handle_msg_22, s.ais_mode, s.ais_communication_state
  FROM n2k_ais_class_b_position_129039_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address, message_id = EXCLUDED.message_id, repeat_indicator = EXCLUDED.repeat_indicator, user_id = EXCLUDED.user_id, longitude_deg = EXCLUDED.longitude_deg, latitude_deg = EXCLUDED.latitude_deg, position_accuracy = EXCLUDED.position_accuracy, raim = EXCLUDED.raim, time_stamp = EXCLUDED.time_stamp, cog_rad = EXCLUDED.cog_rad, sog_ms = EXCLUDED.sog_ms, communication_state = EXCLUDED.communication_state, ais_transceiver_information = EXCLUDED.ais_transceiver_information, heading_rad = EXCLUDED.heading_rad, unit_type = EXCLUDED.unit_type, integrated_display = EXCLUDED.integrated_display, dsc = EXCLUDED.dsc, band = EXCLUDED.band, can_handle_msg_22 = EXCLUDED.can_handle_msg_22, ais_mode = EXCLUDED.ais_mode, ais_communication_state = EXCLUDED.ais_communication_state;

  INSERT INTO n2k_ais_class_a_static_129794_v2(frame_id, time, source_address, device_id, message_id, repeat_indicator, user_id, imo_number, callsign, name, ship_type, length_m, beam_m, position_reference_starboard_m, position_reference_bow_m, eta_days_since_1970, eta_seconds_since_midnight, draft_m, destination, ais_version_indicator, gnss_type, dte, ais_transceiver_information)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.message_id, s.repeat_indicator, s.user_id, s.imo_number, s.callsign, s.name, s.ship_type, s.length_m, s.beam_m, s.position_reference_starboard_m, s.position_reference_bow_m, s.eta_days_since_1970, s.eta_seconds_since_midnight, s.draft_m, s.destination, s.ais_version_indicator, s.gnss_type, s.dte, s.ais_transceiver_information
  FROM n2k_ais_class_a_static_129794_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address, message_id = EXCLUDED.message_id, repeat_indicator = EXCLUDED.repeat_indicator, user_id = EXCLUDED.user_id, imo_number = EXCLUDED.imo_number, callsign = EXCLUDED.callsign, name = EXCLUDED.name, ship_type = EXCLUDED.ship_type, length_m = EXCLUDED.length_m, beam_m = EXCLUDED.beam_m, position_reference_starboard_m = EXCLUDED.position_reference_starboard_m, position_reference_bow_m = EXCLUDED.position_reference_bow_m, eta_days_since_1970 = EXCLUDED.eta_days_since_1970, eta_seconds_since_midnight = EXCLUDED.eta_seconds_since_midnight, draft_m = EXCLUDED.draft_m, destination = EXCLUDED.destination, ais_version_indicator = EXCLUDED.ais_version_indicator, gnss_type = EXCLUDED.gnss_type, dte = EXCLUDED.dte, ais_transceiver_information = EXCLUDED.ais_transceiver_information;

  INSERT INTO n2k_ais_class_b_static_a_129809_v2(frame_id, time, source_address, device_id, message_id, repeat_indicator, user_id, name, ais_transceiver_information, sequence_id)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.message_id, s.repeat_indicator, s.user_id, s.name, s.ais_transceiver_information, s.sequence_id
  FROM n2k_ais_class_b_static_a_129809_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address, message_id = EXCLUDED.message_id, repeat_indicator = EXCLUDED.repeat_indicator, user_id = EXCLUDED.user_id, name = EXCLUDED.name, ais_transceiver_information = EXCLUDED.ais_transceiver_information, sequence_id = EXCLUDED.sequence_id;

  INSERT INTO n2k_ais_class_b_static_b_129810_v2(frame_id, time, source_address, device_id, message_id, repeat_indicator, user_id, ship_type, vendor_id, callsign, length_m, beam_m, position_reference_starboard_m, position_reference_bow_m, mothership_user_id, gnss_type, ais_transceiver_information, sequence_id)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.message_id, s.repeat_indicator, s.user_id, s.ship_type, s.vendor_id, s.callsign, s.length_m, s.beam_m, s.position_reference_starboard_m, s.position_reference_bow_m, s.mothership_user_id, s.gnss_type, s.ais_transceiver_information, s.sequence_id
  FROM n2k_ais_class_b_static_b_129810_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address, message_id = EXCLUDED.message_id, repeat_indicator = EXCLUDED.repeat_indicator, user_id = EXCLUDED.user_id, ship_type = EXCLUDED.ship_type, vendor_id = EXCLUDED.vendor_id, callsign = EXCLUDED.callsign, length_m = EXCLUDED.length_m, beam_m = EXCLUDED.beam_m, position_reference_starboard_m = EXCLUDED.position_reference_starboard_m, position_reference_bow_m = EXCLUDED.position_reference_bow_m, mothership_user_id = EXCLUDED.mothership_user_id, gnss_type = EXCLUDED.gnss_type, ais_transceiver_information = EXCLUDED.ais_transceiver_information, sequence_id = EXCLUDED.sequence_id;

  INSERT INTO n2k_gnss_dops_129539_v2(frame_id, time, source_address, device_id, sid, desired_mode, actual_mode, hdop, vdop, tdop)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.sid, s.desired_mode, s.actual_mode, s.hdop, s.vdop, s.tdop
  FROM n2k_gnss_dops_129539_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    sid = EXCLUDED.sid,
    desired_mode = EXCLUDED.desired_mode,
    actual_mode = EXCLUDED.actual_mode,
    hdop = EXCLUDED.hdop,
    vdop = EXCLUDED.vdop,
    tdop = EXCLUDED.tdop;

  INSERT INTO n2k_gnss_satellites_129540_v2(frame_id, time, source_address, device_id, sid, range_residual_mode, sats_in_view, satellite_index, prn, elevation_rad, azimuth_rad, snr_db, range_residual_m, status)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.sid, s.range_residual_mode, s.sats_in_view, s.satellite_index, s.prn, s.elevation_rad, s.azimuth_rad, s.snr_db, s.range_residual_m, s.status
  FROM n2k_gnss_satellites_129540_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id, satellite_index) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    sid = EXCLUDED.sid,
    range_residual_mode = EXCLUDED.range_residual_mode,
    sats_in_view = EXCLUDED.sats_in_view,
    prn = EXCLUDED.prn,
    elevation_rad = EXCLUDED.elevation_rad,
    azimuth_rad = EXCLUDED.azimuth_rad,
    snr_db = EXCLUDED.snr_db,
    range_residual_m = EXCLUDED.range_residual_m,
    status = EXCLUDED.status;

  INSERT INTO n2k_wind_130306_v2(frame_id, time, source_address, device_id, sid, wind_speed_ms, wind_angle_rad, reference)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.sid, s.wind_speed_ms, s.wind_angle_rad, s.reference
  FROM n2k_wind_130306_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    sid = EXCLUDED.sid,
    wind_speed_ms = EXCLUDED.wind_speed_ms,
    wind_angle_rad = EXCLUDED.wind_angle_rad,
    reference = EXCLUDED.reference;

  INSERT INTO n2k_environment_130310_v2(frame_id, time, source_address, device_id, sid, water_temperature_k, outside_ambient_air_temperature_k, atmospheric_pressure_pa)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.sid, s.water_temperature_k, s.outside_ambient_air_temperature_k, s.atmospheric_pressure_pa
  FROM n2k_environment_130310_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    sid = EXCLUDED.sid,
    water_temperature_k = EXCLUDED.water_temperature_k,
    outside_ambient_air_temperature_k = EXCLUDED.outside_ambient_air_temperature_k,
    atmospheric_pressure_pa = EXCLUDED.atmospheric_pressure_pa;

  INSERT INTO n2k_environment_130311_v2(frame_id, time, source_address, device_id, sid, temperature_source, humidity_source, temperature_k, humidity_ratio, atmospheric_pressure_pa)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.sid, s.temperature_source, s.humidity_source, s.temperature_k, s.humidity_ratio, s.atmospheric_pressure_pa
  FROM n2k_environment_130311_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    sid = EXCLUDED.sid,
    temperature_source = EXCLUDED.temperature_source,
    humidity_source = EXCLUDED.humidity_source,
    temperature_k = EXCLUDED.temperature_k,
    humidity_ratio = EXCLUDED.humidity_ratio,
    atmospheric_pressure_pa = EXCLUDED.atmospheric_pressure_pa;

  INSERT INTO n2k_temperature_130312_v2(frame_id, time, source_address, device_id, sid, instance, source, actual_temperature_k, set_temperature_k)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.sid, s.instance, s.source, s.actual_temperature_k, s.set_temperature_k
  FROM n2k_temperature_130312_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    sid = EXCLUDED.sid,
    instance = EXCLUDED.instance,
    source = EXCLUDED.source,
    actual_temperature_k = EXCLUDED.actual_temperature_k,
    set_temperature_k = EXCLUDED.set_temperature_k;

  INSERT INTO n2k_pressure_130314_v2(frame_id, time, source_address, device_id, sid, instance, source, pressure_pa)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.sid, s.instance, s.source, s.pressure_pa
  FROM n2k_pressure_130314_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    sid = EXCLUDED.sid,
    instance = EXCLUDED.instance,
    source = EXCLUDED.source,
    pressure_pa = EXCLUDED.pressure_pa;

  INSERT INTO n2k_temperature_ext_130316_v2(frame_id, time, source_address, device_id, sid, instance, source, temperature_k, set_temperature_k)
  SELECT f.frame_id, s.time, s.source_address, NULL, s.sid, s.instance, s.source, s.temperature_k, s.set_temperature_k
  FROM n2k_temperature_ext_130316_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id) DO UPDATE SET
    source_address = EXCLUDED.source_address,
    sid = EXCLUDED.sid,
    instance = EXCLUDED.instance,
    source = EXCLUDED.source,
    temperature_k = EXCLUDED.temperature_k,
    set_temperature_k = EXCLUDED.set_temperature_k;

  INSERT INTO n2k_research_fields_v2(frame_id, time, pgn, source_address, field_name, value_double, value_text, value_bool)
  SELECT f.frame_id, s.time, s.pgn, s.source_address, s.field_name, s.value_double, s.value_text, s.value_bool
  FROM n2k_research_fields_stage_v2 s
  JOIN n2k_frames_v2 f USING (raw_file_id, message_index)
  WHERE s.raw_file_id = p_raw_file_id
  ON CONFLICT (time, frame_id, field_name) DO UPDATE SET
    pgn = EXCLUDED.pgn,
    source_address = EXCLUDED.source_address,
    value_double = EXCLUDED.value_double,
    value_text = EXCLUDED.value_text,
    value_bool = EXCLUDED.value_bool;

  DELETE FROM n2k_file_pgn_summary_v2 WHERE raw_file_id = p_raw_file_id;
  INSERT INTO n2k_file_pgn_summary_v2(raw_file_id, pgn, source_key, source_address, frame_count, first_time, last_time)
  SELECT raw_file_id, pgn, coalesce(source_address, -1), source_address, count(*), min(time), max(time)
  FROM n2k_frames_v2
  WHERE raw_file_id = p_raw_file_id
  GROUP BY raw_file_id, pgn, source_address;

  DELETE FROM n2k_file_source_summary_v2 WHERE raw_file_id = p_raw_file_id;
  INSERT INTO n2k_file_source_summary_v2(raw_file_id, source_address, frame_count, first_time, last_time, pgns)
  SELECT raw_file_id, source_address, count(*), min(time), max(time), array_agg(DISTINCT pgn ORDER BY pgn)
  FROM n2k_frames_v2
  WHERE raw_file_id = p_raw_file_id AND source_address IS NOT NULL
  GROUP BY raw_file_id, source_address;

  UPDATE n2k_raw_files_v2 r
  SET frame_count = s.frame_count,
      first_edge_time = s.first_time,
      last_edge_time = s.last_time,
      import_status = 'imported',
      imported_at = now(),
      updated_at = now(),
      error_summary = NULL
  FROM (
    SELECT raw_file_id, count(*) AS frame_count, min(time) AS first_time, max(time) AS last_time
    FROM n2k_frames_v2
    WHERE raw_file_id = p_raw_file_id
    GROUP BY raw_file_id
  ) s
  WHERE r.raw_file_id = s.raw_file_id;

  UPDATE n2k_import_runs_v2
  SET status = 'succeeded', finished_at = now(), evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('raw_file_id', p_raw_file_id)
  WHERE import_run_id = v_run_id;

  DELETE FROM n2k_frames_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_position_rapid_129025_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_cog_sog_129026_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_gnss_position_129029_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_heading_127250_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_rudder_127245_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_heading_track_control_127237_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_rate_of_turn_127251_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_switch_bank_status_127501_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_attitude_127257_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_magnetic_variation_127258_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_water_speed_128259_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_water_depth_128267_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_distance_log_128275_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_navigation_data_129284_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_route_waypoint_129285_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_ais_class_a_position_129038_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_ais_class_b_position_129039_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_ais_class_a_static_129794_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_ais_class_b_static_a_129809_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_ais_class_b_static_b_129810_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_gnss_dops_129539_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_gnss_satellites_129540_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_wind_130306_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_environment_130310_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_environment_130311_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_temperature_130312_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_pressure_130314_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_temperature_ext_130316_stage_v2 WHERE raw_file_id = p_raw_file_id;
  DELETE FROM n2k_research_fields_stage_v2 WHERE raw_file_id = p_raw_file_id;
EXCEPTION WHEN OTHERS THEN
  -- PL/pgSQL rolls back statements in this block before entering the handler,
  -- so the original running import_run row may no longer exist. Record a
  -- durable failed run here as evidence, then mark the file failed.
  INSERT INTO n2k_import_runs_v2(raw_file_id, finished_at, status, error_summary, evidence)
  VALUES (p_raw_file_id, now(), 'failed', SQLERRM, jsonb_build_object('merge_function', 'n2k_merge_staged_file_v2'));

  UPDATE n2k_raw_files_v2
  SET import_status = 'failed', error_summary = SQLERRM, updated_at = now()
  WHERE raw_file_id = p_raw_file_id;
  RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION n2k_merge_staged_file_v2(bigint) TO boat_ingest;
