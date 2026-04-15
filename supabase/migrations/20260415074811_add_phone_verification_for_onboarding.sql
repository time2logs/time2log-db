-- Add profile-scoped phone verification fields
ALTER TABLE app.profiles
	ADD COLUMN IF NOT EXISTS phone_number text,
	ADD COLUMN IF NOT EXISTS phone_verified boolean NOT NULL DEFAULT false,
	ADD COLUMN IF NOT EXISTS phone_verified_at timestamptz,
	ADD COLUMN IF NOT EXISTS phone_verification_code_hash text,
	ADD COLUMN IF NOT EXISTS phone_verification_code_expires_at timestamptz,
	ADD COLUMN IF NOT EXISTS last_time_sent timestamptz;

-- Event log for auditing + hourly rate-limiting
CREATE TABLE IF NOT EXISTS admin.sms_verification_events (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
	phone_number text NOT NULL,
	sent_at timestamptz NOT NULL DEFAULT now(),
	status text NOT NULL CHECK (status IN ('sent', 'failed')),
	provider_message_id text,
	error_message text,
	created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sms_verification_events_user_sent_at
	ON admin.sms_verification_events (user_id, sent_at DESC);

CREATE INDEX IF NOT EXISTS idx_sms_verification_events_phone_sent_at
	ON admin.sms_verification_events (phone_number, sent_at DESC);

ALTER TABLE admin.sms_verification_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sms_verification_events_select_own"
	ON admin.sms_verification_events FOR SELECT
	USING (auth.uid() = user_id);

CREATE POLICY "sms_verification_events_insert_own"
	ON admin.sms_verification_events FOR INSERT
	WITH CHECK (auth.uid() = user_id);

-- Atomic check for cooldown + hourly quota.
CREATE OR REPLACE FUNCTION app.phone_verification_send_allowed()
RETURNS TABLE (
	can_send boolean,
	cooldown_remaining_seconds integer,
	sends_in_last_hour integer
)
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
	v_user_id uuid;
	v_last_time_sent timestamptz;
	v_sends_in_last_hour integer;
	v_cooldown_remaining integer := 0;
BEGIN
	v_user_id := auth.uid();
	IF v_user_id IS NULL THEN
		RAISE EXCEPTION 'Not authenticated';
	END IF;

	SELECT p.last_time_sent
	INTO v_last_time_sent
	FROM app.profiles p
	WHERE p.id = v_user_id;

	SELECT COUNT(*)::integer
	INTO v_sends_in_last_hour
	FROM admin.sms_verification_events e
	WHERE e.user_id = v_user_id
		AND e.status = 'sent'
		AND e.sent_at >= now() - interval '1 hour';

	IF v_last_time_sent IS NOT NULL AND v_last_time_sent > now() - interval '30 seconds' THEN
		v_cooldown_remaining := GREATEST(0, CEIL(EXTRACT(EPOCH FROM (v_last_time_sent + interval '30 seconds' - now())))::integer);
	END IF;

	can_send := v_cooldown_remaining = 0 AND v_sends_in_last_hour < 3;
	cooldown_remaining_seconds := v_cooldown_remaining;
	sends_in_last_hour := v_sends_in_last_hour;
	RETURN NEXT;
END;
$$;

-- Update last send timestamp and append provider event
CREATE OR REPLACE FUNCTION app.log_phone_verification_event(
	p_phone_number text,
	p_status text,
	p_provider_message_id text DEFAULT NULL,
	p_error_message text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
	v_user_id uuid;
BEGIN
	v_user_id := auth.uid();
	IF v_user_id IS NULL THEN
		RAISE EXCEPTION 'Not authenticated';
	END IF;

	IF p_status NOT IN ('sent', 'failed') THEN
		RAISE EXCEPTION 'Invalid status for phone verification event';
	END IF;

	UPDATE app.profiles
	SET last_time_sent = now(),
		phone_number = p_phone_number,
		phone_verified = false,
		phone_verified_at = NULL
	WHERE id = v_user_id;

	INSERT INTO admin.sms_verification_events (
		user_id,
		phone_number,
		status,
		provider_message_id,
		error_message
	)
	VALUES (
		v_user_id,
		p_phone_number,
		p_status,
		p_provider_message_id,
		p_error_message
	);
END;
$$;

GRANT EXECUTE ON FUNCTION app.phone_verification_send_allowed() TO authenticated;
GRANT EXECUTE ON FUNCTION app.log_phone_verification_event(text, text, text, text) TO authenticated;
GRANT SELECT, INSERT ON admin.sms_verification_events TO authenticated;
