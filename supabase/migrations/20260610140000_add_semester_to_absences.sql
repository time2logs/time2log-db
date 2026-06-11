-- Semester-Zuordnung für Absenzen, damit Abwesenheiten (wie Aktivitäten) nach
-- Semester gefiltert werden können.
--
-- app.absences hatte bisher keine current_semester-Spalte. Wir spiegeln das
-- bestehende Muster der activity_records: Spalte + Sync-Trigger, der beim Insert
-- das aktuelle Semester aus dem Profil übernimmt (app.sync_activity_semester ist
-- generisch: liest NEW.user_id, setzt NEW.current_semester).

ALTER TABLE app.absences
    ADD COLUMN current_semester app.semester_type;

CREATE TRIGGER tr_insert_sync_semester_absences
    BEFORE INSERT ON app.absences
    FOR EACH ROW
    EXECUTE FUNCTION app.sync_activity_semester();

-- Backfill bestehender Absenzen aus dem Profil (Näherung: aktuelles Semester
-- des Members, da der historische Semesterstand pro Absenz nicht vorliegt).
UPDATE app.absences a
SET current_semester = p.current_semester
FROM app.profiles p
WHERE a.user_id = p.id
  AND a.current_semester IS NULL;
