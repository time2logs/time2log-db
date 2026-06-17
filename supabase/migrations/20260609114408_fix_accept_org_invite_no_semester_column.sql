-- Fix fuer 20260609094815_accept_org_invite_for_existing_user.sql:
-- Die vorherige Version hat current_semester in admin.organization_members
-- geschrieben, aber diese Spalte existiert dort nicht (sie wurde in
-- 20260408114755_add_semester_column.sql nur zu app.profiles, admin.invites
-- und app.activity_records hinzugefuegt — Semester ist user-global, nicht
-- per Membership). Der INSERT scheiterte mit
-- 'column "current_semester" of relation "organization_members" does not exist'
-- und das Frontend zeigte "Einladung ungueltig".
--
-- Inhaltlich passt das ohnehin so: ein Existing-User, der einer weiteren Org
-- beitritt, behaelt seinen bestehenden Semester auf dem Profil — wir
-- ignorieren das Invite-Semester an dieser Stelle bewusst.

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
        RAISE EXCEPTION 'invite_not_org_scoped' USING ERRCODE = '22023';
    END IF;

    SELECT email INTO v_user_email
      FROM auth.users
     WHERE id = v_user_id;

    IF v_user_email IS NULL OR lower(v_user_email) <> lower(v_invite.email) THEN
        RAISE EXCEPTION 'email_mismatch' USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM app.profiles WHERE id = v_user_id) THEN
        RAISE EXCEPTION 'profile_missing' USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO admin.organization_members (user_id, organization_id, user_role)
    VALUES (v_user_id, v_invite.organization_id, v_invite.user_role)
    ON CONFLICT (user_id, organization_id) DO UPDATE
        SET user_role = EXCLUDED.user_role;

    UPDATE admin.invites SET status = 'accepted' WHERE id = v_invite.id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION admin.accept_org_invite_for_existing_user(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin.accept_org_invite_for_existing_user(uuid) TO authenticated;
