-- Existing-User-Invite: bestehende User koennen zu weiteren Organisationen
-- eingeladen werden, ohne erneutes Onboarding (kein generate_link, kein
-- Setzen von Passwort/Namen).
--
-- Pendant zu admin.accept_invite_for (Neu-User, Service-Role). Hier ruft der
-- eingeloggte User selber auf, die RPC liest auth.uid() statt einen
-- p_user_id-Parameter zu vertrauen.
--
-- Anders als accept_invite_for wird app.profiles NICHT angefasst: ein
-- Plattform-Admin, der als Moderator zu Org X eingeladen wird, bleibt global
-- Admin und ist in Org X nur via organization_members.user_role Moderator.

CREATE OR REPLACE FUNCTION admin.accept_org_invite_for_existing_user(
    invite_token uuid
)
RETURNS void AS $$
DECLARE
    v_invite      admin.invites%ROWTYPE;
    v_user_id     uuid := auth.uid();
    v_user_email  text;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
    END IF;

    SELECT * INTO v_invite
      FROM admin.invites
     WHERE token = invite_token
       AND status = 'pending'
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'invite_invalid' USING ERRCODE = 'P0002';
    END IF;

    IF v_invite.expires_at < now() THEN
        UPDATE admin.invites SET status = 'expired' WHERE id = v_invite.id;
        RAISE EXCEPTION 'invite_expired' USING ERRCODE = 'P0002';
    END IF;

    IF v_invite.organization_id IS NULL THEN
        -- Plattform-Invites (admin/moderator/system_admin) laufen weiterhin
        -- ueber den Neu-User-Flow; diese RPC ist Org-Scope only.
        RAISE EXCEPTION 'invite_not_org_scoped' USING ERRCODE = '22023';
    END IF;

    SELECT email INTO v_user_email
      FROM auth.users
     WHERE id = v_user_id;

    IF v_user_email IS NULL OR lower(v_user_email) <> lower(v_invite.email) THEN
        RAISE EXCEPTION 'email_mismatch' USING ERRCODE = '28000';
    END IF;

    -- Profil muss existieren — sonst ist der Neu-User-Pfad richtig, nicht
    -- dieser hier (sonst staende der User in keiner app.profiles-Zeile).
    IF NOT EXISTS (SELECT 1 FROM app.profiles WHERE id = v_user_id) THEN
        RAISE EXCEPTION 'profile_missing' USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO admin.organization_members (user_id, organization_id, user_role, current_semester)
    VALUES (v_user_id, v_invite.organization_id, v_invite.user_role, v_invite.current_semester)
    ON CONFLICT (user_id, organization_id) DO UPDATE
        SET user_role = EXCLUDED.user_role;

    UPDATE admin.invites SET status = 'accepted' WHERE id = v_invite.id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION admin.accept_org_invite_for_existing_user(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin.accept_org_invite_for_existing_user(uuid) TO authenticated;
