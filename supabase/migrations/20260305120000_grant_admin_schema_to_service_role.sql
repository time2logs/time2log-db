-- admin Schema - service_role permissions
GRANT USAGE ON SCHEMA admin TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA admin TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA admin TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA admin GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA admin GRANT ALL ON FUNCTIONS TO service_role;
