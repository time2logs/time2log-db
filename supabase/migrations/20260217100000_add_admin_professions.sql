CREATE TABLE admin.professions (
    id uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES admin.organizations(id) ON DELETE CASCADE,
    key text NOT NULL,
    label text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    UNIQUE (organization_id, key)
);

CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON admin.professions
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- RLS: admin.professions
-- ===========================================================================
ALTER TABLE admin.professions ENABLE ROW LEVEL SECURITY;

-- Alle Org-Mitglieder dürfen Berufe sehen
CREATE POLICY "professions_select_member"
    ON admin.professions FOR SELECT
    USING (admin.is_member_of(organization_id));

-- Nur Org-Admins dürfen Berufe erstellen
CREATE POLICY "professions_insert_admin"
    ON admin.professions FOR INSERT
    WITH CHECK (admin.is_admin_of(organization_id));

-- Nur Org-Admins dürfen Berufe bearbeiten
CREATE POLICY "professions_update_admin"
    ON admin.professions FOR UPDATE
    USING (admin.is_admin_of(organization_id))
    WITH CHECK (admin.is_admin_of(organization_id));

-- Nur Org-Admins dürfen Berufe löschen
CREATE POLICY "professions_delete_admin"
    ON admin.professions FOR DELETE
    USING (admin.is_admin_of(organization_id));
