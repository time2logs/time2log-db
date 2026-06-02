-- Platform-Invites: System-Admin laedt neue Admins ohne Organisation ein.
-- admin.invites.organization_id wird nullable; ein CHECK erzwingt, dass
-- Platform-Invites (org_id IS NULL) nur die Rolle 'admin' haben duerfen.

-- 1. is_system_admin() Helper
-- ============================================================
CREATE OR REPLACE FUNCTION admin.is_system_admin()
RETURNS boolean AS $$
SELECT EXISTS (
    SELECT 1 FROM admin.organization_members
    WHERE user_id = auth.uid()
      AND user_role = 'system_admin'
);
$$ LANGUAGE sql SECURITY DEFINER STABLE
   SET search_path = '';

-- 2. organization_id nullable + CHECK
-- ============================================================
ALTER TABLE admin.invites
    ALTER COLUMN organization_id DROP NOT NULL;

ALTER TABLE admin.invites
    ADD CONSTRAINT invites_platform_requires_admin_role
    CHECK (organization_id IS NOT NULL OR user_role = 'admin');

-- 3. RLS-Policies fuer Platform-Invites
-- ============================================================
-- System-Admin darf Platform-Invites (org_id IS NULL) sehen
CREATE POLICY "invites_select_system_admin_platform"
    ON admin.invites FOR SELECT
    USING (organization_id IS NULL AND admin.is_system_admin());

-- System-Admin darf Platform-Invites anlegen
CREATE POLICY "invites_insert_system_admin_platform"
    ON admin.invites FOR INSERT
    WITH CHECK (organization_id IS NULL AND admin.is_system_admin());

-- System-Admin darf Platform-Invites loeschen/widerrufen
CREATE POLICY "invites_delete_system_admin_platform"
    ON admin.invites FOR DELETE
    USING (organization_id IS NULL AND admin.is_system_admin());
