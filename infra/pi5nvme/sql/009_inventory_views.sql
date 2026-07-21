-- Inventory views use compact per-file summaries. Complete decoded frame
-- envelopes remain in authoritative candump files, not PostgreSQL.

CREATE OR REPLACE VIEW v_pgn_catalog_seen AS
SELECT
  s.pgn,
  max(d.description) AS description,
  sum(s.frame_count) AS frames,
  min(s.first_time) AS first_seen,
  max(s.last_time) AS last_seen,
  count(DISTINCT s.source_address) FILTER (WHERE s.source_address IS NOT NULL) AS source_count,
  array_agg(DISTINCT s.source_address ORDER BY s.source_address)
    FILTER (WHERE s.source_address IS NOT NULL) AS sources
FROM n2k_file_pgn_summary_v2 s
LEFT JOIN n2k_pgn_definitions_v2 d USING (pgn)
GROUP BY s.pgn;

CREATE OR REPLACE VIEW v_known_devices AS
SELECT
  s.source_address,
  sum(s.frame_count) AS frames,
  min(s.first_time) AS first_seen,
  max(s.last_time) AS last_seen,
  array_agg(DISTINCT p.pgn ORDER BY p.pgn) AS pgns
FROM n2k_file_source_summary_v2 s
CROSS JOIN LATERAL unnest(s.pgns) AS p(pgn)
GROUP BY s.source_address;

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
