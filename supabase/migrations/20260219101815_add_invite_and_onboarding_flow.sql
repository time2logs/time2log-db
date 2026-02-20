CREATE TYPE app.onboarding_status AS ENUM (
    'pending',
    'in_progress',
    'completed'
);

ALTER TABLE app.profiles
    ADD COLUMN onboarding_status app.onboarding_status
        NOT NULL DEFAULT 'pending',
    ADD COLUMN onboarding_completed_at timestamptz;

CREATE OR REPLACE FUNCTION app.set_onboarding_completed_at()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.onboarding_status = 'completed'
       AND OLD.onboarding_status <> 'completed' THEN
        NEW.onboarding_completed_at := now();
    ELSIF NEW.onboarding_status <> 'completed'
       AND OLD.onboarding_status = 'completed' THEN
        NEW.onboarding_completed_at := NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_set_onboarding_completed_at
    BEFORE UPDATE ON app.profiles
    FOR EACH ROW
    EXECUTE FUNCTION app.set_onboarding_completed_at();

-- 2. admin.invites table
-- ============================================================
CREATE TYPE admin.invite_status AS ENUM ('pending', 'accepted', 'expired');

CREATE TABLE admin.invites (
    id uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES admin.organizations(id) ON DELETE CASCADE,
    email text NOT NULL,
    user_role app.user_role NOT NULL DEFAULT 'user',
    token uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    status admin.invite_status NOT NULL DEFAULT 'pending',
    invited_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    expires_at timestamp with time zone NOT NULL DEFAULT (now() + INTERVAL '7 days')
);

CREATE INDEX idx_invites_token ON admin.invites (token);
CREATE INDEX idx_invites_email ON admin.invites (email);
CREATE INDEX idx_invites_org ON admin.invites (organization_id);

-- 3. RLS policies for admin.invites
-- ============================================================
ALTER TABLE admin.invites ENABLE ROW LEVEL SECURITY;

-- Org-Admins can view invites of their org
CREATE POLICY "invites_select_admin"
    ON admin.invites FOR SELECT
    USING (admin.is_admin_of(organization_id));

-- Org-Admins can create invites
CREATE POLICY "invites_insert_admin"
    ON admin.invites FOR INSERT
    WITH CHECK (admin.is_admin_of(organization_id));

-- Org-Admins can delete (cancel) invites
CREATE POLICY "invites_delete_admin"
    ON admin.invites FOR DELETE
    USING (admin.is_admin_of(organization_id));

-- 4. RPC: get_invite_details
-- ============================================================
CREATE OR REPLACE FUNCTION admin.get_invite_details(invite_token uuid)
RETURNS jsonb AS $$
DECLARE
    v_invite record;
BEGIN
    SELECT i.*, o.name AS org_name
    INTO v_invite
    FROM admin.invites i
    JOIN admin.organizations o ON o.id = i.organization_id
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

GRANT EXECUTE ON FUNCTION admin.get_invite_details(uuid) TO authenticated;

-- 5. RPC: accept_invite (after signup)
-- ============================================================
CREATE OR REPLACE FUNCTION admin.accept_invite(invite_token uuid)
RETURNS void AS $$
DECLARE
    v_invite record;
    v_user_email text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT email INTO v_user_email
    FROM auth.users
    WHERE id = auth.uid();

    SELECT * INTO v_invite
    FROM admin.invites
    WHERE token = invite_token
      AND status = 'pending';

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
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = '';

GRANT EXECUTE ON FUNCTION admin.accept_invite(uuid) TO authenticated;
