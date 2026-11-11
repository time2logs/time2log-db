ALTER FUNCTION admin.rollover_semester(uuid) SET search_path = '';

REVOKE EXECUTE ON FUNCTION admin.rollover_semester(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION admin.rollover_semester(uuid) TO service_role;
