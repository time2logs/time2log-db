-- service role permission für app
GRANT USAGE ON SCHEMA app TO service_role;
GRANT SELECT ON app.activity_records TO service_role;
GRANT SELECT ON app.profiles TO service_role;