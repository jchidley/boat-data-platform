CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE IF NOT EXISTS signal_k_measurements (
  time timestamptz NOT NULL,
  path text NOT NULL,
  source text,
  pgn integer,
  value_double double precision,
  value_text text,
  value_json jsonb
);

SELECT create_hypertable('signal_k_measurements', 'time', if_not_exists => TRUE);

CREATE INDEX IF NOT EXISTS signal_k_measurements_path_time_idx
  ON signal_k_measurements (path, time DESC);
CREATE INDEX IF NOT EXISTS signal_k_measurements_source_time_idx
  ON signal_k_measurements (source, time DESC);
CREATE INDEX IF NOT EXISTS signal_k_measurements_pgn_time_idx
  ON signal_k_measurements (pgn, time DESC);

CREATE TABLE IF NOT EXISTS raw_n2k_log_files (
  path text PRIMARY KEY,
  size_bytes bigint NOT NULL,
  mtime timestamptz NOT NULL,
  mirrored_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz
);

GRANT USAGE ON SCHEMA public TO boat_ingest, grafana_reader;
GRANT SELECT, INSERT, UPDATE ON signal_k_measurements TO boat_ingest;
GRANT SELECT, INSERT, UPDATE ON raw_n2k_log_files TO boat_ingest;
GRANT SELECT ON signal_k_measurements TO grafana_reader;
GRANT SELECT ON raw_n2k_log_files TO grafana_reader;
