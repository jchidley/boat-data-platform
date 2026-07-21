CREATE TABLE IF NOT EXISTS public.health_observations (
  observed_at timestamptz NOT NULL DEFAULT now(),
  run_id text NOT NULL,
  check_group text,
  check_name text NOT NULL,
  status text NOT NULL CHECK (status IN ('pass', 'warn', 'fail')),
  message text NOT NULL,
  value_double double precision,
  value_text text,
  evidence jsonb
);

SELECT create_hypertable('public.health_observations', 'observed_at', if_not_exists => TRUE);

CREATE INDEX IF NOT EXISTS health_observations_check_time_idx
  ON public.health_observations (check_name, observed_at DESC);
CREATE INDEX IF NOT EXISTS health_observations_status_time_idx
  ON public.health_observations (status, observed_at DESC);
CREATE INDEX IF NOT EXISTS health_observations_run_idx
  ON public.health_observations (run_id);

CREATE OR REPLACE VIEW public.v_latest_health_observations AS
SELECT DISTINCT ON (check_name)
  observed_at,
  run_id,
  check_group,
  check_name,
  status,
  message,
  value_double,
  value_text,
  evidence
FROM public.health_observations
ORDER BY check_name, observed_at DESC;

CREATE OR REPLACE VIEW public.v_recent_health_summary AS
SELECT
  date_trunc('minute', observed_at) AS minute,
  count(*) FILTER (WHERE status = 'pass') AS pass_count,
  count(*) FILTER (WHERE status = 'warn') AS warn_count,
  count(*) FILTER (WHERE status = 'fail') AS fail_count,
  count(*) AS total_count
FROM public.health_observations
WHERE observed_at > now() - interval '24 hours'
GROUP BY date_trunc('minute', observed_at)
ORDER BY minute DESC;

GRANT SELECT, INSERT ON public.health_observations TO boat_ingest;
GRANT SELECT ON public.health_observations, public.v_latest_health_observations, public.v_recent_health_summary TO grafana_reader;
GRANT SELECT ON public.health_observations, public.v_latest_health_observations, public.v_recent_health_summary TO boat_ingest;

DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'jack') THEN
    GRANT SELECT, INSERT ON public.health_observations TO jack;
    GRANT SELECT ON public.v_latest_health_observations, public.v_recent_health_summary TO jack;
  END IF;
END $$;
