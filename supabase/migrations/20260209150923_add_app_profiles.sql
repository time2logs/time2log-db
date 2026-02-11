CREATE SCHEMA app;

CREATE TYPE app.user_role AS ENUM ('user', 'admin');

CREATE TABLE app.profiles (
    id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    first_name text NOT NULL,
    last_name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    PRIMARY KEY (id)
);

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at_profiles
    BEFORE UPDATE ON app.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- RLS
-- =============================================================================
ALTER TABLE app.profiles ENABLE ROW LEVEL SECURITY;

-- User darf eigenes Profil lesen
CREATE POLICY "profiles_select_own"
    ON app.profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "profiles_insert_own"
    ON app.profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_update_own"
    ON app.profiles FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);
-- Delete über ON DELETE CASCADE von auth.users
