-- is_admin() und is_admin_of(): system_admin zählt wie admin
-- (is_member_of() filtert nicht nach Rolle -> system_admin ist als Mitglied bereits abgedeckt)

CREATE OR REPLACE FUNCTION admin.is_admin()
RETURNS boolean AS $$
SELECT EXISTS (
    SELECT 1 FROM admin.organization_members
    WHERE user_id = auth.uid()
      AND user_role IN ('admin', 'system_admin')
);
$$ LANGUAGE sql SECURITY DEFINER STABLE
   SET search_path = '';

CREATE OR REPLACE FUNCTION admin.is_admin_of(org_id uuid)
RETURNS boolean AS $$
SELECT EXISTS (
    SELECT 1 FROM admin.organization_members
    WHERE user_id = auth.uid()
      AND organization_id = org_id
      AND user_role IN ('admin', 'system_admin')
);
$$ LANGUAGE sql SECURITY DEFINER STABLE
   SET search_path = '';

-- Profil-Lese-Policy prüft user_role direkt inline -> ebenfalls anpassen
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