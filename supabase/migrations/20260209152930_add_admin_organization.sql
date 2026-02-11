CREATE SCHEMA admin;

CREATE TABLE admin.organizations (
    id uuid NOT NULL PRIMARY KEY,
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON admin.organizations
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE admin.organization_members (
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    organization_id uuid NOT NULL REFERENCES admin.organizations(id) ON DELETE CASCADE,
    user_role app.user_role NOT NULL DEFAULT 'user',
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, organization_id)
);

CREATE INDEX idx_org_members_user_role ON admin.organization_members (user_id, user_role);

CREATE TRIGGER set_updated_at_org_members
    BEFORE UPDATE ON admin.organization_members
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE OR REPLACE FUNCTION admin.is_admin()
RETURNS boolean AS $$
    SELECT EXISTS (
        SELECT 1 FROM admin.organization_members
        WHERE user_id = auth.uid()
          AND user_role = 'admin'
    );
$$ LANGUAGE sql SECURITY DEFINER STABLE
   SET search_path = '';

CREATE OR REPLACE FUNCTION admin.is_admin_of(org_id uuid)
RETURNS boolean AS $$
    SELECT EXISTS (
        SELECT 1 FROM admin.organization_members
        WHERE user_id = auth.uid()
          AND organization_id = org_id
          AND user_role = 'admin'
    );
$$ LANGUAGE sql SECURITY DEFINER STABLE
   SET search_path = '';

CREATE OR REPLACE FUNCTION admin.is_member_of(org_id uuid)
RETURNS boolean AS $$
    SELECT EXISTS (
        SELECT 1 FROM admin.organization_members
        WHERE user_id = auth.uid()
          AND organization_id = org_id
    );
$$ LANGUAGE sql SECURITY DEFINER STABLE
   SET search_path = '';

CREATE OR REPLACE FUNCTION admin.auto_add_creator_as_member()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO admin.organization_members (user_id, organization_id, user_role)
    VALUES (auth.uid(), NEW.id, 'admin');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = '';

CREATE TRIGGER trg_auto_add_creator
    AFTER INSERT ON admin.organizations
    FOR EACH ROW
    EXECUTE FUNCTION admin.auto_add_creator_as_member();

-- RLS: admin.organizations
-- ===========================================================================
ALTER TABLE admin.organizations ENABLE ROW LEVEL SECURITY;

-- Alle Mitglieder dürfen ihre Orgs sehen
CREATE POLICY "orgs_select_member"
    ON admin.organizations FOR SELECT
    USING (admin.is_member_of(id));

-- Admins dürfen neue Organizations erstellen
CREATE POLICY "orgs_insert_admin"
    ON admin.organizations FOR INSERT
    WITH CHECK (admin.is_admin());

-- Nur Org-Admins dürfen ihre Org bearbeiten
CREATE POLICY "orgs_update_admin"
    ON admin.organizations FOR UPDATE
    USING (admin.is_admin_of(id))
    WITH CHECK (admin.is_admin_of(id));

-- RLS: admin.organization_members
-- ============================================================================
ALTER TABLE admin.organization_members ENABLE ROW LEVEL SECURITY;

-- Mitglieder sehen andere Mitglieder ihrer Org
CREATE POLICY "org_members_select_member"
    ON admin.organization_members FOR SELECT
    USING (admin.is_member_of(organization_id));

-- Nur Org-Admins können Mitglieder hinzufügen
CREATE POLICY "org_members_insert_admin"
    ON admin.organization_members FOR INSERT
    WITH CHECK (admin.is_admin_of(organization_id));

-- Nur Org-Admins können Mitglieder entfernen
CREATE POLICY "org_members_delete_admin"
    ON admin.organization_members FOR DELETE
    USING (admin.is_admin_of(organization_id));
