-- Create absences table
CREATE TABLE app.absences (
    id UUID NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES app.profiles(id) ON DELETE CASCADE,
    team_id UUID REFERENCES admin.teams(id) ON DELETE SET NULL,
    organization_id UUID NOT NULL REFERENCES admin.organizations(id) ON DELETE CASCADE,
    absence_type_id TEXT NOT NULL REFERENCES app.absence_types(id) ON DELETE RESTRICT,
    entry_date DATE NOT NULL,
    is_recurring BOOLEAN NOT NULL DEFAULT FALSE,
    recurrence_pattern JSONB,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, entry_date)
);

CREATE TRIGGER set_updated_at_absences
    BEFORE UPDATE ON app.absences
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE INDEX idx_absences_user_date ON app.absences (user_id, entry_date DESC);
CREATE INDEX idx_absences_org_date ON app.absences (organization_id, entry_date DESC);
CREATE INDEX idx_absences_type ON app.absences (absence_type_id);

-- RLS: app.absences
-- =============================================================================
ALTER TABLE app.absences ENABLE ROW LEVEL SECURITY;

-- Users can read their own absences
CREATE POLICY "absences_select_own" ON app.absences FOR SELECT USING (user_id = auth.uid());

-- Users can insert their own absences
CREATE POLICY "absences_insert_own" ON app.absences FOR INSERT WITH CHECK (user_id = auth.uid());

-- Users can update their own absences
CREATE POLICY "absences_update_own" ON app.absences FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- Users can delete their own absences
CREATE POLICY "absences_delete_own" ON app.absences FOR DELETE USING (user_id = auth.uid());
