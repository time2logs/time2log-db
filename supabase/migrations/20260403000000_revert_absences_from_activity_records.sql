-- Revert: Remove is_absent from activity_records and restore original constraints

-- 0. Delete records with NULL curriculum_activity_id (these are leftover absence records)
DELETE FROM app.activity_records WHERE curriculum_activity_id IS NULL;

-- 1. Remove the is_absent column
ALTER TABLE app.activity_records DROP COLUMN IF EXISTS is_absent;

-- 2. Restore curriculum_activity_id to NOT NULL
ALTER TABLE app.activity_records ALTER COLUMN curriculum_activity_id SET NOT NULL;

-- 3. Restore hours to NOT NULL with original check constraint
ALTER TABLE app.activity_records ALTER COLUMN hours SET NOT NULL;

-- 4. Drop the current check constraint
ALTER TABLE app.activity_records DROP CONSTRAINT IF EXISTS activity_records_hours_check;

-- 5. Add back the original check constraint for hours
ALTER TABLE app.activity_records ADD CONSTRAINT activity_records_hours_check CHECK (hours > 0 AND hours <= 24);
