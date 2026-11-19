# Abdulmajeedpharma — FastAPI Backend

Pharmaceutical platform backend.

## Stack

- FastAPI
- SQLAlchemy (async) + PostgreSQL
- Alembic migrations
- Pydantic v2
- Supabase (auth/storage server-side)
- Redis
- Python 3.11

## Structure

```
backend/
├── app/
│   ├── main.py            # FastAPI entry point
│   ├── core/              # config, security, database
│   ├── api/               # route routers (api_router + v1)
│   ├── models/            # SQLAlchemy models
│   ├── schemas/           # Pydantic schemas
│   ├── services/          # business logic
│   └── repositories/      # data access
├── tests/
├── requirements.txt
└── README.md
```

## Running

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp ../.env.example .env   # adjust paths as needed
uvicorn app.main:app --reload
```

> **Note (Phase 01):** Python syntax validation is supported; FastAPI import/tests
> require `pip install -r requirements.txt`, which is deferred to Phase 02 to
> avoid blindly installing large dependencies.
