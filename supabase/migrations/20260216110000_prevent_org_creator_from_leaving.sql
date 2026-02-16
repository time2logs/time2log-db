-- Creator darf die eigene Organisation nicht verlassen
DROP POLICY IF EXISTS "org_members_delete_admin" ON admin.organization_members;

CREATE POLICY "org_members_delete_admin"
    ON admin.organization_members FOR DELETE
    USING (
        admin.is_admin_of(organization_id)
        AND (
            user_id <> auth.uid()
            OR NOT EXISTS (
                SELECT 1
                FROM admin.organizations o
                WHERE o.id = organization_id
                  AND o.created_by = auth.uid()
            )
        )
    );
