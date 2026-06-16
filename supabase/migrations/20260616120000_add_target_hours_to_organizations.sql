ALTER TABLE admin.organizations
	ADD COLUMN target_hours NUMERIC(5,2);

COMMENT ON COLUMN admin.organizations.target_hours IS
	'Target working hours for the organization (e.g. 8.0 per day).';
