-- MasterBus v1 staging merge helpers.
--
-- COPY replayed MasterBus JSONL TSV into masterbus_*_stage_v1 tables first,
-- then call:
--
--   SELECT masterbus_merge_staged_log_v1(<masterbus_log_file_id>);
--
-- The JSONL files remain the replay source. These typed SQL tables are
-- rebuildable derived history for Grafana/SQL/app queries.

CREATE OR REPLACE FUNCTION masterbus_merge_staged_log_v1(p_log_file_id bigint)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_first timestamptz;
  v_last timestamptz;
  v_count bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM masterbus_log_files_v1 WHERE masterbus_log_file_id = p_log_file_id) THEN
    RAISE EXCEPTION 'masterbus_log_files_v1 row % does not exist', p_log_file_id;
  END IF;

  UPDATE masterbus_log_files_v1
  SET import_status = 'staged', updated_at = now()
  WHERE masterbus_log_file_id = p_log_file_id;

  INSERT INTO masterbus_alternator_samples_v1(
    time, alternator_key, masterbus_device_id, source, raw_log_file_id, raw_line_number,
    sense_voltage_v, alternator_voltage_v, voltage_v, current_a, field_current_a,
    alternator_temperature_k, temperature_k
  )
  SELECT time, alternator_key, max(masterbus_device_id), source, raw_log_file_id, min(raw_line_number),
    max(sense_voltage_v), max(alternator_voltage_v), max(voltage_v), max(current_a), max(field_current_a),
    max(alternator_temperature_k), max(temperature_k)
  FROM masterbus_alternator_stage_v1
  WHERE raw_log_file_id = p_log_file_id
  GROUP BY time, alternator_key, source, raw_log_file_id
  ON CONFLICT (time, alternator_key) DO UPDATE SET
    masterbus_device_id = coalesce(EXCLUDED.masterbus_device_id, masterbus_alternator_samples_v1.masterbus_device_id),
    source = EXCLUDED.source,
    raw_log_file_id = EXCLUDED.raw_log_file_id,
    raw_line_number = coalesce(EXCLUDED.raw_line_number, masterbus_alternator_samples_v1.raw_line_number),
    sense_voltage_v = coalesce(EXCLUDED.sense_voltage_v, masterbus_alternator_samples_v1.sense_voltage_v),
    alternator_voltage_v = coalesce(EXCLUDED.alternator_voltage_v, masterbus_alternator_samples_v1.alternator_voltage_v),
    voltage_v = coalesce(EXCLUDED.voltage_v, masterbus_alternator_samples_v1.voltage_v),
    current_a = coalesce(EXCLUDED.current_a, masterbus_alternator_samples_v1.current_a),
    field_current_a = coalesce(EXCLUDED.field_current_a, masterbus_alternator_samples_v1.field_current_a),
    alternator_temperature_k = coalesce(EXCLUDED.alternator_temperature_k, masterbus_alternator_samples_v1.alternator_temperature_k),
    temperature_k = coalesce(EXCLUDED.temperature_k, masterbus_alternator_samples_v1.temperature_k);

  INSERT INTO masterbus_battery_samples_v1(
    time, battery_key, masterbus_device_id, source, raw_log_file_id, raw_line_number,
    voltage_v, current_a, temperature_k, state_of_charge_ratio, time_remaining_s
  )
  SELECT time, battery_key, max(masterbus_device_id), source, raw_log_file_id, min(raw_line_number),
    max(voltage_v), max(current_a), max(temperature_k), max(state_of_charge_ratio), max(time_remaining_s)
  FROM masterbus_battery_stage_v1
  WHERE raw_log_file_id = p_log_file_id
  GROUP BY time, battery_key, source, raw_log_file_id
  ON CONFLICT (time, battery_key) DO UPDATE SET
    masterbus_device_id = coalesce(EXCLUDED.masterbus_device_id, masterbus_battery_samples_v1.masterbus_device_id),
    source = EXCLUDED.source,
    raw_log_file_id = EXCLUDED.raw_log_file_id,
    raw_line_number = coalesce(EXCLUDED.raw_line_number, masterbus_battery_samples_v1.raw_line_number),
    voltage_v = coalesce(EXCLUDED.voltage_v, masterbus_battery_samples_v1.voltage_v),
    current_a = coalesce(EXCLUDED.current_a, masterbus_battery_samples_v1.current_a),
    temperature_k = coalesce(EXCLUDED.temperature_k, masterbus_battery_samples_v1.temperature_k),
    state_of_charge_ratio = coalesce(EXCLUDED.state_of_charge_ratio, masterbus_battery_samples_v1.state_of_charge_ratio),
    time_remaining_s = coalesce(EXCLUDED.time_remaining_s, masterbus_battery_samples_v1.time_remaining_s);

  INSERT INTO masterbus_inverter_charger_samples_v1(
    time, device_key, masterbus_device_id, source, raw_log_file_id, raw_line_number,
    inverter_enabled, charger_enabled, ac_in_voltage_v, ac_in_current_a,
    ac_in_current_limit_a, ac_in_frequency_hz, ac_out_voltage_v, ac_out_power_w,
    ac_out_frequency_hz, dc_voltage_v, dc_current_a
  )
  SELECT time, device_key, max(masterbus_device_id), source, raw_log_file_id, min(raw_line_number),
    bool_or(inverter_enabled), bool_or(charger_enabled), max(ac_in_voltage_v), max(ac_in_current_a),
    max(ac_in_current_limit_a), max(ac_in_frequency_hz), max(ac_out_voltage_v), max(ac_out_power_w),
    max(ac_out_frequency_hz), max(dc_voltage_v), max(dc_current_a)
  FROM masterbus_inverter_charger_stage_v1
  WHERE raw_log_file_id = p_log_file_id
  GROUP BY time, device_key, source, raw_log_file_id
  ON CONFLICT (time, device_key) DO UPDATE SET
    masterbus_device_id = coalesce(EXCLUDED.masterbus_device_id, masterbus_inverter_charger_samples_v1.masterbus_device_id),
    source = EXCLUDED.source,
    raw_log_file_id = EXCLUDED.raw_log_file_id,
    raw_line_number = coalesce(EXCLUDED.raw_line_number, masterbus_inverter_charger_samples_v1.raw_line_number),
    inverter_enabled = coalesce(EXCLUDED.inverter_enabled, masterbus_inverter_charger_samples_v1.inverter_enabled),
    charger_enabled = coalesce(EXCLUDED.charger_enabled, masterbus_inverter_charger_samples_v1.charger_enabled),
    ac_in_voltage_v = coalesce(EXCLUDED.ac_in_voltage_v, masterbus_inverter_charger_samples_v1.ac_in_voltage_v),
    ac_in_current_a = coalesce(EXCLUDED.ac_in_current_a, masterbus_inverter_charger_samples_v1.ac_in_current_a),
    ac_in_current_limit_a = coalesce(EXCLUDED.ac_in_current_limit_a, masterbus_inverter_charger_samples_v1.ac_in_current_limit_a),
    ac_in_frequency_hz = coalesce(EXCLUDED.ac_in_frequency_hz, masterbus_inverter_charger_samples_v1.ac_in_frequency_hz),
    ac_out_voltage_v = coalesce(EXCLUDED.ac_out_voltage_v, masterbus_inverter_charger_samples_v1.ac_out_voltage_v),
    ac_out_power_w = coalesce(EXCLUDED.ac_out_power_w, masterbus_inverter_charger_samples_v1.ac_out_power_w),
    ac_out_frequency_hz = coalesce(EXCLUDED.ac_out_frequency_hz, masterbus_inverter_charger_samples_v1.ac_out_frequency_hz),
    dc_voltage_v = coalesce(EXCLUDED.dc_voltage_v, masterbus_inverter_charger_samples_v1.dc_voltage_v),
    dc_current_a = coalesce(EXCLUDED.dc_current_a, masterbus_inverter_charger_samples_v1.dc_current_a);

  INSERT INTO masterbus_solar_samples_v1(
    time, controller_key, masterbus_device_id, source, raw_log_file_id, raw_line_number,
    battery_voltage_v, panel_voltage_v, charge_current_a, yield_total_wh
  )
  SELECT time, controller_key, max(masterbus_device_id), source, raw_log_file_id, min(raw_line_number),
    max(battery_voltage_v), max(panel_voltage_v), max(charge_current_a), max(yield_total_wh)
  FROM masterbus_solar_stage_v1
  WHERE raw_log_file_id = p_log_file_id
  GROUP BY time, controller_key, source, raw_log_file_id
  ON CONFLICT (time, controller_key) DO UPDATE SET
    masterbus_device_id = coalesce(EXCLUDED.masterbus_device_id, masterbus_solar_samples_v1.masterbus_device_id),
    source = EXCLUDED.source,
    raw_log_file_id = EXCLUDED.raw_log_file_id,
    raw_line_number = coalesce(EXCLUDED.raw_line_number, masterbus_solar_samples_v1.raw_line_number),
    battery_voltage_v = coalesce(EXCLUDED.battery_voltage_v, masterbus_solar_samples_v1.battery_voltage_v),
    panel_voltage_v = coalesce(EXCLUDED.panel_voltage_v, masterbus_solar_samples_v1.panel_voltage_v),
    charge_current_a = coalesce(EXCLUDED.charge_current_a, masterbus_solar_samples_v1.charge_current_a),
    yield_total_wh = coalesce(EXCLUDED.yield_total_wh, masterbus_solar_samples_v1.yield_total_wh);

  SELECT min(time), max(time), count(DISTINCT raw_line_number) INTO v_first, v_last, v_count
  FROM (
    SELECT time, raw_line_number FROM masterbus_alternator_samples_v1 WHERE raw_log_file_id = p_log_file_id
    UNION ALL SELECT time, raw_line_number FROM masterbus_battery_samples_v1 WHERE raw_log_file_id = p_log_file_id
    UNION ALL SELECT time, raw_line_number FROM masterbus_inverter_charger_samples_v1 WHERE raw_log_file_id = p_log_file_id
    UNION ALL SELECT time, raw_line_number FROM masterbus_solar_samples_v1 WHERE raw_log_file_id = p_log_file_id
  ) samples;

  UPDATE masterbus_log_files_v1
  SET first_event_time = v_first,
      last_event_time = v_last,
      line_count = v_count,
      import_status = 'imported',
      imported_at = now(),
      updated_at = now()
  WHERE masterbus_log_file_id = p_log_file_id;

  DELETE FROM masterbus_alternator_stage_v1 WHERE raw_log_file_id = p_log_file_id;
  DELETE FROM masterbus_battery_stage_v1 WHERE raw_log_file_id = p_log_file_id;
  DELETE FROM masterbus_inverter_charger_stage_v1 WHERE raw_log_file_id = p_log_file_id;
  DELETE FROM masterbus_solar_stage_v1 WHERE raw_log_file_id = p_log_file_id;
EXCEPTION WHEN OTHERS THEN
  UPDATE masterbus_log_files_v1
  SET import_status = 'failed', updated_at = now()
  WHERE masterbus_log_file_id = p_log_file_id;
  RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION masterbus_merge_staged_log_v1(bigint) TO boat_ingest;
