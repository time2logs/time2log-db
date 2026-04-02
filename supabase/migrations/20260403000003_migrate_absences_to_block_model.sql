-- Migrate absences table from single-day model to block/rule model
-- This migration transitions from entry_date to start_date/end_date with rrule support

-- Step 1: Add new columns (nullable first for migration)
ALTER TABLE app.absences
    ADD COLUMN start_date DATE,
    ADD COLUMN end_date DATE,
    ADD COLUMN rrule TEXT;

-- Step 2: Migrate existing data
-- Map entry_date to both start_date and end_date for existing single-day records
UPDATE app.absences
SET 
    start_date = entry_date,
    end_date = entry_date;

-- Step 3: Make new columns NOT NULL after data migration
ALTER TABLE app.absences
    ALTER COLUMN start_date SET NOT NULL,
    ALTER COLUMN end_date SET NOT NULL;

-- Step 4: Drop old unique constraint
ALTER TABLE app.absences
    DROP CONSTRAINT absences_user_id_entry_date_key;

-- Step 5: Add new unique constraint
-- Prevent duplicate absence blocks for same user with same start/end dates
ALTER TABLE app.absences
    ADD CONSTRAINT absences_user_id_start_date_end_date_key
    UNIQUE (user_id, start_date, end_date);

-- Step 6: Add check constraint to ensure end_date >= start_date
ALTER TABLE app.absences
    ADD CONSTRAINT absences_date_range_check
    CHECK (end_date >= start_date);

-- Step 7: Drop old indexes
DROP INDEX IF EXISTS app.idx_absences_user_date;
DROP INDEX IF EXISTS app.idx_absences_org_date;

-- Step 8: Create new indexes for the new columns
CREATE INDEX idx_absences_user_date_range ON app.absences (user_id, start_date DESC, end_date DESC);
CREATE INDEX idx_absences_org_date_range ON app.absences (organization_id, start_date DESC, end_date DESC);
CREATE INDEX idx_absences_recurring ON app.absences (is_recurring) WHERE is_recurring = TRUE;

-- Step 9: Drop old columns
ALTER TABLE app.absences
    DROP COLUMN entry_date,
    DROP COLUMN recurrence_pattern;

-- Add comment to document rrule format
COMMENT ON COLUMN app.absences.rrule IS 'iCalendar recurrence rule string (e.g., FREQ=WEEKLY;BYDAY=MO;INTERVAL=1)';
