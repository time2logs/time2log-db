-- Saved workplaces (Arbeitsplatz) per user; used by settings + dashboard.

CREATE TABLE app.user_locations (
	id uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
	user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
	location text NOT NULL CHECK (length(trim(location)) > 0),
	is_default boolean NOT NULL DEFAULT false,
	created_at timestamp with time zone NOT NULL DEFAULT now(),
	UNIQUE (user_id, location)
);

CREATE INDEX idx_user_locations_user_created
	ON app.user_locations (user_id, created_at DESC);

ALTER TABLE app.user_locations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_locations_select_own"
	ON app.user_locations FOR SELECT
	USING (auth.uid() = user_id);

CREATE POLICY "user_locations_insert_own"
	ON app.user_locations FOR INSERT
	WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_locations_update_own"
	ON app.user_locations FOR UPDATE
	USING (auth.uid() = user_id)
	WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_locations_delete_own"
	ON app.user_locations FOR DELETE
	USING (auth.uid() = user_id);