-- Bildungsplan-Aktivierung: erlaubt das Auswählen, welcher hochgeladene Import
-- auf App-Seite aktiv ist (statt implizit "der neueste").
--
-- Änderungen:
--   1) apply_curriculum_import demoviert beim Anwenden den zuvor aktiven Import
--      des Berufs auf status 'superseded'. Dadurch hat pro Beruf immer genau
--      EIN Import status 'applied' = der aktive Plan.
--   2) Ein 'superseded' Import kann später erneut angewendet ("aktiviert") werden,
--      da die bestehende Guard nur status 'applied' blockt.
--   3) Einmaliges Daten-Cleanup für Berufe mit mehreren 'applied' Importen:
--      nur der zuletzt erstellte bleibt aktiv, ältere werden 'superseded'.

-- ===========================================================================
-- 1) Daten-Cleanup: pro (org, profession) nur den neuesten 'applied' behalten
-- ===========================================================================
UPDATE admin.curriculum_imports ci
SET status = 'superseded'
WHERE ci.status = 'applied'
  AND ci.id <> (
      SELECT inner_ci.id
      FROM admin.curriculum_imports inner_ci
      WHERE inner_ci.organization_id = ci.organization_id
        AND inner_ci.profession_id = ci.profession_id
        AND inner_ci.status = 'applied'
      ORDER BY inner_ci.created_at DESC
      LIMIT 1
  );

-- ===========================================================================
-- 2) RPC neu definieren: mit Demotion des bisher aktiven Imports
-- ===========================================================================
CREATE OR REPLACE FUNCTION admin.apply_curriculum_import(import_id uuid)
RETURNS void AS $$
DECLARE
    v_import record;
    v_org_id uuid;
    v_prof_id uuid;
    v_payload jsonb;
    v_comp jsonb;
BEGIN
    -- Import laden
    SELECT * INTO v_import
    FROM admin.curriculum_imports
    WHERE id = import_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Import not found: %', import_id;
    END IF;

    -- Bereits aktiver Import muss nicht erneut angewendet werden
    IF v_import.status = 'applied' THEN
        RAISE EXCEPTION 'Import already applied: %', import_id;
    END IF;

    -- Berechtigung prüfen
    IF NOT admin.is_admin_of(v_import.organization_id) THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;

    v_org_id := v_import.organization_id;
    v_prof_id := v_import.profession_id;
    v_payload := v_import.payload;

    -- Impliziter Savepoint: bei Fehler werden alle Änderungen im BEGIN-Block
    -- zurückgerollt, der EXCEPTION-Handler setzt den Status auf 'failed'
    BEGIN
        -- 1) Kompetenzen upserten
        FOR v_comp IN SELECT * FROM jsonb_array_elements(v_payload -> 'competencies')
        LOOP
            INSERT INTO app.competencies (organization_id, profession_id, code, description)
            VALUES (v_org_id, v_prof_id, v_comp ->> 'code', v_comp ->> 'description')
            ON CONFLICT (organization_id, profession_id, code)
            DO UPDATE SET
                description = EXCLUDED.description,
                updated_at = now();
        END LOOP;

        -- 2) Bestehende Knoten deaktivieren (nicht löschen, da activity_records referenzieren)
        UPDATE app.curriculum_nodes
        SET is_active = false, updated_at = now()
        WHERE organization_id = v_org_id
          AND profession_id = v_prof_id;

        -- 3) Bestehende Kompetenz-Verknüpfungen entfernen (werden neu aufgebaut)
        DELETE FROM app.curriculum_node_competencies
        WHERE curriculum_node_id IN (
            SELECT id FROM app.curriculum_nodes
            WHERE organization_id = v_org_id
              AND profession_id = v_prof_id
        );

        -- 4) Knoten rekursiv upserten + Verknüpfungen erstellen
        PERFORM admin._upsert_curriculum_nodes(
            v_org_id, v_prof_id, NULL, v_payload -> 'nodes'
        );

        -- 5) Zuvor aktiven Import des Berufs demovieren, damit pro Beruf genau
        --    EIN Import status 'applied' hat (= der aktive Plan)
        UPDATE admin.curriculum_imports
        SET status = 'superseded'
        WHERE organization_id = v_org_id
          AND profession_id = v_prof_id
          AND status = 'applied'
          AND id <> import_id;

        -- 6) Diesen Import als angewendet markieren (Fehler eines früheren
        --    Versuchs zurücksetzen)
        UPDATE admin.curriculum_imports
        SET status = 'applied', error = NULL
        WHERE id = import_id;

    EXCEPTION WHEN OTHERS THEN
        -- Savepoint wird zurückgerollt, nur der Status update bleibt
        UPDATE admin.curriculum_imports
        SET status = 'failed', error = SQLERRM
        WHERE id = import_id;
    END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = '';

GRANT EXECUTE ON FUNCTION admin.apply_curriculum_import(uuid) TO authenticated;
