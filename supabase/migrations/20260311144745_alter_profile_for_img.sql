ALTER TABLE app.profiles
DROP COLUMN IF EXISTS avatar_url;

ALTER TABLE app.profiles
add COLUMN avatar_url text;
