# Abdulmajeedpharma — Database

PostgreSQL cloud database, migrations, and seeds.

## Structure

```
database/
├── migrations/     # Alembic / SQL migrations
├── seeds/          # Reference data seeds (no real drug data)
└── README.md
```

## Notes

- Cloud PostgreSQL (e.g., Supabase Postgres).
- Connection via `DATABASE_URL` (see `.env.example`).
- No real drug or patient data is stored in this repository.
