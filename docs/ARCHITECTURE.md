# Abdulmajeedpharma (APH) — Architecture Document

**Project Owner:** Dr. Abdulmajeed Abdullah Almakhedhi  
**App Short Name:** APH  
**Phase:** Phase 02 — Database Foundation

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
- **app/models** — SQLAlchemy async models (PostgreSQL), 39 tables mirrored from migrations.
- **app/schemas** — Pydantic v2 request/response schemas.
- **app/services** — business logic.
- **app/repositories** — data access layer.

### Database configuration

- `DATABASE_URL` from `.env` (never committed).
- SQLAlchemy 2.0 with asyncpg driver.
- Alembic listed in requirements.txt but not configured; plain SQL migrations used directly.

## 4. Cloud Database (PostgreSQL / Supabase)

**PostgreSQL** (cloud, e.g., Supabase Postgres) as the primary database.

### Migrations (11 files, `database/migrations/`)

| # | File | Purpose |
|---|------|---------|
| 001 | `001_extensions_and_helpers.sql` | pgcrypto, pg_trgm; trigger/helper functions |
| 002 | `002_geography_and_classification.sql` | countries, body_systems, therapeutic_classes, pharmacological_classes, drug_classes |
| 003 | `003_drug_catalog.sql` | active_ingredients, drugs, and 10 related catalog tables |
| 004 | `004_companies_and_market.sql` | manufacturers, MAH, suppliers, distributors, brand_products, presentations, markets, registrations |
| 005 | `005_scientific_evidence_and_reviews.sql` | scientific_sources, drug_evidence, content_reviews |
| 006 | `006_users_and_permissions.sql` | user_profiles (Supabase auth.users linked) |
| 007 | `007_messaging_and_notifications.sql` | conversations, participants, messages, attachments, receipts, notifications |
| 008 | `008_imports_and_audit.sql` | import_batches, import_batch_items, import_errors, audit_logs, sync_records |
| 009 | `009_indexes_and_search.sql` | Full-text search vectors, trigram indexes, composite indexes |
| 010 | `010_rls_and_storage_policies.sql` | RLS enablement, ownership columns, role-based policies |
| 011 | `011_seed_reference_data.sql` | Yemen country, 18 body systems (idempotent) |

### Key design decisions

- **UUID primary keys** (`gen_random_uuid()` from pgcrypto) on all tables.
- **`timestamptz`** for all timestamps; `created_at` and `updated_at` where appropriate.
- **Bilingual fields** (`*_en` / `*_ar`); missing translations allowed (NULL).
- **No fake data:** Only 18 body systems and Yemen country are seeded.
- **Row Level Security (RLS):** Enabled on all 39 tables with role-based policies.
- **Supabase Auth:** Identity provider; `user_profiles.user_id` references `auth.users(id)`.
- **Roles:** user, editor, scientific_reviewer, administrator.
- **No plaintext passwords:** Supabase Auth handles hashing.
- **No secrets in audit_logs:** CHECK constraint rejects password/token/key metadata.

## 5. Supabase Authentication & Storage

- Supabase Auth for user authentication (mobile + backend).
- Supabase Storage for product images and documents.
- **Security rule:** Supabase service-role keys are backend-only; never exposed in Flutter or browser/admin code.
- RLS policies use `auth.uid()` for user identification.

## 6. Central Synchronization

- Mobile works offline with local SQLite (Drift).
- Changes sync to the cloud backend when connectivity is restored.
- `sync_records` table provides the foundation for future offline synchronization.
- Conflict resolution strategy to be defined in a later phase.

## 7. Next.js Admin Dashboard

- Next.js 14 (App Router), React 18, TypeScript, Tailwind CSS.
- Administrative website for managing drugs, manufacturers, suppliers, orders.

## 8. AI RAG Architecture (`ai/`)

- `ai/rag/` — retrieval-augmented generation pipeline.
- `ai/prompts/` — system/user prompt templates.
- AI provider configured via `.env` (`AI_PROVIDER`, `AI_API_KEY`).
- Google Cloud project for Vertex AI (optional provider).
- Scientific evidence and review workflow tables support RAG source traceability.

## 9. Pharmaceutical Data Provenance

- All drug/reference data imported via `data-import/` pipeline (CSV/Excel/JSON/images).
- `import_batches`, `import_batch_items`, `import_errors` track import provenance.
- `product_registration_records.source_reference` tracks registration source.
- `scientific_sources` tracks evidence provenance (DOI, URL, organization).
- No real drug or patient data is committed to this repository.

## 10. Security Foundations

- `.env.example` with placeholders only; real `.env` never committed.
- JWT for access tokens (`JWT_SECRET`).
- Service-role keys restricted to trusted backend environments.
- RLS on all tables; no `USING (true)` on private tables.
- Audit logs capture actor, action, entity, timestamp, safe metadata only.
- See `docs/DATABASE_SECURITY.md` and `docs/RLS_POLICY_MATRIX.md`.

## 11. Module Responsibilities

| Module | Responsibility |
|--------|---------------|
| mobile | Android-first Flutter client; offline DB; Supabase auth/storage; RTL/LTR; themes |
| backend | FastAPI API; business logic; PostgreSQL access; JWT; Supabase server-side |
| admin | Next.js admin dashboard for platform management |
| database | PostgreSQL schema, migrations (11 files), seeds (18 body systems + Yemen) |
| data-import | Reference data import sources and pipeline (import tables defined) |
| ai | RAG pipeline and prompts for Pharma AI (evidence/review tables defined) |
| infrastructure | Docker / deployment configuration |
| docs | Architecture, status, security, roadmap, database docs |
| scripts | Health checks and tooling |

## 12. Known Limitations

- Arabic full-text search stemming is not natively optimal in PostgreSQL without external dictionaries.
- No real PostgreSQL database was available in Phase 02; migrations validated statically only.
- Alembic not configured; plain SQL migrations used directly.
