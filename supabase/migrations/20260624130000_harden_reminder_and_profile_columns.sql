-- Security-Fix (Audit 2026-06-24, zweiter Durchgang):
--
--   MEDIUM: admin.reminder hatte RLS NIE aktiviert. Die Policies
--           reminder_select/insert/update_admin existierten, waren aber
--           wirkungslos. Zusammen mit dem tabellenweiten GRANT an authenticated
--           konnte jeder eingeloggte User die Reminder-Konfiguration ALLER
--           Organisationen lesen, aendern und loeschen.
--
--   LOW/MED: app.profiles.onboarding_status und current_semester waren ueber
--           profiles_update_own (eigene Zeile, ohne Spalten-Einschraenkung)
--           selbst setzbar. Ein User konnte sein Onboarding selbst als
--           'completed' markieren bzw. sein Semester beliebig aendern
--           (verfaelscht Reports/Sollstunden-Filter).
--
-- Beide Spalten werden legitim ausschliesslich von SECURITY-DEFINER-Funktionen
-- (app.accept_invite, admin.accept_invite_for) bzw. dem Service-Role-Rollover
-- gesetzt -- diese laufen NICHT im 'authenticated'/'anon'-Rollenkontext und sind
-- vom Guard daher nicht betroffen.

-- ===========================================================================
-- 1) admin.reminder: RLS aktivieren (Policies existieren bereits)
-- ===========================================================================
ALTER TABLE admin.reminder ENABLE ROW LEVEL SECURITY;

-- ===========================================================================
-- 2) Profil-Spalten-Guard erweitern: user_role + onboarding_* + current_semester
-- ===========================================================================
-- Ersetzt den bisherigen reinen user_role-Guard (20260624120000) durch eine
-- generische Schutzfunktion fuer alle privilegierten Profil-Spalten.

CREATE OR REPLACE FUNCTION app.guard_profile_privileged_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    -- Nur direkte Writes aus dem PostgREST-Rollenkontext einschraenken.
    -- service_role und SECURITY-DEFINER-Funktionen (Owner) bleiben unberuehrt.
    IF current_user IN ('authenticated', 'anon') THEN
        IF TG_OP = 'INSERT' THEN
            IF NEW.user_role IS DISTINCT FROM 'user'::app.user_role THEN
                RAISE EXCEPTION 'user_role cannot be set by the user'
                    USING ERRCODE = '42501';
            END IF;
            IF NEW.onboarding_status IS DISTINCT FROM 'pending'::app.onboarding_status THEN
                RAISE EXCEPTION 'onboarding_status cannot be set by the user'
                    USING ERRCODE = '42501';
            END IF;
            IF NEW.current_semester IS NOT NULL THEN
                RAISE EXCEPTION 'current_semester cannot be set by the user'
                    USING ERRCODE = '42501';
            END IF;
        ELSIF TG_OP = 'UPDATE' THEN
            IF NEW.user_role IS DISTINCT FROM OLD.user_role THEN
                RAISE EXCEPTION 'user_role cannot be changed by the user'
                    USING ERRCODE = '42501';
            END IF;
            IF NEW.onboarding_status IS DISTINCT FROM OLD.onboarding_status THEN
                RAISE EXCEPTION 'onboarding_status cannot be changed by the user'
                    USING ERRCODE = '42501';
            END IF;
            IF NEW.onboarding_completed_at IS DISTINCT FROM OLD.onboarding_completed_at THEN
                RAISE EXCEPTION 'onboarding_completed_at cannot be changed by the user'
                    USING ERRCODE = '42501';
            END IF;
            IF NEW.current_semester IS DISTINCT FROM OLD.current_semester THEN
                RAISE EXCEPTION 'current_semester cannot be changed by the user'
                    USING ERRCODE = '42501';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION app.guard_profile_privileged_columns() FROM PUBLIC, anon;

-- Trigger auf die neue Funktion umstellen und alten Guard abloesen.
DROP TRIGGER IF EXISTS trg_guard_profile_user_role ON app.profiles;
DROP TRIGGER IF EXISTS trg_guard_profile_privileged_columns ON app.profiles;
CREATE TRIGGER trg_guard_profile_privileged_columns
    BEFORE INSERT OR UPDATE ON app.profiles
    FOR EACH ROW
    EXECUTE FUNCTION app.guard_profile_privileged_columns();

DROP FUNCTION IF EXISTS app.guard_profile_user_role();
