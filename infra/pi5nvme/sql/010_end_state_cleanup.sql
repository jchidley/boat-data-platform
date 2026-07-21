-- Remove deployed database objects that are not part of the two-path end state.
-- All objects below are derived; authoritative N2K and MasterBus source files
-- must be verified before this migration is applied.

DROP VIEW IF EXISTS public.v_signalk_path_catalog CASCADE;
DROP VIEW IF EXISTS public.v_latest_boat_state CASCADE;
DROP VIEW IF EXISTS public.v_recent_data_quality CASCADE;

DROP TABLE IF EXISTS public.signal_k_measurements CASCADE;
DROP TABLE IF EXISTS public.raw_n2k_log_files CASCADE;
DROP TABLE IF EXISTS public.masterbus_snapshots CASCADE;
DROP TABLE IF EXISTS public.data_quality_observations CASCADE;
DROP TABLE IF EXISTS public.boat_data_summaries CASCADE;
DROP TABLE IF EXISTS public.n2k_device_pgn_summary_v2 CASCADE;
