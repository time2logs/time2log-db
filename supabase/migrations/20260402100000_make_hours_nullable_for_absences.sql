-- Allow hours to be NULL for absence records
ALTER TABLE app.activity_records
  ALTER COLUMN hours DROP NOT NULL;

-- Update check: hours must be a valid integer when provided (non-absence records)
ALTER TABLE app.activity_records
  DROP CONSTRAINT IF EXISTS activity_records_hours_check;

ALTER TABLE app.activity_records
  ADD CONSTRAINT activity_records_hours_check
  CHECK (
    (is_absent = true AND hours IS NULL)
    OR (is_absent = false AND hours IS NOT NULL AND hours > 0 AND hours <= 24)
  );
