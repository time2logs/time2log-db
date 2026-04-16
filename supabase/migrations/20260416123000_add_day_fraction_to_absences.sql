ALTER TABLE app.absences
	ADD COLUMN day_fraction NUMERIC(3,2) NOT NULL DEFAULT 1.00;

ALTER TABLE app.absences
	ADD CONSTRAINT absences_day_fraction_check
	CHECK (day_fraction > 0 AND day_fraction <= 1);

COMMENT ON COLUMN app.absences.day_fraction IS
	'Fraction of each affected day that is absent. 1.00 = full day, 0.50 = half day, 0.20 = one fifth of a day.';
