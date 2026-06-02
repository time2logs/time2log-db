-- Platform-Invites haben organization_id IS NULL. Der bisherige INNER JOIN
-- auf admin.organizations verwarf solche Eintraege und das Frontend zeigte
-- "Invalid invite". LEFT JOIN, damit Platform-Invites korrekt geliefert
-- werden; organization_name ist dann NULL.

CREATE OR REPLACE FUNCTION admin.get_invite_details(invite_token uuid)
RETURNS jsonb AS $$
DECLARE
    v_invite record;
BEGIN
    SELECT i.*, o.name AS org_name
    INTO v_invite
    FROM admin.invites i
    LEFT JOIN admin.organizations o ON o.id = i.organization_id
    WHERE i.token = invite_token
      AND i.status = 'pending';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invite not found or no longer valid';
    END IF;

    IF v_invite.expires_at < now() THEN
        UPDATE admin.invites SET status = 'expired' WHERE id = v_invite.id;
        RAISE EXCEPTION 'Invite has expired';
    END IF;

    RETURN jsonb_build_object(
        'organization_name', v_invite.org_name,
        'email', v_invite.email,
        'role', v_invite.user_role
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = '';
