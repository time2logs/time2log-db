-- Moderator-Rolle neu definieren:
--   * KEIN globaler Lesezugriff (frueher: sah alle Orgs, alle Profile, etc.)
--   * Innerhalb der eigenen Org gleiche Rechte wie ein admin
--   * Darf KEINE neuen Orgs erstellen
--   * Darf KEINE weiteren Moderatoren einladen
--
-- Umsetzung:
--   1. Globale Moderator-SELECT-Policies entfernen
--   2. admin.is_admin_of(org) erweitern -> 'moderator' zaehlt als admin in der eigenen Org
--   3. profiles_select_admin_org auf 'moderator' erweitern
--   4. orgs_insert_admin: Moderatoren ausschliessen
--   5. invites_insert_admin: Moderatoren duerfen keine Moderator-Invites anlegen

-- 1. Globale Moderator-SELECT-Policies entfernen
-- ============================================================
DROP POLICY IF EXISTS "profiles_select_moderator"                   ON app.profiles;
DROP POLICY IF EXISTS "organizations_select_moderator"              ON admin.organizations;
DROP POLICY IF EXISTS "organization_members_select_moderator"       ON admin.organization_members;
DROP POLICY IF EXISTS "invites_select_moderator"                    ON admin.invites;
DROP POLICY IF EXISTS "professions_select_moderator"                ON admin.professions;
DROP POLICY IF EXISTS "teams_select_moderator"                      ON admin.teams;
DROP POLICY IF EXISTS "team_members_select_moderator"               ON admin.team_members;
DROP POLICY IF EXISTS "competencies_select_moderator"               ON admin.competencies;
DROP POLICY IF EXISTS "curriculum_nodes_select_moderator"           ON admin.curriculum_nodes;
DROP POLICY IF EXISTS "curriculum_node_competencies_select_moderator" ON admin.curriculum_node_competencies;
DROP POLICY IF EXISTS "curriculum_imports_select_moderator"         ON admin.curriculum_imports;
DROP POLICY IF EXISTS "activity_records_select_moderator"           ON app.activity_records;
DROP POLICY IF EXISTS "absence_types_select_moderator"              ON app.absence_types;
DROP POLICY IF EXISTS "absences_select_moderator"                   ON app.absences;
DROP POLICY IF EXISTS "user_locations_select_moderator"             ON app.user_locations;
DROP POLICY IF EXISTS "reminder_select_moderator"                   ON admin.reminder;

-- 2. is_admin_of(): Moderator zaehlt wie admin in seiner Org
-- ============================================================
CREATE OR REPLACE FUNCTION admin.is_admin_of(org_id uuid)
RETURNS boolean AS $$
SELECT EXISTS (
    SELECT 1 FROM admin.organization_members
    WHERE user_id = auth.uid()
      AND organization_id = org_id
      AND user_role IN ('admin', 'system_admin', 'moderator')
);
$$ LANGUAGE sql SECURITY DEFINER STABLE
   SET search_path = '';

-- 3. profiles_select_admin_org: 'moderator' ergaenzen
-- ============================================================
DROP POLICY IF EXISTS "profiles_select_admin_org" ON app.profiles;

CREATE POLICY "profiles_select_admin_org"
    ON app.profiles FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM admin.organization_members om1
            JOIN admin.organization_members om2
              ON om1.organization_id = om2.organization_id
            WHERE om1.user_id = auth.uid()
              AND om1.user_role IN ('admin', 'system_admin', 'moderator')
              AND om2.user_id = app.profiles.id
        )
    );

-- 4. orgs_insert_admin: Moderatoren duerfen keine Orgs erstellen
-- ============================================================
DROP POLICY IF EXISTS "orgs_insert_admin" ON admin.organizations;

CREATE POLICY "orgs_insert_admin"
    ON admin.organizations FOR INSERT
    WITH CHECK (
        auth.uid() IS NOT NULL
        AND (
            SELECT user_role FROM app.profiles WHERE id = auth.uid()
        ) <> 'moderator'
    );

-- 5. invites_insert_admin: Moderator darf nicht 'moderator' einladen
-- ============================================================
DROP POLICY IF EXISTS "invites_insert_admin" ON admin.invites;

CREATE POLICY "invites_insert_admin"
    ON admin.invites FOR INSERT
    WITH CHECK (
        admin.is_admin_of(organization_id)
        AND (
            -- Wenn der Caller ein Moderator ist, darf user_role nicht 'moderator' sein
            user_role <> 'moderator'
            OR (SELECT user_role FROM app.profiles WHERE id = auth.uid()) <> 'moderator'
        )
    );
