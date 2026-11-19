# Abdulmajeedpharma (APH) — Architecture Document

**Project Owner:** Dr. Abdulmajeed Abdullah Almakhedhi  
**App Short Name:** APH  
**Phase:** Phase 01 — Foundation (scaffold only)

## 1. Overview

APH is a pharmaceutical platform primarily for Android users, consisting of:

- **Flutter mobile app** (Android-first, Arabic + English, RTL/LTR, light/dark themes)
- **FastAPI backend** (Python, cloud PostgreSQL)
- **Next.js admin dashboard**
- **AI RAG** (Pharma AI)
- **Data import pipeline** (CSV/Excel/JSON/images)

## 2. Flutter Mobile — Clean Architecture

### Feature-first structure

Each feature under `lib/features/<feature>` follows Clean Architecture layers:

- **data/** — repository implementations, remote & local datasources, data models
- **domain/** — entities, use cases, repository interfaces
- **presentation/** — Riverpod providers, UI pages/widgets

### Cross-cutting core

- `core/config` — environment/flavor config (dart-define; no hardcoded secrets)
- `core/constants` — design tokens (APH palette), route names, app constants
- `core/errors` — custom exceptions (`AppException`, `ApiException`, `AuthException`, …) and `Failure`
- `core/localization` — i18n/l10n (Arabic Yemen + English), RTL/LTR
- `core/network` — Dio API client with auth interceptor
- `core/storage` — SharedPreferences wrapper (local storage)
- `core/theme` — light/dark `ThemeData` based on APH palette
- `core/utils` — helpers/extensions

### State management & navigation

- **Riverpod** for state management and dependency injection.
- **GoRouter** for declarative routing.

### Brand palette

| Role | Hex |
|------|-----|
| Deep Navy | #102A43 |
| Medical Blue | #168AAD |
| Turquoise | #20B8B0 |
| White | #FFFFFF |
| Soft Background | #F4F7FA |
| Success Green | #249B78 |

### Offline-first

- **SQLite (Drift)** for offline database.
- **Supabase** for cloud auth and storage.
- **Central synchronization** between local SQLite and cloud backend.

## 3. FastAPI Backend

- **app/main.py** — FastAPI entry point, CORS, health check.
- **app/core/config** — Pydantic settings from `.env`.
- **app/api** — route routers (`api_router`, versioned `/api/v1`).
- **app/models** — SQLAlchemy async models (PostgreSQL).
- **app/schemas** — Pydantic v2 request/response schemas.
- **app/services** — business logic.
- **app/repositories** — data access layer.

## 4. Cloud Database

- **PostgreSQL** (cloud, e.g., Supabase Postgres) as the primary database.
- Connection via `DATABASE_URL` (never committed).
- Alembic migrations under `database/migrations/`.

## 5. Supabase Authentication & Storage

- Supabase Auth for user authentication (mobile + backend).
- Supabase Storage for product images and documents.
- **Security rule:** Supabase service-role keys are backend-only; never exposed in Flutter or browser/admin code.

## 6. Central Synchronization

- Mobile works offline with local SQLite.
- Changes sync to the cloud backend when connectivity is restored.
- Conflict resolution strategy defined in Phase 02.

## 7. Next.js Admin Dashboard

- Next.js 14 (App Router), React 18, TypeScript, Tailwind CSS.
- Administrative website for managing drugs, manufacturers, suppliers, orders.

## 8. AI RAG Architecture (`ai/`)

- `ai/rag/` — retrieval-augmented generation pipeline.
- `ai/prompts/` — system/user prompt templates.
- AI provider configured via `.env` (`AI_PROVIDER`, `AI_API_KEY`).
- Google Cloud project for Vertex AI (optional provider).

## 9. Pharmaceutical Data Provenance

- All drug/reference data imported via `data-import/` pipeline (CSV/Excel/JSON/images).
- Provenance metadata (source, import date, batch) tracked per record.
- No real drug or patient data is committed to this repository.

## 10. Security Foundations

- `.env.example` with placeholders only; real `.env` never committed.
- JWT for access tokens (`JWT_SECRET`).
- Service-role keys restricted to trusted backend environments.
- See `docs/SECURITY.md`.

## 11. Module Responsibilities

| Module | Responsibility |
|--------|---------------|
| mobile | Android-first Flutter client; offline DB; Supabase auth/storage; RTL/LTR; themes |
| backend | FastAPI API; business logic; PostgreSQL access; JWT; Supabase server-side |
| admin | Next.js admin dashboard for platform management |
| database | PostgreSQL schema, migrations, seeds |
| data-import | Reference data import sources and pipeline |
| ai | RAG pipeline and prompts for Pharma AI |
| infrastructure | Docker / deployment configuration |
| docs | Architecture, status, security, roadmap |
| scripts | Health checks and tooling |
