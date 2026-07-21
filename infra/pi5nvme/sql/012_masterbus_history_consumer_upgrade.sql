-- Existing-install upgrade for the bounded electrical-history consumer view.
-- Grafana owns the requested time range through its $__timeFilter macro.
CREATE OR REPLACE VIEW public.v_masterbus_recent_electrical_v1 AS
SELECT time, alternator_key AS device_key, 'alternator'::text AS device_class,
       sense_voltage_v AS voltage_v, current_a, field_current_a,
       alternator_temperature_k AS temperature_k, source, raw_log_file_id, raw_line_number
FROM public.masterbus_alternator_samples_v1
UNION ALL
SELECT time, battery_key, 'battery', voltage_v, current_a, NULL,
       temperature_k, source, raw_log_file_id, raw_line_number
FROM public.masterbus_battery_samples_v1;

DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'grafana_reader') THEN
    GRANT SELECT ON public.v_masterbus_recent_electrical_v1 TO grafana_reader;
  END IF;
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'boat_ingest') THEN
    GRANT SELECT ON public.v_masterbus_recent_electrical_v1 TO boat_ingest;
  END IF;
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'jack') THEN
    GRANT SELECT ON public.v_masterbus_recent_electrical_v1 TO jack;
  END IF;
END $$;
