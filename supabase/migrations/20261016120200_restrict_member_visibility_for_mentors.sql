CREATE OR REPLACE FUNCTION internal.is_mentor_of(org_id uuid)
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
          AND user_role = 'mentor'
    );
$$;

REVOKE EXECUTE ON FUNCTION internal.is_mentor_of(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION internal.is_mentor_of(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION admin.is_mentor_of(org_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path = ''
AS $$
    SELECT internal.is_mentor_of(org_id);
$$;

REVOKE EXECUTE ON FUNCTION admin.is_mentor_of(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin.is_mentor_of(uuid) TO authenticated, service_role;

DROP POLICY IF EXISTS "org_members_select_member" ON admin.organization_members;

CREATE POLICY "org_members_select_member"
    ON admin.organization_members FOR SELECT
    USING (
        admin.is_member_of(organization_id)
        AND (
            NOT admin.is_mentor_of(organization_id)
            OR user_id = auth.uid()
            OR admin.can_view_learner(organization_id, user_id)
        )
    );

DROP POLICY IF EXISTS "team_members_select_member" ON admin.team_members;

CREATE POLICY "team_members_select_member"
    ON admin.team_members FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM admin.teams t
            WHERE t.id = team_members.team_id
              AND admin.is_member_of(t.organization_id)
              AND (
                  NOT admin.is_mentor_of(t.organization_id)
                  OR team_members.user_id = auth.uid()
                  OR admin.can_view_learner(t.organization_id, team_members.user_id)
              )
        )
    );
