-- Report queries used by the admin dashboard.
-- These functions aggregate close to the data and preserve activity_records RLS.

CREATE INDEX IF NOT EXISTS idx_activity_records_org_user_date
    ON app.activity_records (organization_id, user_id, entry_date DESC, created_at DESC);

CREATE OR REPLACE FUNCTION app.get_last_entry_dates(p_organization_id uuid)
RETURNS TABLE (
    user_id uuid,
    last_entry_date timestamptz
)
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path = ''
AS $$
    SELECT DISTINCT ON (ar.user_id)
        ar.user_id,
        ar.created_at AS last_entry_date
    FROM app.activity_records AS ar
    WHERE ar.organization_id = p_organization_id
    ORDER BY ar.user_id, ar.entry_date DESC, ar.created_at DESC;
$$;

REVOKE EXECUTE ON FUNCTION app.get_last_entry_dates(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION app.get_last_entry_dates(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION app.get_dashboard_summary(
    p_organization_id uuid,
    p_user_id uuid DEFAULT NULL,
    p_profession_id uuid DEFAULT NULL,
    p_from date DEFAULT NULL,
    p_to date DEFAULT NULL,
    p_semesters text[] DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path = ''
AS $$
    WITH filtered_records AS (
        SELECT
            ar.curriculum_activity_id,
            ar.hours,
            ar.location,
            ar.rating
        FROM app.activity_records AS ar
        WHERE ar.organization_id = p_organization_id
          AND (p_user_id IS NULL OR ar.user_id = p_user_id)
          AND (p_profession_id IS NULL OR ar.profession_id = p_profession_id)
          AND (
              (
                  coalesce(array_length(p_semesters, 1), 0) > 0
                  AND ar.current_semester::text = ANY (p_semesters)
              )
              OR (
                  coalesce(array_length(p_semesters, 1), 0) = 0
                  AND (p_from IS NULL OR ar.entry_date >= p_from)
                  AND (p_to IS NULL OR ar.entry_date <= p_to)
              )
          )
    ),
    activity_totals AS (
        SELECT
            fr.curriculum_activity_id AS activity_id,
            coalesce(parent.label || ' / ', '') || node.label AS activity_name,
            round(sum(fr.hours), 2) AS total_hours
        FROM filtered_records AS fr
        JOIN admin.curriculum_nodes AS node
          ON node.id = fr.curriculum_activity_id
        LEFT JOIN admin.curriculum_nodes AS parent
          ON parent.id = node.parent_id
        GROUP BY fr.curriculum_activity_id, parent.label, node.label
    ),
    location_totals AS (
        SELECT
            fr.location,
            round(sum(fr.hours), 2) AS total_hours
        FROM filtered_records AS fr
        WHERE fr.location IS NOT NULL
          AND btrim(fr.location) <> ''
        GROUP BY fr.location
    ),
    rating_totals AS (
        SELECT
            fr.curriculum_activity_id AS activity_id,
            coalesce(parent.label || ' / ', '') || node.label AS activity_name,
            round(avg(fr.rating)::numeric, 1) AS average_rating
        FROM filtered_records AS fr
        JOIN admin.curriculum_nodes AS node
          ON node.id = fr.curriculum_activity_id
        LEFT JOIN admin.curriculum_nodes AS parent
          ON parent.id = node.parent_id
        WHERE fr.rating IS NOT NULL
        GROUP BY fr.curriculum_activity_id, parent.label, node.label
    )
    SELECT jsonb_build_object(
        'activities', coalesce((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'activityId', activity_id,
                    'activityName', activity_name,
                    'totalHours', total_hours
                ) ORDER BY total_hours DESC
            )
            FROM activity_totals
        ), '[]'::jsonb),
        'locations', coalesce((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'location', location,
                    'totalHours', total_hours
                ) ORDER BY total_hours DESC
            )
            FROM location_totals
        ), '[]'::jsonb),
        'ratings', coalesce((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'activityId', activity_id,
                    'activityName', activity_name,
                    'averageRating', average_rating
                ) ORDER BY average_rating DESC
            )
            FROM rating_totals
        ), '[]'::jsonb)
    );
$$;

REVOKE EXECUTE ON FUNCTION app.get_dashboard_summary(uuid, uuid, uuid, date, date, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION app.get_dashboard_summary(uuid, uuid, uuid, date, date, text[]) TO authenticated, service_role;
