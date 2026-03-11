ALTER TABLE app.activity_records 
ADD COLUMN location text;

COMMENT ON COLUMN app.activity_records.location IS 'Ort oder Stockwerk';
