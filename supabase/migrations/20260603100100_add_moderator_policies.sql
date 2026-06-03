-- Moderator-Rolle: Schritt 2 von 2.
-- Globale Lese-Berechtigung, keine Schreib-Rechte.
-- Schreiben kann moderator nirgends, weil keine INSERT/UPDATE/DELETE-Policy
-- ihn matched (bestehende Write-Policies pruefen is_admin / is_system_admin /
-- Eigentum, nicht moderator).

-- 1. Helper-Funktion
-- ============================================================
CREATE OR REPLACE FUNCTION admin.is_moderator()
RETURNS boolean AS $$
SELECT EXISTS (
    SELECT 1 FROM app.profiles
    WHERE id = auth.uid()
      AND user_role = 'moderator'
);
$$ LANGUAGE sql SECURITY DEFINER STABLE
   SET search_path = '';

-- 2. SELECT-Policies fuer Moderator (analog zu system_admin)
-- ============================================================

-- Profile lesen (alle)
CREATE POLICY "profiles_select_moderator"
    ON app.profiles FOR SELECT
    USING (admin.is_moderator());

-- Organisationen lesen
CREATE POLICY "organizations_select_moderator"
    ON admin.organizations FOR SELECT
    USING (admin.is_moderator());

-- Organisations-Mitgliedschaften lesen
CREATE POLICY "organization_members_select_moderator"
    ON admin.organization_members FOR SELECT
    USING (admin.is_moderator());

-- Invites lesen (Platform- und Org-Invites)
CREATE POLICY "invites_select_moderator"
    ON admin.invites FOR SELECT
    USING (admin.is_moderator());

-- Professions / Bildungspläne
CREATE POLICY "professions_select_moderator"
    ON admin.professions FOR SELECT
    USING (admin.is_moderator());

-- Teams
CREATE POLICY "teams_select_moderator"
    ON admin.teams FOR SELECT
    USING (admin.is_moderator());

CREATE POLICY "team_members_select_moderator"
    ON admin.team_members FOR SELECT
    USING (admin.is_moderator());

-- Curriculum-Daten
CREATE POLICY "competencies_select_moderator"
    ON admin.competencies FOR SELECT
    USING (admin.is_moderator());

CREATE POLICY "curriculum_nodes_select_moderator"
    ON admin.curriculum_nodes FOR SELECT
    USING (admin.is_moderator());

CREATE POLICY "curriculum_node_competencies_select_moderator"
    ON admin.curriculum_node_competencies FOR SELECT
    USING (admin.is_moderator());

CREATE POLICY "curriculum_imports_select_moderator"
    ON admin.curriculum_imports FOR SELECT
    USING (admin.is_moderator());

-- Aktivitaeten / Absenzen
CREATE POLICY "activity_records_select_moderator"
    ON app.activity_records FOR SELECT
    USING (admin.is_moderator());

CREATE POLICY "absence_types_select_moderator"
    ON app.absence_types FOR SELECT
    USING (admin.is_moderator());

CREATE POLICY "absences_select_moderator"
    ON app.absences FOR SELECT
    USING (admin.is_moderator());

-- User-Locations
CREATE POLICY "user_locations_select_moderator"
    ON app.user_locations FOR SELECT
    USING (admin.is_moderator());

-- Reminder-Einstellungen
CREATE POLICY "reminder_select_moderator"
    ON admin.reminder FOR SELECT
    USING (admin.is_moderator());
