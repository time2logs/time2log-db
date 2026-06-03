-- Moderator-Rolle: Schritt 1 von 2.
-- Postgres erlaubt nicht, einen frisch hinzugefuegten Enum-Wert in derselben
-- Transaktion/Migration zu verwenden. Daher wird der Enum-Wert hier isoliert
-- ergaenzt; Helper und Policies folgen in der naechsten Migration.

ALTER TYPE app.user_role ADD VALUE IF NOT EXISTS 'moderator';
