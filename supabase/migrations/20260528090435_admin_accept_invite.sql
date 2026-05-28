-- Wird vom Backend (Service-Role) waehrend des Admin-Onboardings aufgerufen.
-- Anders als admin.accept_invite() basiert es nicht auf auth.uid(), sondern
-- bekommt die User-ID explizit und setzt zusaetzlich Vor-/Nachname im Profil
-- (handle_new_user legt das Profil nur mit leeren Namen an, und ein
--  user_metadata-Update synchronisiert das Profil nicht).

-- Alte Signatur (ohne Namen) entfernen, falls bereits angewendet.
DROP FUNCTION IF EXISTS admin.accept_invite_for(uuid, uuid);

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

    INSERT INTO admin.organization_members (user_id, organization_id, user_role)
    VALUES (p_user_id, v_invite.organization_id, v_invite.user_role)
    ON CONFLICT (user_id, organization_id) DO UPDATE
        SET user_role = EXCLUDED.user_role;

    UPDATE admin.invites SET status = 'accepted' WHERE id = v_invite.id;

    UPDATE app.profiles
    SET onboarding_status = 'completed',
        first_name = p_first_name,
        last_name  = p_last_name
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';
-- KEIN GRANT an authenticated noetig: nur Service-Role ruft auf
