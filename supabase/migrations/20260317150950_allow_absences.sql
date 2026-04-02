ALTER TABLE app.activity_records
ADD COLUMN is_absent BOOLEAN NOT NULL DEFAULT FALSE;
   
 -- 2. Modify the curriculum_activity_id column to allow NULL values
ALTER TABLE app.activity_records
ALTER COLUMN curriculum_activity_id DROP NOT NULL;
