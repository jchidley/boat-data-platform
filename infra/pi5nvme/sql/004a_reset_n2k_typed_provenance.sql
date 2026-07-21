-- One-time reset from frame-linked experimental tables to direct typed
-- provenance. No historical backfill was loaded before this migration.
-- Raw candump files remain authoritative and are not touched.

DROP VIEW IF EXISTS public.v_unknown_or_proprietary_pgns CASCADE;
DROP VIEW IF EXISTS public.v_known_devices CASCADE;
DROP VIEW IF EXISTS public.v_pgn_catalog_seen CASCADE;

DROP TABLE IF EXISTS public.n2k_position_rapid_129025_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_cog_sog_129026_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_gnss_position_129029_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_heading_127250_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_rudder_127245_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_heading_track_control_127237_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_rate_of_turn_127251_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_switch_bank_status_127501_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_attitude_127257_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_magnetic_variation_127258_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_water_speed_128259_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_water_depth_128267_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_distance_log_128275_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_navigation_data_129284_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_route_waypoint_129285_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_ais_class_a_position_129038_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_ais_class_b_position_129039_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_ais_class_a_static_129794_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_ais_class_b_static_a_129809_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_ais_class_b_static_b_129810_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_gnss_dops_129539_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_gnss_satellites_129540_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_wind_130306_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_environment_130310_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_environment_130311_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_temperature_130312_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_pressure_130314_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_temperature_ext_130316_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_research_fields_v2 CASCADE;
DROP TABLE IF EXISTS public.n2k_frames_v2 CASCADE;
ALTER TABLE IF EXISTS public.n2k_source_observations_v2 DROP COLUMN IF EXISTS frame_id;
