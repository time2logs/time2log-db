-- Admins dürfen Profile von Usern lesen, die in einer gemeinsamen Organisation sind

CREATE POLICY "profiles_select_admin_org"
    ON app.profiles FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM admin.organization_members om1
            JOIN admin.organization_members om2
              ON om1.organization_id = om2.organization_id
            WHERE om1.user_id = auth.uid()
              AND om1.user_role = 'admin'
              AND om2.user_id = app.profiles.id
        )
    );
