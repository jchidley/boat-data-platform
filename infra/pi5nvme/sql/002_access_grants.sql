DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'jack') THEN
    CREATE ROLE jack LOGIN;
  END IF;
END $$;

GRANT CONNECT ON DATABASE boatdata TO jack;
GRANT USAGE ON SCHEMA public TO jack;
