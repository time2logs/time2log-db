CREATE TYPE app.curriculum_node_type AS ENUM ('category', 'activity');

CREATE TABLE app.competencies (
    id uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES admin.organizations(id) ON DELETE CASCADE,
    profession_id uuid NOT NULL REFERENCES admin.professions(id) ON DELETE CASCADE,
    code text NOT NULL,
    description text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    UNIQUE (organization_id, profession_id, code)
);

CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON app.competencies
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- Curriculum-Nodes: Architecture for dynamic structure
CREATE TABLE app.curriculum_nodes (
    id uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES admin.organizations(id) ON DELETE CASCADE,
    profession_id uuid NOT NULL REFERENCES admin.professions(id) ON DELETE CASCADE,
    parent_id uuid REFERENCES app.curriculum_nodes(id) ON DELETE CASCADE,
    node_type app.curriculum_node_type NOT NULL,
    key text NOT NULL,
    label text NOT NULL,
    description text,
    sort_order int NOT NULL DEFAULT 0,
    meta jsonb,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    UNIQUE (organization_id, profession_id, key)
);

CREATE INDEX idx_curriculum_nodes_tree
    ON app.curriculum_nodes (organization_id, profession_id, parent_id, sort_order);

CREATE INDEX idx_curriculum_nodes_type
    ON app.curriculum_nodes (organization_id, profession_id, node_type);

CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON app.curriculum_nodes
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE app.curriculum_node_competencies (
    curriculum_node_id uuid NOT NULL REFERENCES app.curriculum_nodes(id) ON DELETE CASCADE,
    competency_id uuid NOT NULL REFERENCES app.competencies(id) ON DELETE CASCADE,
    PRIMARY KEY (curriculum_node_id, competency_id)
);

CREATE INDEX idx_node_competencies_competency
    ON app.curriculum_node_competencies (competency_id);

-- RLS: app.competencies
-- ===========================================================================
ALTER TABLE app.competencies ENABLE ROW LEVEL SECURITY;

CREATE POLICY "competencies_select_member"
    ON app.competencies FOR SELECT
    USING (admin.is_member_of(organization_id));

CREATE POLICY "competencies_insert_admin"
    ON app.competencies FOR INSERT
    WITH CHECK (admin.is_admin_of(organization_id));

CREATE POLICY "competencies_update_admin"
    ON app.competencies FOR UPDATE
    USING (admin.is_admin_of(organization_id))
    WITH CHECK (admin.is_admin_of(organization_id));

CREATE POLICY "competencies_delete_admin"
    ON app.competencies FOR DELETE
    USING (admin.is_admin_of(organization_id));

-- RLS: app.curriculum_nodes
-- ===========================================================================
ALTER TABLE app.curriculum_nodes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "curriculum_nodes_select_member"
    ON app.curriculum_nodes FOR SELECT
    USING (admin.is_member_of(organization_id));

CREATE POLICY "curriculum_nodes_insert_admin"
    ON app.curriculum_nodes FOR INSERT
    WITH CHECK (admin.is_admin_of(organization_id));

CREATE POLICY "curriculum_nodes_update_admin"
    ON app.curriculum_nodes FOR UPDATE
    USING (admin.is_admin_of(organization_id))
    WITH CHECK (admin.is_admin_of(organization_id));

CREATE POLICY "curriculum_nodes_delete_admin"
    ON app.curriculum_nodes FOR DELETE
    USING (admin.is_admin_of(organization_id));

-- RLS: app.curriculum_node_competencies
-- ===========================================================================
ALTER TABLE app.curriculum_node_competencies ENABLE ROW LEVEL SECURITY;

-- Lesen: wenn User den Curriculum-Knoten sehen darf
CREATE POLICY "node_competencies_select_member"
    ON app.curriculum_node_competencies FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM app.curriculum_nodes cn
            WHERE cn.id = curriculum_node_id
              AND admin.is_member_of(cn.organization_id)
        )
    );

CREATE POLICY "node_competencies_insert_admin"
    ON app.curriculum_node_competencies FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM app.curriculum_nodes cn
            WHERE cn.id = curriculum_node_id
              AND admin.is_admin_of(cn.organization_id)
        )
    );

CREATE POLICY "node_competencies_delete_admin"
    ON app.curriculum_node_competencies FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM app.curriculum_nodes cn
            WHERE cn.id = curriculum_node_id
              AND admin.is_admin_of(cn.organization_id)
        )
    );
