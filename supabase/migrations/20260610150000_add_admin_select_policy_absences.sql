-- Org-Admins dürfen die Absenzen ihrer Mitglieder lesen (für die Reports im
-- Admin-Tool). Bisher hatte app.absences nur "own"- und Moderator-Select-Policies,
-- analog zu app.activity_records (activity_records_select erlaubt is_admin_of).
-- Policies werden ge-OR-t, die bestehende "absences_select_own" bleibt.

CREATE POLICY "absences_select_admin"
    ON app.absences FOR SELECT
    USING (admin.is_admin_of(organization_id));
