# Abdulmajeedpharma (APH) — Development Status

Status values: IMPLEMENTED | TESTED | REQUIRES_EXTERNAL_CONFIGURATION | BLOCKED | NOT_IMPLEMENTED

## Legend

- **IMPLEMENTED** — file/code exists and has been created (scaffold).
- **TESTED** — actually executed and verified in this environment.
- **REQUIRES_EXTERNAL_CONFIGURATION** — needs `.env` values / external services.
- **BLOCKED** — cannot run because a tool/dependency is missing (Flutter, Docker, etc.).
- **NOT_IMPLEMENTED** — not yet created (deferred to a later phase).

> Generated files = scaffolded in Phases 01–02. Executed/tested files = verified by
> running checks in this environment. Nothing in this repo has been deployed.

## Mobile (Flutter)

| Item | Status | Notes |
|------|--------|-------|
| Directory structure | IMPLEMENTED | Scaffolded |
| pubspec.yaml | IMPLEMENTED | Not validated (`flutter` missing) |
| analysis_options.yaml | IMPLEMENTED | Not validated |
| lib/main.dart | IMPLEMENTED | Dart syntax not validated (no Dart SDK) |
| app/ (router, app shell) | IMPLEMENTED | Scaffold |
| core/ (config, constants, errors, localization, network, storage, theme, utils) | IMPLEMENTED | Scaffold |
| shared/ (widgets, models) | IMPLEMENTED | Scaffold |
| features/ (all 17) | IMPLEMENTED | Placeholder READMEs only |
| Flutter analyze | BLOCKED | Flutter SDK not installed |
| Flutter test | BLOCKED | Flutter SDK not installed |

## Backend (FastAPI)

| Item | Status | Notes |
|------|--------|-------|
| Directory structure | IMPLEMENTED | Scaffolded |
| app/main.py | IMPLEMENTED | Python syntax validated; imports OK |
| app/core/config.py | IMPLEMENTED | Python syntax validated |
| app/api/api_router.py | IMPLEMENTED | Python syntax validated |
| app/models/ (39 models) | IMPLEMENTED | Python syntax validated; all import OK |
| app/schemas/* | IMPLEMENTED | Python syntax validated |
| app/services/* | IMPLEMENTED | Scaffold |
| app/repositories/* | IMPLEMENTED | Scaffold |
| tests/ | IMPLEMENTED | 254 tests passing (243 Phase 01–02.3 + 11 Phase 02.4) |
| requirements.txt | IMPLEMENTED | Installed in `.venv` |
| Backend import/tests | TESTED | 254 tests passed (static validation + pglast grammar + security regression) |

## Admin (Next.js)

| Item | Status | Notes |
|------|--------|-------|
| package.json | IMPLEMENTED | JSON validated; `npm install` completed |
| Next.js app | NOT_IMPLEMENTED | Deferred to a later phase |

## Database (PostgreSQL)

| Item | Status | Notes |
|------|--------|-------|
| migrations/ (13 files) | IMPLEMENTED | SQL validated statically (pglast); 013 adds migration tracking + legacy compat + reviewed_at protection |
| seeds/ (011 seed) | IMPLEMENTED | Idempotent seed for 18 body systems + Yemen |
| 18 body systems seeded | IMPLEMENTED | Stable codes, English + Arabic names |
| Yemen country seeded | IMPLEMENTED | Code YE |
| RLS policies | IMPLEMENTED | Defined in migration 010; INSERT policy blocks reviewed_at forgery |
| SQLAlchemy models (39) | IMPLEMENTED | Match migrations; all import OK |
| Backend-model consistency | TESTED | 254 schema/pglast/security tests passed (static validation) |
| Column-level security (user_profiles) | IMPLEMENTED | REVOKE/GRANT on privileged columns in migration 010 |
| Column-level security (content_reviews.reviewed_at) | IMPLEMENTED | REVOKE UPDATE (reviewed_at) FROM PUBLIC/authenticated in migration 013 |
| SECURITY DEFINER functions | IMPLEMENTED | aph_manage_user_role, aph_manage_user_profile in migration 010; aph_correct_reviewed_at in migration 013 |
| Review traceability | IMPLEMENTED | reviewed_at NOT NULL DEFAULT now(), reviewer_id FK, no-self-review trigger, reviewed_at immutable trigger |
| Migration 012 (review trigger) | IMPLEMENTED | assert_no_self_review() function + trigger after drug_evidence.created_by exists |
| Migration 013 (tracking + legacy + protection) | IMPLEMENTED | schema_migrations table, legacy content_reviews repair, reviewed_at column-level REVOKE + trigger + SECURITY DEFINER correction |
| Real PostgreSQL execution | BLOCKED | No PostgreSQL server available; CI workflow defined in .github/workflows/database-readiness.yml |
| Alembic integration | NOT_IMPLEMENTED | Lightweight SQL runner (backend/scripts/run_migrations.py) used instead |
| Migration runner | IMPLEMENTED | backend/scripts/run_migrations.py — dry-run validated |

## Data Import

| Item | Status | Notes |
|------|--------|-------|
| csv/, excel/, json/, images/ | IMPLEMENTED | Empty directories |
| import_batches, items, errors tables | IMPLEMENTED | In migration 008 |

## AI

| Item | Status | Notes |
|------|--------|-------|
| rag/, prompts/ | IMPLEMENTED | Empty directories |
| scientific_sources, drug_evidence, content_reviews | IMPLEMENTED | In migration 005 |

## Infrastructure

| Item | Status | Notes |
|------|--------|-------|
| docker/ | IMPLEMENTED | Empty; Docker not installed (BLOCKED for build) |

## Docs

| Item | Status | Notes |
|------|--------|-------|
| ARCHITECTURE.md | IMPLEMENTED | Updated for Phase 02 |
| DEVELOPMENT_STATUS.md | IMPLEMENTED | This document |
| SECURITY.md | IMPLEMENTED | — |
| ROADMAP.md | IMPLEMENTED | — |
| DATABASE_SCHEMA.md | IMPLEMENTED | New (Phase 02) |
| DATABASE_SECURITY.md | IMPLEMENTED | New (Phase 02) |
| RLS_POLICY_MATRIX.md | IMPLEMENTED | New (Phase 02) |
| DATABASE_SETUP.md | IMPLEMENTED | New (Phase 02) |
| PHASE_02_REPORT.md | IMPLEMENTED | New (Phase 02) |

## Scripts

| Item | Status | Notes |
|------|--------|-------|
| health_check.py | IMPLEMENTED | TESTED (95/95 passed) |

## Configuration

| Item | Status | Notes |
|------|--------|-------|
| .env.example | IMPLEMENTED | Placeholders only; requires external config |
| .gitignore | IMPLEMENTED | Covers env, node_modules, cache, venv, signing keys |
| README.md | IMPLEMENTED | — |
| LICENSE | IMPLEMENTED | — |

## Environment

| Tool | Version | Status |
|------|---------|--------|
| Git | 2.39.5 | TESTED |
| Python | 3.11.2 | TESTED |
| Node.js | 22.22.3 | TESTED |
| npm | 10.9.8 | TESTED |
| Flutter | — | BLOCKED (not installed) |
| Dart | — | BLOCKED (not installed) |
| Docker | — | BLOCKED (not installed) |
| Android SDK | — | BLOCKED (not installed) |
| PostgreSQL (psql/pg_isready) | — | BLOCKED (not available) |
| SQLAlchemy | 2.0.29 | TESTED (in .venv) |
| FastAPI | 0.111.0 | TESTED (in .venv) |
| Pytest | 8.2.0 | TESTED (in .venv) |
| sqlglot | 30.33.0 | TESTED (static SQL validation) |
| pglast | 8.9 | TESTED (native PostgreSQL grammar validation, 13/13 migrations) |

## Summary

- Implemented scaffold files: yes (all Phase 01 + Phase 02)
- Actually executed & tested: health_check.py (95/95), backend tests (254 passed), Python syntax validation, SQL static validation (13/13 migrations via pglast), migration runner dry-run validated
- Blocked: Flutter analyze/test, real PostgreSQL execution, Docker build, Alembic integration
- Deployed: no
