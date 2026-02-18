CREATE OR REPLACE FUNCTION admin._upsert_curriculum_nodes(
    p_org_id uuid,
    p_prof_id uuid,
    p_parent_id uuid,
    p_nodes jsonb
) RETURNS void AS $$
DECLARE
    v_node jsonb;
    v_node_id uuid;
    v_sort int := 0;
    v_comp_code text;
    v_comp_id uuid;
BEGIN
    FOR v_node IN SELECT * FROM jsonb_array_elements(p_nodes)
    LOOP
        INSERT INTO app.curriculum_nodes (
            organization_id, profession_id, parent_id, node_type,
            key, label, description, sort_order, is_active
        ) VALUES (
            p_org_id,
            p_prof_id,
            p_parent_id,
            (v_node ->> 'type')::app.curriculum_node_type,
            v_node ->> 'key',
            v_node ->> 'label',
            v_node ->> 'description',
            v_sort,
            true
        )
        ON CONFLICT (organization_id, profession_id, key)
        DO UPDATE SET
            parent_id = EXCLUDED.parent_id,
            node_type = EXCLUDED.node_type,
            label = EXCLUDED.label,
            description = EXCLUDED.description,
            sort_order = EXCLUDED.sort_order,
            is_active = true,
            updated_at = now()
        RETURNING id INTO v_node_id;

        -- Kompetenz-Verknüpfungen für diesen Knoten
        IF v_node ? 'competencies' THEN
            FOR v_comp_code IN SELECT * FROM jsonb_array_elements_text(v_node -> 'competencies')
            LOOP
                SELECT id INTO v_comp_id
                FROM app.competencies
                WHERE organization_id = p_org_id
                  AND profession_id = p_prof_id
                  AND code = v_comp_code;

                IF v_comp_id IS NOT NULL THEN
                    INSERT INTO app.curriculum_node_competencies (curriculum_node_id, competency_id)
                    VALUES (v_node_id, v_comp_id)
                    ON CONFLICT DO NOTHING;
                END IF;
            END LOOP;
        END IF;

        -- Kinder rekursiv verarbeiten
        IF v_node ? 'children' THEN
            PERFORM admin._upsert_curriculum_nodes(
                p_org_id, p_prof_id, v_node_id, v_node -> 'children'
            );
        END IF;

        v_sort := v_sort + 1;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = '';

-- Aufruf via PostgREST: POST /rest/v1/rpc/apply_curriculum_import { "import_id": "..." }
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

        -- 5) Import als angewendet markieren
        UPDATE admin.curriculum_imports
        SET status = 'applied'
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

-- Berechtigung: nur authenticated darf die RPC aufrufen (Autorisierung prüft die Funktion selbst)
GRANT EXECUTE ON FUNCTION admin.apply_curriculum_import(uuid) TO authenticated;
