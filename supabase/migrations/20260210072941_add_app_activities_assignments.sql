CREATE TABLE app.activities_assignments (
    id uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    activity_id uuid NOT NULL REFERENCES app.pre_defined_activities(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    start_time timestamp with time zone NOT NULL,
    end_time timestamp with time zone,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON app.activities_assignments
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- RLS
-- =============================================================================
ALTER TABLE app.activities_assignments ENABLE ROW LEVEL SECURITY;

-- User darf eigene Assignments lesen + Admins dürfen Assignments ihrer Org lesen
CREATE POLICY "assignments_select"
    ON app.activities_assignments FOR SELECT
    USING (
        user_id = auth.uid()
        OR admin.is_admin_of((
            SELECT organization_id FROM app.pre_defined_activities
            WHERE id = activity_id
        ))
    );

-- User darf eigene Assignments erstellen
CREATE POLICY "assignments_insert_own"
    ON app.activities_assignments FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- User darf eigene Assignments bearbeiten
CREATE POLICY "assignments_update_own"
    ON app.activities_assignments FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- User darf eigene Assignments löschen
CREATE POLICY "assignments_delete_own"
    ON app.activities_assignments FOR DELETE
    USING (user_id = auth.uid());
