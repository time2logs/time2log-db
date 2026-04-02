-- Create absence_types enum table
CREATE TABLE app.absence_types (
    id TEXT NOT NULL PRIMARY KEY,
    label_key TEXT NOT NULL,
    is_recurring_allowed BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed default absence types
INSERT INTO app.absence_types (id, label_key, is_recurring_allowed, sort_order) VALUES
    ('sick', 'absence_type_sick', FALSE, 1),
    ('vacation', 'absence_type_vacation', FALSE, 2),
    ('military', 'absence_type_military', TRUE, 3),
    ('uk', 'absence_type_uk', TRUE, 4),
    ('berufsschule', 'absence_type_berufsschule', TRUE, 5),
    ('custom', 'absence_type_custom', FALSE, 6);

-- RLS for absence_types (read-only for users, only admins can modify)
ALTER TABLE app.absence_types ENABLE ROW LEVEL SECURITY;

CREATE POLICY "absence_types_select" ON app.absence_types FOR SELECT USING (TRUE);

-- Note: Insert/Update/Delete for absence_types should be done by admin only
-- This can be handled through a separate admin policy or function
