CREATE TABLE admin.curriculum_imports (
    id uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES admin.organizations(id) ON DELETE CASCADE,
    profession_id uuid NOT NULL REFERENCES admin.professions(id) ON DELETE CASCADE,
    uploaded_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    payload jsonb NOT NULL,
    version text NOT NULL,
    status text NOT NULL DEFAULT 'pending',
    error text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- RLS: admin.curriculum_imports
-- ===========================================================================
ALTER TABLE admin.curriculum_imports ENABLE ROW LEVEL SECURITY;

-- Org-Admins dürfen Imports sehen
CREATE POLICY "curriculum_imports_select_admin"
    ON admin.curriculum_imports FOR SELECT
    USING (admin.is_admin_of(organization_id));

-- Org-Admins dürfen Imports erstellen
CREATE POLICY "curriculum_imports_insert_admin"
    ON admin.curriculum_imports FOR INSERT
    WITH CHECK (admin.is_admin_of(organization_id));
