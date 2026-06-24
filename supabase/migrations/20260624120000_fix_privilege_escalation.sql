-- Security-Fix: Privilege-Escalation schliessen.
--
-- Hintergrund (Audit 2026-06-24):
--   CRITICAL: app.profiles.user_role lag in einer Tabelle, die jeder User per
--             RLS (profiles_update_own) und tabellenweitem UPDATE-Grant selbst
--             beschreiben darf. Damit konnte sich jeder authentifizierte User
--             via direktem PostgREST-PATCH auf user_role='system_admin' setzen
--             und war Plattform-Admin. is_system_admin() liest genau diese Spalte.
--   HIGH:     Die INSERT-Policy auf admin.invites (is_admin_of) schraenkte
--             user_role nicht ein -> ein Org-Admin konnte ueber einen Org-Invite
--             die Rolle 'system_admin' vergeben. accept_invite_for uebernahm sie
--             via GREATEST in app.profiles.user_role.
--   HIGH:     GREATEST(user_role, invite_role) nutzt die Enum-Sortierung als
--             Hierarchie. Da 'moderator' als letzter Enum-Wert ergaenzt wurde,
--             galt moderator > system_admin > admin > user -> falsche Hierarchie.
--
-- Beabsichtigte Rollen-Hierarchie: system_admin > admin > moderator > user.

-- ===========================================================================
-- 1) CRITICAL: user_role gegen Selbst-Eskalation schuetzen (Trigger-Guard)
-- ===========================================================================
-- Spaltenweise Grants sind gegen den bestehenden tabellenweiten UPDATE-Grant
-- nicht zuverlaessig (PostgreSQL verrechnet Tabellen- und Spalten-Privilegien
-- getrennt). Ein BEFORE INSERT/UPDATE-Trigger ist die robuste Variante: er
-- blockt jede Aenderung von user_role aus dem PostgREST-Rollenkontext
-- ('authenticated'/'anon'). Serverseitige SECURITY-DEFINER-RPCs (accept_invite_for)
-- laufen als Function-Owner und sind nicht betroffen; das Backend nutzt
-- ausserdem den service_role-Kontext.

CREATE OR REPLACE FUNCTION app.guard_profile_user_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    IF current_user IN ('authenticated', 'anon') THEN
        IF TG_OP = 'INSERT' THEN
            IF NEW.user_role IS DISTINCT FROM 'user'::app.user_role THEN
                RAISE EXCEPTION 'user_role cannot be set by the user'
                    USING ERRCODE = '42501';
            END IF;
        ELSIF TG_OP = 'UPDATE' THEN
            IF NEW.user_role IS DISTINCT FROM OLD.user_role THEN
                RAISE EXCEPTION 'user_role cannot be changed by the user'
                    USING ERRCODE = '42501';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION app.guard_profile_user_role() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_guard_profile_user_role ON app.profiles;
CREATE TRIGGER trg_guard_profile_user_role
    BEFORE INSERT OR UPDATE ON app.profiles
    FOR EACH ROW
    EXECUTE FUNCTION app.guard_profile_user_role();

-- ===========================================================================
-- 2) HIGH: Invites duerfen niemals 'system_admin' vergeben
-- ===========================================================================
-- Bestehende Constraint invites_platform_requires_admin_role erzwingt bereits:
-- org_id IS NULL  -> user_role = 'admin' (Platform-Invite, RLS: nur system_admin).
-- Ergaenzend: 'system_admin' ist ueber KEINEN Invite-Pfad zulaessig. Plattform-
-- Admins werden ausschliesslich serverseitig/seed-seitig vergeben.
ALTER TABLE admin.invites
    DROP CONSTRAINT IF EXISTS invites_no_system_admin;
ALTER TABLE admin.invites
    ADD CONSTRAINT invites_no_system_admin
    CHECK (user_role <> 'system_admin');

-- ===========================================================================
-- 3) HIGH: Rollen-Hierarchie explizit statt ueber Enum-Sortierung
-- ===========================================================================
CREATE OR REPLACE FUNCTION internal.role_rank(r app.user_role)
RETURNS int
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
    SELECT CASE r
        WHEN 'system_admin' THEN 3
        WHEN 'admin'        THEN 2
        WHEN 'moderator'    THEN 1
        WHEN 'user'         THEN 0
        ELSE 0
    END;
$$;

REVOKE EXECUTE ON FUNCTION internal.role_rank(app.user_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION internal.role_rank(app.user_role) TO authenticated, service_role;

-- accept_invite_for neu aufsetzen: GREATEST durch rangbasierte Auswahl ersetzen.
-- Signatur unveraendert -> bestehende GRANTs (nur service_role) bleiben erhalten.
CREATE OR REPLACE FUNCTION admin.accept_invite_for(
    p_user_id uuid,
    invite_token uuid,
    p_first_name text,
    p_last_name text
)
RETURNS void AS $$
DECLARE
    v_invite record;
BEGIN
    SELECT * INTO v_invite
    FROM admin.invites
    WHERE token = invite_token AND status = 'pending';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invite not found or already used';
    END IF;
    IF v_invite.expires_at < now() THEN
        UPDATE admin.invites SET status = 'expired' WHERE id = v_invite.id;
        RAISE EXCEPTION 'Invite has expired';
    END IF;

    -- Nur Org-Invites schreiben in organization_members
    IF v_invite.organization_id IS NOT NULL THEN
        INSERT INTO admin.organization_members (user_id, organization_id, user_role)
        VALUES (p_user_id, v_invite.organization_id, v_invite.user_role)
        ON CONFLICT (user_id, organization_id) DO UPDATE
            SET user_role = EXCLUDED.user_role;
    END IF;

    UPDATE admin.invites SET status = 'accepted' WHERE id = v_invite.id;

    UPDATE app.profiles
    SET onboarding_status = 'completed',
        first_name = p_first_name,
        last_name  = p_last_name,
        user_role  = CASE
            WHEN internal.role_rank(v_invite.user_role) > internal.role_rank(user_role)
                THEN v_invite.user_role
            ELSE user_role
        END
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';
