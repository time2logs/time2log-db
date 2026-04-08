CREATE TYPE app.semester_type AS ENUM ('1', '2', '3', '4', '5', '6', '7', '8');

ALTER TABLE app.profiles
    ADD COLUMN current_semester app.semester_type;

ALTER TABLE admin.invites
    ADD COLUMN current_semester app.semester_type;

ALTER TABLE app.activity_records
    ADD COLUMN current_semester app.semester_type;

CREATE OR REPLACE FUNCTION app.sync_activity_semester()
RETURNS TRIGGER AS $$
BEGIN

SELECT current_semester INTO NEW.current_semester
FROM app.profiles
WHERE id = NEW.user_id;

RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_insert_sync_semester
    BEFORE INSERT ON app.activity_records
    FOR EACH ROW
    EXECUTE FUNCTION app.sync_activity_semester();