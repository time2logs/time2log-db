-- Enddatum des aktuellen Semesters pro Organisation
ALTER TABLE admin.organizations
    ADD COLUMN semester_end_date date;

-- Rollover: für alle Member der Org current_semester +1 (max. 8), dann Datum leeren
CREATE OR REPLACE FUNCTION admin.rollover_semester(p_org_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $body$
BEGIN
    UPDATE app.profiles p
    SET current_semester = ((p.current_semester::text)::int + 1)::text::app.semester_type
    FROM admin.organization_members m
    WHERE m.user_id = p.id
        AND m.organization_id = p_org_id
        AND p.current_semester IS NOT NULL
        AND p.current_semester <> '8';   -- 8. Semester überspringen

    UPDATE admin.organizations
    SET semester_end_date = NULL
    WHERE id = p_org_id;
END;
$body$;