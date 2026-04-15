-- 1. Schema dem PostgREST exponieren
-- In Supabase Dashboard: Settings > API > Exposed schemas -> "admin" hinzufügen
-- Using ALTER SYSTEM instead of ALTER ROLE (authenticator is reserved)
ALTER SYSTEM SET pgrst.db_schemas = 'public, app, admin';
SELECT pg_reload_conf();

-- 2. USAGE auf dem Schema gewähren
GRANT USAGE ON SCHEMA admin TO service_role;

-- 3. SELECT-Berechtigung auf die benötigten Tabellen gewähren
GRANT SELECT ON admin.organizations TO service_role;
GRANT SELECT ON admin.organization_members TO service_role;
