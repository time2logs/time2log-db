-- 1. Ensure Profile Column exists
ALTER TABLE app.profiles ADD COLUMN IF NOT EXISTS avatar_url TEXT;

-- 2. Define get_invite_details in admin schema
CREATE OR REPLACE FUNCTION admin.get_invite_details(invite_token uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $body$
DECLARE
    v_invite record;
BEGIN
    SELECT i.*, o.name AS org_name
    INTO v_invite
    FROM admin.invites i
    JOIN admin.organizations o ON o.id = i.organization_id
    WHERE i.token = invite_token AND i.status = 'pending';

    IF NOT FOUND THEN RETURN NULL; END IF;

    RETURN jsonb_build_object(
        'organization_name', v_invite.org_name,
        'email', v_invite.email,
        'role', v_invite.user_role
    );
END;
$body$;

-- 3. Define accept_invite in app schema (where main client looks)
CREATE OR REPLACE FUNCTION app.accept_invite(invite_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $body$
DECLARE
    v_invite record;
    v_user_email text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT email INTO v_user_email FROM auth.users WHERE id = auth.uid();

    SELECT * INTO v_invite FROM admin.invites
    WHERE token = invite_token AND status = 'pending';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invite not found or already used';
    END IF;

    IF v_invite.expires_at < now() THEN
        UPDATE admin.invites SET status = 'expired' WHERE id = v_invite.id;
        RAISE EXCEPTION 'Invite has expired';
    END IF;

    IF lower(v_user_email) <> lower(v_invite.email) THEN
        RAISE EXCEPTION 'Email does not match invite';
    END IF;

    -- Add user to organization
    INSERT INTO admin.organization_members (user_id, organization_id, user_role)
    VALUES (auth.uid(), v_invite.organization_id, v_invite.user_role)
    ON CONFLICT (user_id, organization_id) DO UPDATE
        SET user_role = EXCLUDED.user_role;

    -- Mark invite as accepted
    UPDATE admin.invites
    SET status = 'accepted'
    WHERE id = v_invite.id;

    -- Complete onboarding
    UPDATE app.profiles
    SET onboarding_status = 'completed'
    WHERE id = auth.uid();
END;
$body$;

-- 4. Permissions
GRANT USAGE ON SCHEMA admin TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA app TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION admin.get_invite_details(uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION app.accept_invite(uuid) TO authenticated;
