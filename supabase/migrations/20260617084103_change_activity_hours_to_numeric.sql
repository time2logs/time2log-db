-- Change activity_records.hours from int to numeric so fractional hours
-- (i.e. minutes, e.g. 8.5 = 8h30m) can be recorded.

-- 1. Drop the existing integer check constraint
ALTER TABLE app.activity_records DROP CONSTRAINT IF EXISTS activity_records_hours_check;

-- 2. Change the column type to numeric(4,2) (e.g. 8.25, 8.50, 0.25)
ALTER TABLE app.activity_records
  ALTER COLUMN hours TYPE numeric(4,2) USING hours::numeric(4,2);

-- 3. Re-add the range check (still > 0 and <= 24, now allowing fractions)
ALTER TABLE app.activity_records
  ADD CONSTRAINT activity_records_hours_check CHECK (hours > 0 AND hours <= 24);
