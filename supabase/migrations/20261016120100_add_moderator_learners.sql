CREATE OR REPLACE FUNCTION internal.is_admin_of(org_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM admin.organization_members
        WHERE user_id = auth.uid()
          AND organization_id = org_id
          AND user_role IN ('admin', 'system_admin')
    );
$$;

DROP POLICY IF EXISTS "profiles_select_admin_org" ON app.profiles;

CREATE POLICY "profiles_select_admin_org"
    ON app.profiles FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM admin.organization_members om1
            JOIN admin.organization_members om2
              ON om1.organization_id = om2.organization_id
            WHERE om1.user_id = auth.uid()
              AND om1.user_role IN ('admin', 'system_admin')
              AND om2.user_id = app.profiles.id
        )
    );

CREATE TABLE admin.moderator_learners (
    organization_id uuid NOT NULL,
    moderator_id uuid NOT NULL,
    learner_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    PRIMARY KEY (organization_id, moderator_id, learner_id),
    FOREIGN KEY (moderator_id, organization_id)
        REFERENCES admin.organization_members (user_id, organization_id) ON DELETE CASCADE,
    FOREIGN KEY (learner_id, organization_id)
        REFERENCES admin.organization_members (user_id, organization_id) ON DELETE CASCADE
);

CREATE INDEX idx_moderator_learners_moderator ON admin.moderator_learners (moderator_id);
CREATE INDEX idx_moderator_learners_learner ON admin.moderator_learners (learner_id, organization_id);

ALTER TABLE admin.moderator_learners ENABLE ROW LEVEL SECURITY;

CREATE POLICY "moderator_learners_select"
    ON admin.moderator_learners FOR SELECT
    TO authenticated
    USING (
        admin.is_admin_of(organization_id)
        OR moderator_id = auth.uid()
    );

CREATE POLICY "moderator_learners_insert_admin"
    ON admin.moderator_learners FOR INSERT
    TO authenticated
    WITH CHECK (
        admin.is_admin_of(organization_id)
        AND EXISTS (
            SELECT 1 FROM admin.organization_members
            WHERE organization_id = moderator_learners.organization_id
              AND user_id = moderator_learners.moderator_id
              AND user_role = 'moderator'
        )
        AND EXISTS (
            SELECT 1 FROM admin.organization_members
            WHERE organization_id = moderator_learners.organization_id
              AND user_id = moderator_learners.learner_id
              AND user_role = 'user'
        )
    );

CREATE POLICY "moderator_learners_delete_admin"
    ON admin.moderator_learners FOR DELETE
    TO authenticated
    USING (admin.is_admin_of(organization_id));

GRANT SELECT, INSERT, DELETE ON admin.moderator_learners TO authenticated;

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
            FROM admin.moderator_learners ml
            JOIN admin.organization_members om
              ON om.organization_id = ml.organization_id
             AND om.user_id = ml.moderator_id
            WHERE ml.organization_id = p_org
              AND ml.moderator_id = auth.uid()
              AND ml.learner_id = p_user
              AND om.user_role = 'moderator'
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

CREATE POLICY "activity_records_select_moderator"
    ON app.activity_records FOR SELECT
    TO authenticated
    USING (admin.can_view_learner(organization_id, user_id));

CREATE POLICY "absences_select_moderator"
    ON app.absences FOR SELECT
    TO authenticated
    USING (admin.can_view_learner(organization_id, user_id));

CREATE POLICY "profiles_select_moderator"
    ON app.profiles FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM admin.moderator_learners ml
            WHERE ml.moderator_id = auth.uid()
              AND ml.learner_id = app.profiles.id
              AND admin.can_view_learner(ml.organization_id, ml.learner_id)
        )
    );
