CREATE SCHEMA admin;

CREATE TABLE admin.organizations (
    id uuid NOT NULL PRIMARY KEY,
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- update updated_at column on update
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON admin.organizations
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE admin.organization_members (
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    organization_id uuid NOT NULL REFERENCES admin.organizations(id) ON DELETE CASCADE,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, organization_id)
);

CREATE TRIGGER set_updated_at_org_members
    BEFORE UPDATE ON admin.organization_members
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- Index für performante Admin-Prüfung
CREATE INDEX idx_user_roles_user_role ON app.user_roles (user_id, role);

-- Hilfsfunktion: Ist der aktuelle User Admin?
CREATE OR REPLACE FUNCTION admin.is_admin()
RETURNS boolean AS $$
    SELECT EXISTS (
        SELECT 1 FROM app.user_roles
        WHERE user_id = auth.uid()
          AND role = 'admin'
    );
$$ LANGUAGE sql SECURITY DEFINER STABLE
   SET search_path = '';

-- Hilfsfunktion: Ist der aktuelle User Mitglied einer Organisation?
CREATE OR REPLACE FUNCTION admin.is_member_of(org_id uuid)
RETURNS boolean AS $$
    SELECT EXISTS (
        SELECT 1 FROM admin.organization_members
        WHERE user_id = auth.uid()
          AND organization_id = org_id
    );
$$ LANGUAGE sql SECURITY DEFINER STABLE
   SET search_path = '';

-- Trigger: Creator wird automatisch erstes Mitglied der neuen Organisation
CREATE OR REPLACE FUNCTION admin.auto_add_creator_as_member()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO admin.organization_members (user_id, organization_id)
    VALUES (auth.uid(), NEW.id);
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

-- Admins dürfen Organizations sehen, in denen sie Mitglied sind
CREATE POLICY "orgs_select_member_admin"
    ON admin.organizations FOR SELECT
    USING (admin.is_admin() AND admin.is_member_of(id));

-- Admins dürfen neue Organizations erstellen
CREATE POLICY "orgs_insert_admin"
    ON admin.organizations FOR INSERT
    WITH CHECK (admin.is_admin());

-- Admins dürfen Organizations bearbeiten, in denen sie Mitglied sind
CREATE POLICY "orgs_update_member_admin"
    ON admin.organizations FOR UPDATE
    USING (admin.is_admin() AND admin.is_member_of(id))
    WITH CHECK (admin.is_admin() AND admin.is_member_of(id));

-- RLS: admin.organization_members
-- ============================================================================
ALTER TABLE admin.organization_members ENABLE ROW LEVEL SECURITY;

-- Admins sehen Mitglieder ihrer eigenen Organisationen
CREATE POLICY "org_members_select_admin"
    ON admin.organization_members FOR SELECT
    USING (admin.is_admin() AND admin.is_member_of(organization_id));

-- Admins können Mitglieder zu ihren Organisationen hinzufügen
CREATE POLICY "org_members_insert_admin"
    ON admin.organization_members FOR INSERT
    WITH CHECK (admin.is_admin() AND admin.is_member_of(organization_id));

-- Admins können Mitglieder aus ihren Organisationen entfernen
CREATE POLICY "org_members_delete_admin"
    ON admin.organization_members FOR DELETE
    USING (admin.is_admin() AND admin.is_member_of(organization_id));
