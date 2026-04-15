-- 1. Schema dem PostgREST exponieren
-- In Supabase Dashboard: Settings > API > Exposed schemas -> "admin" hinzufügen
-- Note: This config is typically set via Supabase Dashboard UI or project settings
-- ALTER SYSTEM requires superuser privileges not available in managed environment
-- If admin schema needs to be exposed, configure it manually in:
-- https://app.supabase.com/project/YOUR_PROJECT/settings/api

-- 2. USAGE auf dem Schema gewähren
GRANT USAGE ON SCHEMA admin TO service_role;

-- 3. SELECT-Berechtigung auf die benötigten Tabellen gewähren
GRANT SELECT ON admin.organizations TO service_role;
GRANT SELECT ON admin.organization_members TO service_role;
