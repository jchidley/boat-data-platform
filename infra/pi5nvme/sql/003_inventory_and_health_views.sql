ALTER TABLE raw_n2k_log_files
  ADD COLUMN IF NOT EXISTS sha256 text,
  ADD COLUMN IF NOT EXISTS first_edge_time timestamptz,
  ADD COLUMN IF NOT EXISTS last_edge_time timestamptz,
  ADD COLUMN IF NOT EXISTS frame_count bigint,
  ADD COLUMN IF NOT EXISTS error_summary text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE TABLE IF NOT EXISTS masterbus_snapshots (
  snapshot_time timestamptz NOT NULL DEFAULT now(),
  path text PRIMARY KEY,
  host text,
  tool_version text,
  summary jsonb,
  error_summary text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS data_quality_observations (
  observed_at timestamptz NOT NULL DEFAULT now(),
  severity text NOT NULL,
  category text NOT NULL,
  affected text,
  message text NOT NULL,
  evidence jsonb
);

CREATE TABLE IF NOT EXISTS boat_data_summaries (
  scope text NOT NULL,
  start_time timestamptz,
  end_time timestamptz,
  summary_md text NOT NULL,
  generated_at timestamptz NOT NULL DEFAULT now(),
  provenance jsonb
);

CREATE OR REPLACE VIEW v_signalk_path_catalog AS
SELECT
  path,
  count(*) AS samples,
  min(time) AS first_seen,
  max(time) AS last_seen,
  count(DISTINCT source) AS source_count,
  max(source) FILTER (WHERE source IS NOT NULL) AS example_source,
  max(pgn) FILTER (WHERE pgn IS NOT NULL) AS example_pgn
FROM signal_k_measurements
GROUP BY path;

CREATE OR REPLACE VIEW v_pgn_catalog_seen AS
SELECT
  pgn,
  max(description) AS description,
  count(*) AS frames,
  min(time) AS first_seen,
  max(time) AS last_seen,
  count(DISTINCT src) AS source_count,
  array_agg(DISTINCT src ORDER BY src) FILTER (WHERE src IS NOT NULL) AS sources
FROM n2k_decoded_messages
GROUP BY pgn;

CREATE OR REPLACE VIEW v_known_devices AS
SELECT
  src AS source_address,
  count(*) AS frames,
  min(time) AS first_seen,
  max(time) AS last_seen,
  array_agg(DISTINCT pgn ORDER BY pgn) AS pgns,
  array_agg(DISTINCT description ORDER BY description) FILTER (WHERE description IS NOT NULL) AS descriptions
FROM n2k_decoded_messages
WHERE src IS NOT NULL
GROUP BY src;

CREATE OR REPLACE VIEW v_unknown_or_proprietary_pgns AS
SELECT *
FROM v_pgn_catalog_seen
WHERE description IS NULL
   OR description ILIKE '%unknown%'
   OR description ILIKE '%proprietary%'
   OR pgn BETWEEN 61184 AND 65535
   OR pgn BETWEEN 126720 AND 126975
   OR pgn BETWEEN 130816 AND 131071;

CREATE OR REPLACE VIEW v_latest_boat_state AS
SELECT DISTINCT ON (path)
  path,
  time,
  source,
  pgn,
  value_double,
  value_text,
  value_json
FROM signal_k_measurements
ORDER BY path, time DESC;

CREATE OR REPLACE VIEW v_recent_data_quality AS
SELECT *
FROM data_quality_observations
WHERE observed_at > now() - interval '7 days'
ORDER BY observed_at DESC;

GRANT SELECT, INSERT, UPDATE ON masterbus_snapshots, data_quality_observations, boat_data_summaries TO boat_ingest;
GRANT SELECT ON masterbus_snapshots, data_quality_observations, boat_data_summaries TO grafana_reader;
GRANT SELECT ON v_signalk_path_catalog, v_pgn_catalog_seen, v_known_devices, v_unknown_or_proprietary_pgns, v_latest_boat_state, v_recent_data_quality TO grafana_reader;
GRANT SELECT ON v_signalk_path_catalog, v_pgn_catalog_seen, v_known_devices, v_unknown_or_proprietary_pgns, v_latest_boat_state, v_recent_data_quality TO boat_ingest;

DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'jack') THEN
    GRANT SELECT, INSERT, UPDATE ON masterbus_snapshots, data_quality_observations, boat_data_summaries TO jack;
    GRANT SELECT ON v_signalk_path_catalog, v_pgn_catalog_seen, v_known_devices, v_unknown_or_proprietary_pgns, v_latest_boat_state, v_recent_data_quality TO jack;
  END IF;
END $$;
