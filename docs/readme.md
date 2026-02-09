# Time2Log – DB Repository (Supabase)

#### Dieses Repository ist die einzige Quelle der Wahrheit für das Datenbankschema von Time2Log.
#### Alle Änderungen an der Datenbank erfolgen ausschließlich über SQL-Migrations in diesem Repo!

⸻

## Migrations

Neue Migration erstellen
```
supabase migration new <name>
```

Regeln für Migrations
•	Migrationen sind forward-only (keine Down-Migrations)
•	Bereits gemergte Migrations niemals ändern
•	Jede Schema-Änderung = neue Migration
•	Keine manuellen Änderungen im Supabase UI

⸻

## Deployment / Upgrade

#### DEV
•	Trigger: Merge auf main <br>
•	Aktion: supabase db push <br>
•	Ziel: DEV Supabase Projekt <br>

DEV ist immer der neueste Stand.

⸻

#### PRD
•	Trigger: Git Tag db-vX.Y.Z <br>
•	Manual Approval (GitHub Environment) <br>
•	Aktion: supabase db push <br>
•	Ziel: PRD Supabase Projekt <br>

⸻

Rollback
•	Kein direktes DB-Rollback
•	Fehler werden durch neue Migration korrigiert

⸻

Verantwortlichkeiten
•	Dieses Repo ist shared zwischen Admin- und User-Team
•	Änderungen am gemeinsamen Schema erfordern Review