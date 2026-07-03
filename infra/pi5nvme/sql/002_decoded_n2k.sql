CREATE TABLE IF NOT EXISTS n2k_decoded_messages (
  log_path text NOT NULL,
  message_index integer NOT NULL,
  time timestamptz,
  pgn integer NOT NULL,
  prio integer,
  src integer,
  dst integer,
  description text,
  decoder_id text,
  fields jsonb,
  raw jsonb,
  signalk_exposed boolean DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (log_path, message_index)
);

CREATE INDEX IF NOT EXISTS n2k_decoded_messages_time_idx ON n2k_decoded_messages (time DESC);
CREATE INDEX IF NOT EXISTS n2k_decoded_messages_pgn_time_idx ON n2k_decoded_messages (pgn, time DESC);
CREATE INDEX IF NOT EXISTS n2k_decoded_messages_src_time_idx ON n2k_decoded_messages (src, time DESC);
CREATE INDEX IF NOT EXISTS n2k_decoded_messages_description_idx ON n2k_decoded_messages (description);
CREATE INDEX IF NOT EXISTS n2k_decoded_messages_fields_gin_idx ON n2k_decoded_messages USING gin (fields);

GRANT SELECT, INSERT, UPDATE ON n2k_decoded_messages TO boat_ingest;
GRANT SELECT ON n2k_decoded_messages TO grafana_reader;

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'jack') THEN
    CREATE ROLE jack LOGIN;
  END IF;
END $$;

GRANT CONNECT ON DATABASE boatdata TO jack;
GRANT USAGE ON SCHEMA public TO jack;
GRANT SELECT, INSERT, UPDATE ON signal_k_measurements, raw_n2k_log_files, n2k_decoded_messages TO jack;
