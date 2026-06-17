-- Fix Supabase security advisor warnings without changing app/admin API contracts.
--
-- This migration keeps the public RPC names that the user UI/admin backend call,
-- but moves privileged SECURITY DEFINER implementations behind SECURITY INVOKER
-- wrappers where authenticated users still need to call them.

-- -----------------------------------------------------------------------------
-- Internal implementation schema (not exposed by supabase/config.toml API schemas)
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS internal;
REVOKE ALL ON SCHEMA internal FROM PUBLIC;
GRANT USAGE ON SCHEMA internal TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Function search_path hardening
-- -----------------------------------------------------------------------------
ALTER FUNCTION public.update_updated_at_column() SET search_path = '';
ALTER FUNCTION app.sync_activity_semester() SET search_path = '';
ALTER FUNCTION app.phone_verification_send_allowed() SET search_path = '';
ALTER FUNCTION app.log_phone_verification_event(text, text, text, text) SET search_path = '';
ALTER FUNCTION app.set_onboarding_completed_at() SET search_path = '';

-- -----------------------------------------------------------------------------
-- RLS helper functions
-- Keep admin.is_* names for existing RLS policies, but make exposed functions
-- SECURITY INVOKER wrappers around non-exposed SECURITY DEFINER implementations.
-- -----------------------------------------------------------------------------
ALTER FUNCTION admin.is_admin() SET SCHEMA internal;
ALTER FUNCTION admin.is_admin_of(uuid) SET SCHEMA internal;
ALTER FUNCTION admin.is_member_of(uuid) SET SCHEMA internal;

REVOKE EXECUTE ON FUNCTION internal.is_admin() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION internal.is_admin_of(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION internal.is_member_of(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION internal.is_admin() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION internal.is_admin_of(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION internal.is_member_of(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION admin.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path = ''
AS $$
    SELECT internal.is_admin();
$$;

CREATE OR REPLACE FUNCTION admin.is_admin_of(org_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path = ''
AS $$
    SELECT internal.is_admin_of(org_id);
$$;

CREATE OR REPLACE FUNCTION admin.is_member_of(org_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path = ''
AS $$
    SELECT internal.is_member_of(org_id);
$$;

REVOKE EXECUTE ON FUNCTION admin.is_admin() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION admin.is_admin_of(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION admin.is_member_of(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin.is_admin() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION admin.is_admin_of(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION admin.is_member_of(uuid) TO authenticated, service_role;

-- Optional role helpers exist on newer remote databases.
DO $$
BEGIN
    IF to_regprocedure('admin.is_moderator()') IS NOT NULL THEN
        ALTER FUNCTION admin.is_moderator() SET SCHEMA internal;
        REVOKE EXECUTE ON FUNCTION internal.is_moderator() FROM PUBLIC, anon;
        GRANT EXECUTE ON FUNCTION internal.is_moderator() TO authenticated, service_role;

        EXECUTE $sql$
            CREATE OR REPLACE FUNCTION admin.is_moderator()
            RETURNS boolean
            LANGUAGE sql
            SECURITY INVOKER
            STABLE
            SET search_path = ''
            AS $fn$
                SELECT internal.is_moderator();
            $fn$;
        $sql$;

        REVOKE EXECUTE ON FUNCTION admin.is_moderator() FROM PUBLIC, anon;
        GRANT EXECUTE ON FUNCTION admin.is_moderator() TO authenticated, service_role;
    END IF;

    IF to_regprocedure('admin.is_system_admin()') IS NOT NULL THEN
        ALTER FUNCTION admin.is_system_admin() SET SCHEMA internal;
        REVOKE EXECUTE ON FUNCTION internal.is_system_admin() FROM PUBLIC, anon;
        GRANT EXECUTE ON FUNCTION internal.is_system_admin() TO authenticated, service_role;

        EXECUTE $sql$
            CREATE OR REPLACE FUNCTION admin.is_system_admin()
            RETURNS boolean
            LANGUAGE sql
            SECURITY INVOKER
            STABLE
            SET search_path = ''
            AS $fn$
                SELECT internal.is_system_admin();
            $fn$;
        $sql$;

        REVOKE EXECUTE ON FUNCTION admin.is_system_admin() FROM PUBLIC, anon;
        GRANT EXECUTE ON FUNCTION admin.is_system_admin() TO authenticated, service_role;
    END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- RPCs intentionally callable by authenticated users
-- Preserve the exposed RPC names but move privileged bodies to internal schema.
-- -----------------------------------------------------------------------------
ALTER FUNCTION app.accept_invite(uuid) RENAME TO accept_invite_impl;
ALTER FUNCTION app.accept_invite_impl(uuid) SET SCHEMA internal;
ALTER FUNCTION internal.accept_invite_impl(uuid) SET search_path = '';
REVOKE EXECUTE ON FUNCTION internal.accept_invite_impl(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION internal.accept_invite_impl(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION app.accept_invite(invite_token uuid)
RETURNS void
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
    SELECT internal.accept_invite_impl(invite_token);
$$;

REVOKE EXECUTE ON FUNCTION app.accept_invite(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION app.accept_invite(uuid) TO authenticated, service_role;

ALTER FUNCTION admin.apply_curriculum_import(uuid) RENAME TO apply_curriculum_import_impl;
ALTER FUNCTION admin.apply_curriculum_import_impl(uuid) SET SCHEMA internal;
ALTER FUNCTION internal.apply_curriculum_import_impl(uuid) SET search_path = '';
REVOKE EXECUTE ON FUNCTION internal.apply_curriculum_import_impl(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION internal.apply_curriculum_import_impl(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION admin.apply_curriculum_import(import_id uuid)
RETURNS void
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
    SELECT internal.apply_curriculum_import_impl(import_id);
$$;

REVOKE EXECUTE ON FUNCTION admin.apply_curriculum_import(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin.apply_curriculum_import(uuid) TO authenticated, service_role;

-- Optional admin org-invite RPC exists on newer remote databases and is used by
-- the admin backend with the signed-in user's JWT.
DO $$
BEGIN
    IF to_regprocedure('admin.accept_org_invite_for_existing_user(uuid)') IS NOT NULL THEN
        ALTER FUNCTION admin.accept_org_invite_for_existing_user(uuid)
            RENAME TO accept_org_invite_for_existing_user_impl;
        ALTER FUNCTION admin.accept_org_invite_for_existing_user_impl(uuid)
            SET SCHEMA internal;
        ALTER FUNCTION internal.accept_org_invite_for_existing_user_impl(uuid)
            SET search_path = '';
        REVOKE EXECUTE ON FUNCTION internal.accept_org_invite_for_existing_user_impl(uuid)
            FROM PUBLIC, anon;
        GRANT EXECUTE ON FUNCTION internal.accept_org_invite_for_existing_user_impl(uuid)
            TO authenticated, service_role;

        EXECUTE $sql$
            CREATE OR REPLACE FUNCTION admin.accept_org_invite_for_existing_user(invite_token uuid)
            RETURNS void
            LANGUAGE sql
            SECURITY INVOKER
            SET search_path = ''
            AS $fn$
                SELECT internal.accept_org_invite_for_existing_user_impl(invite_token);
            $fn$;
        $sql$;

        REVOKE EXECUTE ON FUNCTION admin.accept_org_invite_for_existing_user(uuid) FROM PUBLIC, anon;
        GRANT EXECUTE ON FUNCTION admin.accept_org_invite_for_existing_user(uuid) TO authenticated, service_role;
    END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- SECURITY DEFINER functions that should not be directly callable via RPC
-- -----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION admin._upsert_curriculum_nodes(uuid, uuid, uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION admin.auto_add_creator_as_member() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION app.handle_new_user() FROM PUBLIC, anon, authenticated;

-- Server-side/service-role only RPCs. The user UI and admin backend call these
-- through service-role clients, not directly from anonymous/authenticated clients.
REVOKE EXECUTE ON FUNCTION admin.get_invite_details(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION admin.get_invite_details(uuid) TO service_role;

REVOKE EXECUTE ON FUNCTION admin.accept_invite(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION admin.accept_invite(uuid) TO service_role;

REVOKE EXECUTE ON FUNCTION admin.accept_invite_for(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION admin.accept_invite_for(uuid, uuid, text, text) TO service_role;

-- -----------------------------------------------------------------------------
-- admin.reminder RLS tightening
-- Authenticated users can manage reminders only for organizations where they are
-- admins according to the existing admin.is_admin_of helper.
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON admin.reminder;
DROP POLICY IF EXISTS "Enable read access for all users" ON admin.reminder;
DROP POLICY IF EXISTS "Policy with table joins" ON admin.reminder;
DROP POLICY IF EXISTS "reminder_select_admin" ON admin.reminder;
DROP POLICY IF EXISTS "reminder_insert_admin" ON admin.reminder;
DROP POLICY IF EXISTS "reminder_update_admin" ON admin.reminder;

CREATE POLICY "reminder_select_admin"
    ON admin.reminder FOR SELECT
    TO authenticated
    USING (admin.is_admin_of(organization_id));

CREATE POLICY "reminder_insert_admin"
    ON admin.reminder FOR INSERT
    TO authenticated
    WITH CHECK (admin.is_admin_of(organization_id));

CREATE POLICY "reminder_update_admin"
    ON admin.reminder FOR UPDATE
    TO authenticated
    USING (admin.is_admin_of(organization_id))
    WITH CHECK (admin.is_admin_of(organization_id));

-- -----------------------------------------------------------------------------
-- Public avatar bucket listing
-- Public object URLs continue to work for the public bucket, but clients can no
-- longer list every object in the avatars bucket through storage.objects SELECT.
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Avatar images are publicly accessible" ON storage.objects;
