CREATE TABLE app.pre_defined_activities (
    id uuid NOT NULL PRIMARY KEY,
    organization_id uuid NOT NULL REFERENCES admin.organizations(id) ON DELETE CASCADE,
    key text NOT NULL,
    label text NOT NULL,
    description text,
    category text,
    meta jsonb,
    is_active boolean NOT NULL DEFAULT true,
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
    BEFORE UPDATE ON app.pre_defined_activities
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- RLS
ALTER TABLE app.pre_defined_activities ENABLE ROW LEVEL SECURITY;

-- Alle Org-Mitglieder dürfen Activities lesen
CREATE POLICY "pre_defined_activities_select_member"
    ON app.pre_defined_activities FOR SELECT
    USING (admin.is_member_of(organization_id));

-- Nur Admins dürfen Activities erstellen
CREATE POLICY "pre_defined_activities_insert_admin"
    ON app.pre_defined_activities FOR INSERT
    WITH CHECK (admin.is_admin() AND admin.is_member_of(organization_id));

-- Nur Admins dürfen Activities bearbeiten
CREATE POLICY "pre_defined_activities_update_admin"
    ON app.pre_defined_activities FOR UPDATE
    USING (admin.is_admin() AND admin.is_member_of(organization_id))
    WITH CHECK (admin.is_admin() AND admin.is_member_of(organization_id));

-- Nur Admins dürfen Activities löschen
CREATE POLICY "pre_defined_activities_delete_admin"
    ON app.pre_defined_activities FOR DELETE
    USING (admin.is_admin() AND admin.is_member_of(organization_id));