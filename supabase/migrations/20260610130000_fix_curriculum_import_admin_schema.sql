-- Fix: Die vorherige Migration (20260610120000) hat apply_curriculum_import
-- versehentlich auf das alte 'app'-Schema zurückgesetzt (app.competencies,
-- app.curriculum_nodes, ...). Diese Tabellen wurden jedoch in
-- 20260407062943_migrate_curriculum_to_admin.sql ins 'admin'-Schema verschoben.
--
-- Hier wird die RPC mit den korrekten 'admin'-Referenzen neu definiert und
-- behält die Aktivierungs-Logik (Demotion des zuvor aktiven Imports) bei.

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
            INSERT INTO admin.competencies (organization_id, profession_id, code, description)
            VALUES (v_org_id, v_prof_id, v_comp ->> 'code', v_comp ->> 'description')
            ON CONFLICT (organization_id, profession_id, code)
            DO UPDATE SET
                description = EXCLUDED.description,
                updated_at = now();
        END LOOP;

        -- 2) Bestehende Knoten deaktivieren (nicht löschen, da activity_records referenzieren)
        UPDATE admin.curriculum_nodes
        SET is_active = false, updated_at = now()
        WHERE organization_id = v_org_id
          AND profession_id = v_prof_id;

        -- 3) Bestehende Kompetenz-Verknüpfungen entfernen (werden neu aufgebaut)
        DELETE FROM admin.curriculum_node_competencies
        WHERE curriculum_node_id IN (
            SELECT id FROM admin.curriculum_nodes
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
