-- System-Admin darf alle Profile lesen (fuer die Admin-Uebersicht im
-- System-Admin-Bereich des Frontends).

CREATE POLICY "profiles_select_system_admin"
    ON app.profiles FOR SELECT
    USING (admin.is_system_admin());
