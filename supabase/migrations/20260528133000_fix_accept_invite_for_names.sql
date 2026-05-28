-- Fix: accept_invite_for muss Vor-/Nachname mitschreiben.
-- Die urspruengliche Migration 20260528090435 wurde ggf. bereits mit der alten
-- 2-Parameter-Signatur angewendet; ein nachtraegliches Editieren wird von der
-- Supabase-Migrationshistorie nicht erneut ausgefuehrt. Daher hier als eigene
-- Migration (idempotent).

DROP FUNCTION IF EXISTS admin.accept_invite_for(uuid, uuid);
DROP FUNCTION IF EXISTS admin.accept_invite_for(uuid, uuid, text, text);

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
