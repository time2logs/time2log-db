-- Speichert die "globale" Rolle eines Users direkt am Profil, statt sie
-- jedes Mal aus admin.organization_members ableiten zu muessen.
-- Hierarchie: system_admin > admin > user.

-- 1. Spalte hinzufuegen (default 'user', NOT NULL)
-- ============================================================
ALTER TABLE app.profiles
    ADD COLUMN user_role app.user_role NOT NULL DEFAULT 'user';

-- 2. Backfill: hoechste Rolle aus organization_members uebernehmen
-- ============================================================
UPDATE app.profiles p
SET user_role = sub.highest_role
FROM (
    SELECT
        user_id,
        CASE
            WHEN bool_or(user_role = 'system_admin') THEN 'system_admin'::app.user_role
            WHEN bool_or(user_role = 'admin')        THEN 'admin'::app.user_role
            ELSE 'user'::app.user_role
        END AS highest_role
    FROM admin.organization_members
    GROUP BY user_id
) sub
WHERE p.id = sub.user_id;

-- 3. accept_invite_for: Rolle auch auf das Profil schreiben
-- ============================================================
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
        user_role  = GREATEST(user_role, v_invite.user_role)
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';
