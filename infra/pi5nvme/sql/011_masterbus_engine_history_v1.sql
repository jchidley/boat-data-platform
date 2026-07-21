-- Durable engine history derived only from typed native MasterBus alternator samples.
-- No Signal K engine-state output is read here. Rebuild is deterministic: all
-- derived rows are replaced from the selected typed evidence.
-- Call rebuild_masterbus_engine_history_v1 inside a transaction. It takes a
-- SHARE lock on the source table before TRUNCATE so a concurrent typed merge
-- cannot change the evidence set during the rebuild. TRUNCATE therefore takes
-- ACCESS EXCLUSIVE locks on the two derived tables; callers should use a
-- bounded transaction and expect readers of those tables to wait briefly.

CREATE TABLE IF NOT EXISTS public.masterbus_engine_transitions_v1 (
  engine_key text NOT NULL,
  event_time timestamptz NOT NULL,
  event_type text NOT NULL,
  state text,
  evidence_time timestamptz NOT NULL,
  alternator_key text NOT NULL,
  raw_log_file_id bigint REFERENCES public.masterbus_log_files_v1(masterbus_log_file_id),
  raw_line_number integer,
  threshold_v double precision NOT NULL,
  debounce_seconds double precision NOT NULL,
  source text NOT NULL DEFAULT 'masterbus-native',
  PRIMARY KEY (engine_key, event_time, event_type),
  CHECK (event_type IN ('started', 'stopped', 'data_gap')),
  CHECK (state IS NULL OR state IN ('started', 'stopped', 'unknown'))
);
CREATE INDEX IF NOT EXISTS masterbus_engine_transitions_v1_time_idx
  ON public.masterbus_engine_transitions_v1 (event_time DESC, engine_key);

CREATE TABLE IF NOT EXISTS public.masterbus_engine_runtime_intervals_v1 (
  engine_key text NOT NULL,
  started_at timestamptz NOT NULL,
  ended_at timestamptz,
  duration_seconds double precision,
  end_reason text NOT NULL,
  start_evidence_time timestamptz NOT NULL,
  end_evidence_time timestamptz,
  start_raw_log_file_id bigint REFERENCES public.masterbus_log_files_v1(masterbus_log_file_id),
  start_raw_line_number integer,
  end_raw_log_file_id bigint REFERENCES public.masterbus_log_files_v1(masterbus_log_file_id),
  end_raw_line_number integer,
  source text NOT NULL DEFAULT 'masterbus-native',
  PRIMARY KEY (engine_key, started_at),
  CHECK (end_reason IN ('stopped', 'data_gap', 'open')),
  CHECK (ended_at IS NULL OR ended_at >= started_at),
  CHECK (duration_seconds IS NULL OR duration_seconds >= 0)
);
CREATE INDEX IF NOT EXISTS masterbus_engine_runtime_v1_time_idx
  ON public.masterbus_engine_runtime_intervals_v1 (engine_key, started_at DESC);
CREATE INDEX IF NOT EXISTS masterbus_alternator_samples_v1_time_idx
  ON public.masterbus_alternator_samples_v1 (time DESC);
CREATE INDEX IF NOT EXISTS masterbus_battery_samples_v1_time_idx
  ON public.masterbus_battery_samples_v1 (time DESC);

CREATE OR REPLACE FUNCTION public.rebuild_masterbus_engine_history_v1(
  p_threshold_v double precision DEFAULT 13.25,
  p_start_debounce_seconds double precision DEFAULT 10,
  p_stop_debounce_seconds double precision DEFAULT 30,
  p_max_gap_seconds double precision DEFAULT 120
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  e record;
  s record;
  v_state text;
  v_candidate text;
  v_candidate_since timestamptz;
  v_last_time timestamptz;
  v_last_raw_file_id bigint;
  v_last_raw_line integer;
  v_last_source text;
  v_debounce double precision;
  v_transition_time timestamptz;
BEGIN
  IF p_threshold_v IS NULL OR p_threshold_v IN ('NaN'::double precision, 'Infinity'::double precision, '-Infinity'::double precision)
     OR p_start_debounce_seconds IS NULL OR p_start_debounce_seconds IN ('NaN'::double precision, 'Infinity'::double precision, '-Infinity'::double precision)
     OR p_stop_debounce_seconds IS NULL OR p_stop_debounce_seconds IN ('NaN'::double precision, 'Infinity'::double precision, '-Infinity'::double precision)
     OR p_max_gap_seconds IS NULL OR p_max_gap_seconds IN ('NaN'::double precision, 'Infinity'::double precision, '-Infinity'::double precision)
     OR p_start_debounce_seconds < 0 OR p_stop_debounce_seconds < 0 OR p_max_gap_seconds <= 0 THEN
    RAISE EXCEPTION 'invalid engine history parameters';
  END IF;

  LOCK TABLE public.masterbus_alternator_samples_v1 IN SHARE MODE;
  TRUNCATE public.masterbus_engine_runtime_intervals_v1,
           public.masterbus_engine_transitions_v1;

  FOR e IN
    SELECT * FROM (VALUES
      ('port'::text, 'alpha-port'::text),
      ('starboard'::text, 'alpha-stbd'::text)
    ) AS x(engine_key, alternator_key)
  LOOP
    v_state := NULL;
    v_candidate := NULL;
    v_candidate_since := NULL;
    v_last_time := NULL;
    v_last_raw_file_id := NULL;
    v_last_raw_line := NULL;
    v_last_source := NULL;

    FOR s IN
      SELECT time, alternator_key, raw_log_file_id, raw_line_number, source, sense_voltage_v
      FROM public.masterbus_alternator_samples_v1
      WHERE alternator_key = e.alternator_key
      ORDER BY time, raw_log_file_id NULLS LAST, raw_line_number NULLS LAST, source
    LOOP
      IF s.sense_voltage_v IS NULL THEN
        CONTINUE;
      END IF;

      -- A heartbeat gap is not evidence that the engine stopped. Close a
      -- running interval at the last known sample and reset to unknown.
      IF v_last_time IS NOT NULL
         AND EXTRACT(EPOCH FROM (s.time - v_last_time)) > p_max_gap_seconds THEN
        IF v_state = 'started' THEN
          INSERT INTO public.masterbus_engine_transitions_v1(
            engine_key, event_time, event_type, state, evidence_time,
            alternator_key, raw_log_file_id, raw_line_number,
            threshold_v, debounce_seconds, source
          ) VALUES (
            e.engine_key, v_last_time, 'data_gap', 'unknown', v_last_time,
            e.alternator_key, v_last_raw_file_id, v_last_raw_line, p_threshold_v, 0,
            v_last_source
          ) ON CONFLICT DO NOTHING;
        END IF;
        v_state := NULL;
        v_candidate := NULL;
        v_candidate_since := NULL;
      END IF;

      IF s.sense_voltage_v > p_threshold_v THEN
        -- Match the deployed live rule: strictly above threshold is started.
        IF v_state = 'started' THEN
          v_candidate := NULL;
          v_candidate_since := NULL;
        ELSIF v_candidate IS DISTINCT FROM 'started' THEN
          v_candidate := 'started';
          v_candidate_since := s.time;
        END IF;
        v_debounce := p_start_debounce_seconds;
      ELSE
        IF v_state = 'stopped' THEN
          v_candidate := NULL;
          v_candidate_since := NULL;
        ELSIF v_candidate IS DISTINCT FROM 'stopped' THEN
          v_candidate := 'stopped';
          v_candidate_since := s.time;
        END IF;
        v_debounce := p_stop_debounce_seconds;
      END IF;

      IF v_candidate IS NOT NULL
         AND EXTRACT(EPOCH FROM (s.time - v_candidate_since)) >= v_debounce THEN
        v_transition_time := v_candidate_since + make_interval(secs => v_debounce);
        IF v_candidate = 'started' AND v_state IS DISTINCT FROM 'started' THEN
          INSERT INTO public.masterbus_engine_transitions_v1(
            engine_key, event_time, event_type, state, evidence_time,
            alternator_key, raw_log_file_id, raw_line_number,
            threshold_v, debounce_seconds, source
          ) VALUES (
            e.engine_key, v_transition_time, 'started', 'started', s.time,
            e.alternator_key, s.raw_log_file_id, s.raw_line_number,
            p_threshold_v, v_debounce, s.source
          ) ON CONFLICT DO NOTHING;
          v_state := 'started';
          v_candidate := NULL;
          v_candidate_since := NULL;
        ELSIF v_candidate = 'stopped' AND v_state = 'started' THEN
          INSERT INTO public.masterbus_engine_transitions_v1(
            engine_key, event_time, event_type, state, evidence_time,
            alternator_key, raw_log_file_id, raw_line_number,
            threshold_v, debounce_seconds, source
          ) VALUES (
            e.engine_key, v_transition_time, 'stopped', 'stopped', s.time,
            e.alternator_key, s.raw_log_file_id, s.raw_line_number,
            p_threshold_v, v_debounce, s.source
          ) ON CONFLICT DO NOTHING;
          v_state := 'stopped';
          v_candidate := NULL;
          v_candidate_since := NULL;
        ELSE
          -- Initial below-threshold evidence establishes stopped state but is
          -- not a start/stop transition because no running interval is known.
          v_state := 'stopped';
          v_candidate := NULL;
          v_candidate_since := NULL;
        END IF;
      END IF;
      v_last_time := s.time;
      v_last_raw_file_id := s.raw_log_file_id;
      v_last_raw_line := s.raw_line_number;
      v_last_source := s.source;
    END LOOP;
  END LOOP;

  -- Materialize intervals so consumers do not need to reproduce the state
  -- machine. A data gap deliberately ends runtime; an open interval is not
  -- counted as completed runtime by the summary view.
  INSERT INTO public.masterbus_engine_runtime_intervals_v1(
    engine_key, started_at, ended_at, duration_seconds, end_reason,
    start_evidence_time, end_evidence_time,
    start_raw_log_file_id, start_raw_line_number,
    end_raw_log_file_id, end_raw_line_number, source
  )
  SELECT t.engine_key,
         t.event_time,
         n.event_time,
         CASE WHEN n.event_time IS NULL THEN NULL
              ELSE EXTRACT(EPOCH FROM (n.event_time - t.event_time)) END,
         CASE WHEN n.event_type = 'data_gap' THEN 'data_gap'
              WHEN n.event_type = 'stopped' THEN 'stopped'
              ELSE 'open' END,
         t.evidence_time,
         n.evidence_time,
         t.raw_log_file_id,
         t.raw_line_number,
         n.raw_log_file_id,
         n.raw_line_number,
         t.source
  FROM public.masterbus_engine_transitions_v1 t
  LEFT JOIN LATERAL (
    SELECT n.*
    FROM public.masterbus_engine_transitions_v1 n
    WHERE n.engine_key = t.engine_key
      AND n.event_time > t.event_time
      AND n.event_type IN ('stopped', 'data_gap')
    ORDER BY n.event_time, n.event_type
    LIMIT 1
  ) n ON true
  WHERE t.event_type = 'started'
  ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE VIEW public.v_masterbus_engine_runtime_summary_v1 AS
SELECT engine_key,
       count(*) FILTER (WHERE end_reason <> 'open') AS completed_intervals,
       sum(duration_seconds) FILTER (WHERE end_reason <> 'open') AS completed_runtime_seconds,
       min(started_at) AS first_started_at,
       max(ended_at) FILTER (WHERE end_reason <> 'open') AS last_completed_at,
       count(*) FILTER (WHERE end_reason = 'open') AS open_intervals
FROM public.masterbus_engine_runtime_intervals_v1
GROUP BY engine_key;

CREATE OR REPLACE VIEW public.v_masterbus_recent_electrical_v1 AS
SELECT time, alternator_key AS device_key, 'alternator'::text AS device_class,
       sense_voltage_v AS voltage_v, current_a, field_current_a,
       alternator_temperature_k AS temperature_k, source, raw_log_file_id, raw_line_number
FROM public.masterbus_alternator_samples_v1
WHERE time >= now() - interval '24 hours'
UNION ALL
SELECT time, battery_key, 'battery', voltage_v, current_a, NULL,
       temperature_k, source, raw_log_file_id, raw_line_number
FROM public.masterbus_battery_samples_v1
WHERE time >= now() - interval '24 hours';

DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'grafana_reader') THEN
    GRANT SELECT ON public.masterbus_engine_transitions_v1,
      public.masterbus_engine_runtime_intervals_v1,
      public.v_masterbus_engine_runtime_summary_v1,
      public.v_masterbus_recent_electrical_v1 TO grafana_reader;
  END IF;
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'boat_ingest') THEN
    GRANT SELECT ON public.masterbus_engine_transitions_v1,
      public.masterbus_engine_runtime_intervals_v1,
      public.v_masterbus_engine_runtime_summary_v1,
      public.v_masterbus_recent_electrical_v1 TO boat_ingest;
    GRANT EXECUTE ON FUNCTION public.rebuild_masterbus_engine_history_v1(double precision, double precision, double precision, double precision) TO boat_ingest;
  END IF;
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'jack') THEN
    GRANT SELECT ON public.masterbus_engine_transitions_v1,
      public.masterbus_engine_runtime_intervals_v1,
      public.v_masterbus_engine_runtime_summary_v1,
      public.v_masterbus_recent_electrical_v1 TO jack;
  END IF;
END $$;
