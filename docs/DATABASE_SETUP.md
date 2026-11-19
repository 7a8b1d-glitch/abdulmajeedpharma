# Abdulmajeedpharma (APH) — Database Setup

**Project Owner:** Dr. Abdulmajeed Abdullah Almakhedhi  
**Phase:** Phase 02 — Database Foundation  
**Target:** Supabase PostgreSQL

## Prerequisites

- A PostgreSQL database (Supabase PostgreSQL recommended).
- `psql` client or a PostgreSQL-compatible SQL runner.
- Backend Python environment (`backend/.venv`) with dependencies installed.

No real database was available in the Phase 02 environment. These
instructions are for when a database is provisioned.

## Environment Variables

Copy `.env.example` to `.env` and fill in placeholder values:

```bash
cp .env.example .env
```

Required variables (placeholders only — never real credentials):

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string (`postgresql+asyncpg://...`) |
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_PUBLIC_KEY` | Supabase public anon key (client-safe) |
| `SUPABASE_SERVICE_KEY` | Supabase service-role key (backend-only, never commit) |
| `JWT_SECRET` | JWT signing secret (min 32 chars) |

## Applying Migrations

Migrations are plain SQL files under `database/migrations/`. Apply them in
order (001 → 011):

```bash
# Using psql (example; adjust connection string as needed)
psql "$DATABASE_URL" -f database/migrations/001_extensions_and_helpers.sql
psql "$DATABASE_URL" -f database/migrations/002_geography_and_classification.sql
# ... continue through 011_seed_reference_data.sql
```

Or apply all at once:

```bash
cat database/migrations/*.sql | psql "$DATABASE_URL"
```

Migrations use `CREATE EXTENSION IF NOT EXISTS`, `CREATE TABLE IF NOT EXISTS`
patterns where applicable, and `ON CONFLICT DO NOTHING` for seed data, making
them safe to re-run.

## Required Extensions

| Extension | Purpose |
|-----------|---------|
| `pgcrypto` | `gen_random_uuid()` for UUID primary keys |
| `pg_trgm` | Trigram indexes for fuzzy search on names |

In Supabase, enable these via the SQL Editor or the Extensions page in the
dashboard.

## Supabase-Specific Notes

- Supabase Auth manages `auth.users`. Do not create a separate users table;
  `public.user_profiles.user_id` references `auth.users(id)`.
- RLS policies reference `auth.uid()` which is provided by Supabase Auth.
- The `aph_current_user_role()` helper function is `SECURITY DEFINER` and
  should be owned by the `postgres`/`supabase_admin` role.
- Storage buckets for product images and message attachments must be created
  separately in the Supabase dashboard.

## Backend Configuration

The FastAPI backend reads `DATABASE_URL` from `.env` via Pydantic Settings
(`backend/app/core/config.py`). SQLAlchemy models use async PostgreSQL
access (`asyncpg` driver).

To verify backend models import correctly:

```bash
cd backend
source .venv/bin/activate
python3 -c "from app.models import Base; print(len(Base.metadata.tables), 'tables')"
```

## Running Tests

```bash
cd backend
source .venv/bin/activate
python3 -m pytest tests/
```

Tests are static (no live database required) and validate:
- Migration file existence
- Table/column/foreign key/unique/check constraint definitions
- RLS enablement and policy presence
- Seed data (18 body systems, Yemen country)
- SQLAlchemy model/migration consistency

## Arabic Search Limitations

PostgreSQL full-text search uses the `simple` configuration. Arabic stemming
is not natively optimal without external dictionaries. `pg_trgm` trigram
indexes provide approximate matching but are not a complete Arabic search
solution. This is a known limitation to be addressed in a future phase.

## Troubleshooting

| Issue | Resolution |
|-------|------------|
| `gen_random_uuid()` not found | Enable `pgcrypto` extension (migration 001) |
| `auth.uid()` is null | Ensure the request is authenticated via Supabase Auth |
| RLS policy blocks access | Verify the user has a row in `user_profiles` with a valid role |
| Migration fails on re-run | Migrations are idempotent; check for partially applied state |
