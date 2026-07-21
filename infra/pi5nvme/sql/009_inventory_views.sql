-- Create inventory views against the typed N2K model after 005_* creates the
-- frame and definition tables.

CREATE OR REPLACE VIEW v_pgn_catalog_seen AS
SELECT
  f.pgn,
  max(d.description) AS description,
  count(*) AS frames,
  min(f.time) AS first_seen,
  max(f.time) AS last_seen,
  count(DISTINCT f.source_address) AS source_count,
  array_agg(DISTINCT f.source_address ORDER BY f.source_address)
    FILTER (WHERE f.source_address IS NOT NULL) AS sources
FROM n2k_frames_v2 f
LEFT JOIN n2k_pgn_definitions_v2 d USING (pgn)
GROUP BY f.pgn;

CREATE OR REPLACE VIEW v_known_devices AS
SELECT
  source_address,
  count(*) AS frames,
  min(time) AS first_seen,
  max(time) AS last_seen,
  array_agg(DISTINCT pgn ORDER BY pgn) AS pgns
FROM n2k_frames_v2
WHERE source_address IS NOT NULL
GROUP BY source_address;

CREATE OR REPLACE VIEW v_unknown_or_proprietary_pgns AS
SELECT *
FROM v_pgn_catalog_seen
WHERE description IS NULL
   OR description ILIKE '%unknown%'
   OR description ILIKE '%proprietary%'
   OR pgn BETWEEN 61184 AND 65535
   OR pgn BETWEEN 126720 AND 126975
   OR pgn BETWEEN 130816 AND 131071;

GRANT SELECT ON v_pgn_catalog_seen, v_known_devices,
  v_unknown_or_proprietary_pgns
  TO grafana_reader, boat_ingest;

DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'jack') THEN
    GRANT SELECT ON v_pgn_catalog_seen, v_known_devices,
      v_unknown_or_proprietary_pgns TO jack;
  END IF;
END $$;
