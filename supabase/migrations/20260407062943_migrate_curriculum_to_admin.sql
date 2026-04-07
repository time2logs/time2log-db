-- Move only the curriculum tables from app to admin.
-- Keep dependent functions, policies, and FKs aligned with the new schema.

ALTER TABLE app.curriculum_node_competencies SET SCHEMA admin;
ALTER TABLE app.curriculum_nodes SET SCHEMA admin;
ALTER TABLE app.competencies SET SCHEMA admin;

ALTER TABLE app.activity_records
    DROP CONSTRAINT IF EXISTS activity_records_curriculum_activity_id_fkey;

ALTER TABLE app.activity_records
    ADD CONSTRAINT activity_records_curriculum_activity_id_fkey
    FOREIGN KEY (curriculum_activity_id)
    REFERENCES admin.curriculum_nodes(id)
    ON DELETE RESTRICT;

DROP POLICY IF EXISTS "node_competencies_select_member" ON admin.curriculum_node_competencies;
DROP POLICY IF EXISTS "node_competencies_insert_admin" ON admin.curriculum_node_competencies;
DROP POLICY IF EXISTS "node_competencies_delete_admin" ON admin.curriculum_node_competencies;

CREATE POLICY "node_competencies_select_member"
    ON admin.curriculum_node_competencies FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM admin.curriculum_nodes cn
            WHERE cn.id = curriculum_node_id
              AND admin.is_member_of(cn.organization_id)
        )
    );

CREATE POLICY "node_competencies_insert_admin"
    ON admin.curriculum_node_competencies FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM admin.curriculum_nodes cn
            WHERE cn.id = curriculum_node_id
              AND admin.is_admin_of(cn.organization_id)
        )
    );

CREATE POLICY "node_competencies_delete_admin"
    ON admin.curriculum_node_competencies FOR DELETE
    USING (
        EXISTS (
            SELECT 1
            FROM admin.curriculum_nodes cn
            WHERE cn.id = curriculum_node_id
              AND admin.is_admin_of(cn.organization_id)
        )
    );

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
        INSERT INTO admin.curriculum_nodes (
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

        IF v_node ? 'competencies' THEN
            FOR v_comp_code IN SELECT * FROM jsonb_array_elements_text(v_node -> 'competencies')
            LOOP
                SELECT id INTO v_comp_id
                FROM admin.competencies
                WHERE organization_id = p_org_id
                  AND profession_id = p_prof_id
                  AND code = v_comp_code;

                IF v_comp_id IS NOT NULL THEN
                    INSERT INTO admin.curriculum_node_competencies (curriculum_node_id, competency_id)
                    VALUES (v_node_id, v_comp_id)
                    ON CONFLICT DO NOTHING;
                END IF;
            END LOOP;
        END IF;

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

CREATE OR REPLACE FUNCTION admin.apply_curriculum_import(import_id uuid)
RETURNS void AS $$
DECLARE
    v_import record;
    v_org_id uuid;
    v_prof_id uuid;
    v_payload jsonb;
    v_comp jsonb;
BEGIN
    SELECT * INTO v_import
    FROM admin.curriculum_imports
    WHERE id = import_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Import not found: %', import_id;
    END IF;

    IF v_import.status = 'applied' THEN
        RAISE EXCEPTION 'Import already applied: %', import_id;
    END IF;

    IF NOT admin.is_admin_of(v_import.organization_id) THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;

    v_org_id := v_import.organization_id;
    v_prof_id := v_import.profession_id;
    v_payload := v_import.payload;

    BEGIN
        FOR v_comp IN SELECT * FROM jsonb_array_elements(v_payload -> 'competencies')
        LOOP
            INSERT INTO admin.competencies (organization_id, profession_id, code, description)
            VALUES (v_org_id, v_prof_id, v_comp ->> 'code', v_comp ->> 'description')
            ON CONFLICT (organization_id, profession_id, code)
            DO UPDATE SET
                description = EXCLUDED.description,
                updated_at = now();
        END LOOP;

        UPDATE admin.curriculum_nodes
        SET is_active = false, updated_at = now()
        WHERE organization_id = v_org_id
          AND profession_id = v_prof_id;

        DELETE FROM admin.curriculum_node_competencies
        WHERE curriculum_node_id IN (
            SELECT id FROM admin.curriculum_nodes
            WHERE organization_id = v_org_id
              AND profession_id = v_prof_id
        );

        PERFORM admin._upsert_curriculum_nodes(
            v_org_id, v_prof_id, NULL, v_payload -> 'nodes'
        );

        UPDATE admin.curriculum_imports
        SET status = 'applied'
        WHERE id = import_id;

    EXCEPTION WHEN OTHERS THEN
        UPDATE admin.curriculum_imports
        SET status = 'failed', error = SQLERRM
        WHERE id = import_id;
    END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = '';

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE admin.competencies TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE admin.curriculum_nodes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE admin.curriculum_node_competencies TO authenticated;
