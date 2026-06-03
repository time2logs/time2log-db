-- Moderator darf seine Org NICHT loeschen.
-- is_admin_of() schliesst Moderator ein (fuer alle anderen Admin-Aktionen
-- gewollt). Fuer den Org-DELETE braucht es eine zusaetzliche Bedingung,
-- die Moderatoren ausschliesst.

DROP POLICY IF EXISTS "orgs_delete_admin" ON admin.organizations;

CREATE POLICY "orgs_delete_admin"
    ON admin.organizations FOR DELETE
    USING (
        admin.is_admin_of(id)
        AND (SELECT user_role FROM app.profiles WHERE id = auth.uid()) <> 'moderator'
    );
