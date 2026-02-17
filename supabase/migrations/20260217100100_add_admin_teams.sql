CREATE TABLE admin.teams (
    id uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES admin.organizations(id) ON DELETE CASCADE,
    profession_id uuid NOT NULL REFERENCES admin.professions(id) ON DELETE CASCADE,
    name text NOT NULL,
    created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    UNIQUE (organization_id, profession_id, name)
);

CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON admin.teams
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE admin.team_members (
    team_id uuid NOT NULL REFERENCES admin.teams(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    team_role app.user_role NOT NULL DEFAULT 'user',
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    PRIMARY KEY (team_id, user_id)
);

CREATE INDEX idx_team_members_user ON admin.team_members (user_id);

-- RLS: admin.teams
-- ===========================================================================
ALTER TABLE admin.teams ENABLE ROW LEVEL SECURITY;

-- Alle Org-Mitglieder dürfen Teams sehen
CREATE POLICY "teams_select_member"
    ON admin.teams FOR SELECT
    USING (admin.is_member_of(organization_id));

-- Nur Org-Admins dürfen Teams erstellen
CREATE POLICY "teams_insert_admin"
    ON admin.teams FOR INSERT
    WITH CHECK (admin.is_admin_of(organization_id));

-- Nur Org-Admins dürfen Teams bearbeiten
CREATE POLICY "teams_update_admin"
    ON admin.teams FOR UPDATE
    USING (admin.is_admin_of(organization_id))
    WITH CHECK (admin.is_admin_of(organization_id));

-- Nur Org-Admins dürfen Teams löschen
CREATE POLICY "teams_delete_admin"
    ON admin.teams FOR DELETE
    USING (admin.is_admin_of(organization_id));

-- RLS: admin.team_members
-- ===========================================================================
ALTER TABLE admin.team_members ENABLE ROW LEVEL SECURITY;

-- Org-Mitglieder sehen Team-Mitglieder ihrer Org
CREATE POLICY "team_members_select_member"
    ON admin.team_members FOR SELECT
    USING (
        admin.is_member_of((SELECT organization_id FROM admin.teams WHERE id = team_id))
    );

-- Nur Org-Admins können Team-Mitglieder hinzufügen
CREATE POLICY "team_members_insert_admin"
    ON admin.team_members FOR INSERT
    WITH CHECK (
        admin.is_admin_of((SELECT organization_id FROM admin.teams WHERE id = team_id))
    );

-- Nur Org-Admins können Team-Mitglieder entfernen
CREATE POLICY "team_members_delete_admin"
    ON admin.team_members FOR DELETE
    USING (
        admin.is_admin_of((SELECT organization_id FROM admin.teams WHERE id = team_id))
    );
