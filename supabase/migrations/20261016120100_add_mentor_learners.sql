CREATE TABLE admin.mentor_learners (
    organization_id uuid NOT NULL,
    mentor_id uuid NOT NULL,
    learner_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    PRIMARY KEY (organization_id, mentor_id, learner_id),
    FOREIGN KEY (mentor_id, organization_id)
        REFERENCES admin.organization_members (user_id, organization_id) ON DELETE CASCADE,
    FOREIGN KEY (learner_id, organization_id)
        REFERENCES admin.organization_members (user_id, organization_id) ON DELETE CASCADE
);

CREATE INDEX idx_mentor_learners_mentor ON admin.mentor_learners (mentor_id);
CREATE INDEX idx_mentor_learners_learner ON admin.mentor_learners (learner_id, organization_id);

ALTER TABLE admin.mentor_learners ENABLE ROW LEVEL SECURITY;

CREATE POLICY "mentor_learners_select"
    ON admin.mentor_learners FOR SELECT
    TO authenticated
    USING (
        admin.is_admin_of(organization_id)
        OR mentor_id = auth.uid()
    );

CREATE POLICY "mentor_learners_insert_admin"
    ON admin.mentor_learners FOR INSERT
    TO authenticated
    WITH CHECK (
        admin.is_admin_of(organization_id)
        AND EXISTS (
            SELECT 1 FROM admin.organization_members
            WHERE organization_id = mentor_learners.organization_id
              AND user_id = mentor_learners.mentor_id
              AND user_role = 'mentor'
        )
        AND EXISTS (
            SELECT 1 FROM admin.organization_members
            WHERE organization_id = mentor_learners.organization_id
              AND user_id = mentor_learners.learner_id
              AND user_role = 'user'
        )
    );

CREATE POLICY "mentor_learners_delete_admin"
    ON admin.mentor_learners FOR DELETE
    TO authenticated
    USING (admin.is_admin_of(organization_id));

GRANT SELECT, INSERT, DELETE ON admin.mentor_learners TO authenticated;

CREATE OR REPLACE FUNCTION internal.can_view_learner(p_org uuid, p_user uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
    SELECT internal.is_admin_of(p_org)
        OR EXISTS (
            SELECT 1
            FROM admin.mentor_learners ml
            JOIN admin.organization_members om
              ON om.organization_id = ml.organization_id
             AND om.user_id = ml.mentor_id
            WHERE ml.organization_id = p_org
              AND ml.mentor_id = auth.uid()
              AND ml.learner_id = p_user
              AND om.user_role = 'mentor'
        );
$$;

REVOKE EXECUTE ON FUNCTION internal.can_view_learner(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION internal.can_view_learner(uuid, uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION admin.can_view_learner(p_org uuid, p_user uuid)
RETURNS boolean
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path = ''
AS $$
    SELECT internal.can_view_learner(p_org, p_user);
$$;

REVOKE EXECUTE ON FUNCTION admin.can_view_learner(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin.can_view_learner(uuid, uuid) TO authenticated, service_role;

CREATE POLICY "activity_records_select_mentor"
    ON app.activity_records FOR SELECT
    TO authenticated
    USING (admin.can_view_learner(organization_id, user_id));

CREATE POLICY "absences_select_mentor"
    ON app.absences FOR SELECT
    TO authenticated
    USING (admin.can_view_learner(organization_id, user_id));

CREATE POLICY "profiles_select_mentor"
    ON app.profiles FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM admin.mentor_learners ml
            WHERE ml.mentor_id = auth.uid()
              AND ml.learner_id = app.profiles.id
              AND admin.can_view_learner(ml.organization_id, ml.learner_id)
        )
    );

CREATE OR REPLACE FUNCTION internal.role_rank(r app.user_role)
RETURNS int
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
    SELECT CASE r
        WHEN 'system_admin' THEN 4
        WHEN 'admin'        THEN 3
        WHEN 'moderator'    THEN 2
        WHEN 'mentor'       THEN 1
        WHEN 'user'         THEN 0
        ELSE 0
    END;
$$;
