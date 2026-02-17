CREATE TABLE app.activity_records (
    id uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES admin.organizations(id) ON DELETE CASCADE,
    profession_id uuid NOT NULL REFERENCES admin.professions(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    team_id uuid REFERENCES admin.teams(id) ON DELETE SET NULL,
    curriculum_activity_id uuid NOT NULL REFERENCES app.curriculum_nodes(id) ON DELETE RESTRICT,
    entry_date date NOT NULL,
    hours int NOT NULL CHECK (hours > 0 AND hours <= 24),
    notes text,
    rating int CHECK (rating >= 1 AND rating <= 5),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON app.activity_records
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE INDEX idx_activity_records_user_date
    ON app.activity_records (user_id, entry_date DESC);

CREATE INDEX idx_activity_records_org_date
    ON app.activity_records (organization_id, profession_id, entry_date DESC);

CREATE INDEX idx_activity_records_activity
    ON app.activity_records (curriculum_activity_id);

-- RLS: app.activity_records
-- ===========================================================================
ALTER TABLE app.activity_records ENABLE ROW LEVEL SECURITY;

-- User darf eigene Einträge lesen + Org-Admins dürfen alle Einträge ihrer Org lesen
CREATE POLICY "activity_records_select"
    ON app.activity_records FOR SELECT
    USING (
        user_id = auth.uid()
        OR admin.is_admin_of(organization_id)
    );

-- User darf eigene Einträge erstellen
CREATE POLICY "activity_records_insert_own"
    ON app.activity_records FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- User darf eigene Einträge bearbeiten
CREATE POLICY "activity_records_update_own"
    ON app.activity_records FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- User darf eigene Einträge löschen
CREATE POLICY "activity_records_delete_own"
    ON app.activity_records FOR DELETE
    USING (user_id = auth.uid());
