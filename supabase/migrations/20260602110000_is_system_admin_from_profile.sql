-- is_system_admin() liest die Rolle jetzt direkt aus app.profiles.user_role,
-- damit Platform-Admins (ohne Org-Mitgliedschaft) korrekt erkannt werden.

CREATE OR REPLACE FUNCTION admin.is_system_admin()
RETURNS boolean AS $$
SELECT EXISTS (
    SELECT 1 FROM app.profiles
    WHERE id = auth.uid()
      AND user_role = 'system_admin'
);
$$ LANGUAGE sql SECURITY DEFINER STABLE
   SET search_path = '';
