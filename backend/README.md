# Abdulmajeedpharma — FastAPI Backend

Pharmaceutical platform backend.

## Stack

- FastAPI
- SQLAlchemy (async) + PostgreSQL
- Alembic (listed in requirements.txt; SQL migrations used directly)
- Pydantic v2
- Supabase (auth/storage server-side)
- Redis
- Python 3.11

## Structure

```
backend/
├── app/
│   ├── main.py            # FastAPI entry point
│   ├── core/              # config (Pydantic Settings from .env)
│   ├── api/               # route routers (api_router + v1)
│   ├── models/            # 39 SQLAlchemy models (mirrors database/migrations/)
│   ├── schemas/           # Pydantic schemas
│   ├── services/          # business logic (scaffold)
│   └── repositories/      # data access layer (scaffold)
├── tests/
│   ├── test_placeholder.py
│   └── test_database_schema.py   # 197 static schema validation tests
├── requirements.txt
└── README.md
```

## Database Migrations

Plain SQL migrations under `database/migrations/` (001 → 011):

- 001: Extensions (pgcrypto, pg_trgm) + helper functions
- 002: Geography + classification (countries, body_systems, classes)
- 003: Drug catalog (active_ingredients, drugs, and 10 related tables)
- 004: Companies + market (manufacturers, MAH, suppliers, distributors, brand_products, presentations, markets, registrations)
- 005: Scientific evidence + review workflow
- 006: Users + permissions (user_profiles linked to Supabase auth.users)
- 007: Messaging + notifications
- 008: Imports + audit + sync records
- 009: Indexes + search foundation
- 010: RLS policies + storage policies
- 011: Seed reference data (18 body systems + Yemen country)

## Running

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp ../.env.example .env   # adjust paths as needed; never commit .env
uvicorn app.main:app --reload
```

## Testing

```bash
cd backend
source .venv/bin/activate
python3 -m pytest tests/
```

Tests are static (no live database required) and validate migration
structure, constraints, RLS policies, seed data, and model consistency.

## Environment

See `.env.example` at the repository root. Required variables include
`DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_PUBLIC_KEY`,
`SUPABASE_SERVICE_KEY`, `JWT_SECRET`, and others — all placeholders only.

> **Note:** No real PostgreSQL database was available in Phase 02. Migrations
> were validated statically (SQL parsing + SQLAlchemy model consistency),
> not executed against a live database.
