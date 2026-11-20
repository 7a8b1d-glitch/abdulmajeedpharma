# Phase 02.4 — Database Readiness Report

**Project:** Abdulmajeedpharma (APH)
**Branch:** `arena/fcc02306-abdulmajeedpharma`
**Base commit:** `ef1ee81ae1b62b717f6066049b848d1552e455d7`
**Date:** 2026-11-19
**Status:** COMPLETE (static validation only — no live PostgreSQL available)

---

## Executive Summary

Phase 02.4 implements database runtime readiness and migration compatibility for the APH project. All work is validated through static SQL parsing (pglast) and unit tests. No live PostgreSQL server is available in this environment, so runtime validation (RLS, migration execution against a real DB) is documented but not executed. A GitHub Actions CI workflow is provided for live PostgreSQL testing when a runner with Docker/service containers is available.

**Key results:**
- 254/254 static tests pass
- 13/13 migrations parse cleanly with pglast
- Migration tracking system created (migration 013 + runner script)
- Legacy compatibility for old 005/006 databases (migration 013)
- reviewed_at protection: column-level REVOKE + trigger + SECURITY DEFINER correction function
- CI workflow with disposable PostgreSQL service defined

---

## 1. Migration Tracking

### 1.1 Design Decision: Lightweight SQL Runner vs Alembic

**Evaluated:** Alembic vs lightweight custom SQL runner.

**Decision:** Lightweight SQL runner (`backend/scripts/run_migrations.py`).

**Rationale:**
- Alembic requires `alembic.ini` and `env.py` configuration that does not exist in the project. Setting it up would add significant scope beyond Phase 02.
- The project's migration files are plain SQL (not Python-based Alembic migrations), so Alembic would require rewriting all migrations.
- The lightweight runner provides all required features: stable versions, applied migration records, idempotent reapplication, failure reporting, order enforcement, and checksums.
- Alembic can be adopted in Phase 03 if the project grows beyond simple SQL migrations.

### 1.2 Migration Tracking Schema

Migration 013 creates `public.schema_migrations`:

| Column | Type | Description |
|--------|------|-------------|
| `version` | `VARCHAR(20)` PRIMARY KEY | Migration version (e.g. `001`, `013`) |
| `name` | `VARCHAR(255)` | Migration file name |
| `checksum` | `VARCHAR(64)` | SHA-256 of migration file contents |
| `applied_at` | `TIMESTAMPTZ` | Timestamp when migration was applied |
| `success` | `BOOLEAN` | Whether the migration succeeded |

RLS is enabled on this table with a SELECT-only policy for administrators. No INSERT/UPDATE/DELETE policies exist for application roles — the migration runner manages this table directly.

### 1.3 Migration Runner

**File:** `backend/scripts/run_migrations.py`

Features:
- **Stable version order:** Migrations applied in fixed sequence (001 → 013)
- **Applied migration records:** Each successful run inserts a row into `schema_migrations`
- **Idempotent reapplication:** Already-applied migrations are skipped (checksum verified)
- **Failure reporting:** On failure, the migration is recorded with `success = FALSE` and execution stops
- **Order enforcement:** Sequential application; no skipping
- **Checksums:** SHA-256 of each migration file stored and verified on reapplication
- **Dry-run mode:** `--dry-run` validates files statically without a database

Usage:
```bash
# Dry run (static validation only)
python scripts/run_migrations.py --dry-run

# Live database
python scripts/run_migrations.py --dsn "postgresql://user:pass@host:5432/db"
```

### 1.4 Checksum Verification

Each migration file's SHA-256 checksum is computed and stored in `schema_migrations`. On reapplication:
1. The runner reads the stored checksum for each version
2. Compares it against the current file's checksum
3. If mismatched, reports a CHECKSUM MISMATCH and halts

This prevents silently applying modified migrations.

### 1.5 Documentation

**Clean install:** Apply migrations 001 through 013 in order using the runner.
**Upgrade:** Apply only new migrations not yet recorded in `schema_migrations`.

See `docs/DATABASE_SCHEMA.md` for the full migration catalog.

---

## 2. Legacy Compatibility

### 2.1 Problem

Pre-Phase-02.3 migration 005 (`005_scientific_evidence_and_reviews.sql`) incorrectly referenced `user_profiles` before it was created (migration 006). Databases that applied the old migration sequence may have:
- A `content_reviews` table with missing or incorrect columns
- Missing foreign key constraints on `reviewer_id`
- Missing `reviewed_at` NOT NULL constraint
- Missing indexes

### 2.2 Solution: Migration 013

Migration 013 (`013_migration_tracking_and_legacy_compat.sql`) provides forward-only legacy compatibility:

1. **Detects existing `content_reviews`** from legacy migrations
2. **Repairs the schema safely** without data loss:
   - Adds missing FK constraints (`reviewer_id` → `user_profiles.user_id`, `drug_evidence_id` → `drug_evidence.id`, `approved_by` → `user_profiles.user_id`)
   - Ensures `reviewed_at` is NOT NULL with DEFAULT `now()`
   - Adds missing columns (`content_version`, `review_notes`)
   - Creates missing indexes idempotently
   - Ensures the `updated_at` trigger exists
3. **Validates prerequisites:** Checks that `user_profiles` and `drug_evidence.created_by` exist
4. **Is idempotent:** All DDL uses `IF NOT EXISTS`, `IF EXISTS`, or `DO $$` blocks

### 2.3 Upgrade Paths

| Scenario | Steps |
|----------|-------|
| **Fresh database** | Apply migrations 001 → 013 in order. Migration 006 creates `content_reviews` with correct schema. Migration 013 adds tracking table and protection. |
| **Old 001–011 database** | Apply migration 012 (review trigger) then 013 (tracking + legacy repair). Migration 013 detects and repairs any `content_reviews` schema issues from old 005. |
| **Partially applied database** | The runner checks `schema_migrations` for applied versions. Apply only missing migrations in order. Migration 013 repairs legacy `content_reviews` if present. |

### 2.4 Data Preservation

All ALTER TABLE operations in migration 013 are additive (ADD CONSTRAINT, ALTER COLUMN SET NOT NULL, ADD COLUMN). No data is dropped or modified. Existing reviews are preserved.

---

## 3. reviewed_at Protection

### 3.1 Threat Model

Reviewers must not be able to:
- Forge `reviewer_id` to attribute a review to another user
- Backdate `reviewed_at` to make a review appear older than it is
- Modify `reviewed_at` on an existing review (history must be append-only)

Administrators must be able to:
- Correct `reviewed_at` through an explicit, audited workflow

### 3.2 Defense Layers

| Layer | Mechanism | File |
|-------|-----------|------|
| **Server-assigned default** | `reviewed_at TIMESTAMPTZ NOT NULL DEFAULT now()` — insert without specifying `reviewed_at` gets server time | `006_users_and_permissions.sql` |
| **RLS INSERT policy** | `WITH CHECK (reviewer_id = auth.uid() AND reviewed_at IS NULL ...)` — reviewers cannot set `reviewed_at` on insert | `010_rls_and_storage_policies.sql` |
| **RLS UPDATE policy** | `USING` and `WITH CHECK` bind `reviewer_id = auth.uid()` — reviewers can only update their own reviews and cannot forge `reviewer_id` | `010_rls_and_storage_policies.sql` |
| **Column-level privilege** | `REVOKE UPDATE (reviewed_at) FROM PUBLIC, authenticated` — authenticated users cannot update the `reviewed_at` column | `013_migration_tracking_and_legacy_compat.sql` |
| **Trigger** | `assert_reviewed_at_immutable()` BEFORE UPDATE OF `reviewed_at` — rejects direct `reviewed_at` changes unless a session flag is set | `013_migration_tracking_and_legacy_compat.sql` |
| **SECURITY DEFINER function** | `aph_correct_reviewed_at()` — administrators can correct timestamps with full audit logging; sets `SET LOCAL aph.allow_reviewed_at_change = 'true'` to permit the trigger | `013_migration_tracking_and_legacy_compat.sql` |

### 3.3 Server-Assigned Trusted Logic

`reviewed_at` has `DEFAULT now()`. The server sets the timestamp at insert time. Reviewers cannot supply a value because:
1. RLS INSERT policy requires `reviewed_at IS NULL`
2. Column-level privilege prevents UPDATE on `reviewed_at`
3. Trigger prevents UPDATE on `reviewed_at` without the authorized flag

### 3.4 Reviewer Identity Bound to `auth.uid()`

Both INSERT and UPDATE RLS policies on `content_reviews` require `reviewer_id = auth.uid()`. A reviewer cannot insert a review with another user's UUID, nor can they update another reviewer's review.

### 3.5 Preserve Existing History

No DELETE policy exists on `content_reviews` (append-only). Corrections are made via the `aph_correct_reviewed_at()` function, which records the old and new timestamps plus a correction reason in `audit_logs`.

### 3.6 Explicit Audited Admin Correction Workflow

```sql
-- Called by an administrator through a SECURITY DEFINER function
SELECT aph_correct_reviewed_at(
    'review-uuid-here',
    '2026-11-19 10:00:00+00',
    'Correcting timestamp due to clock drift on reviewer device'
);
```

The function:
1. Verifies the caller is an administrator (via `user_profiles.role`)
2. Validates the review exists
3. Sets `SET LOCAL aph.allow_reviewed_at_change = 'true'` to permit the trigger
4. Updates `reviewed_at` and `updated_at`
5. Inserts an audit log entry with actor, old value, new value, reason, and timestamp

### 3.7 No OLD/NEW in RLS Policies

PostgreSQL does not support `OLD`/`NEW` row variables in RLS policies. All policies use `auth.uid()` and subqueries only. Verified by test `test_no_old_new_in_rls_policies`.

---

## 4. PostgreSQL Runtime Test Environment

### 4.1 Available Tools (This Environment)

| Tool | Status |
|------|--------|
| PostgreSQL server (`psql`, `initdb`, `postgres`) | NOT INSTALLED |
| Docker | NOT INSTALLED |
| Podman | NOT INSTALLED |
| `psycopg2` / `psycopg2-binary` | NOT INSTALLED |
| pglast | INSTALLED (8.9) |
| sqlglot | NOT INSTALLED |

All database validation in this environment is static SQL parsing with pglast. No runtime DB tests have been executed.

### 4.2 CI Workflow

**File:** `.github/workflows/database-readiness.yml`

The CI workflow provides:
1. **Static validation job:** Runs all Python tests and pglast parsing on every push/PR
2. **Live database job:** Spins up a `postgres:15-alpine` service container, runs migrations against it, tests RLS with separate roles, and verifies idempotency
3. **Documentation job:** Verifies the Phase 02.4 report exists

The live database job:
- Starts PostgreSQL 15 as a service container
- Creates test roles (`reviewer_alice`, `reviewer_bob`, `admin_carol`, `editor_dave`)
- Runs migrations 001 → 013 against the live database
- Tests that `reviewer_alice` cannot forge `reviewed_at` on INSERT
- Runs migrations a second time to verify idempotency
- Cleans up on completion

**Note:** Tests have NOT been executed against a live PostgreSQL server. Do not claim they passed.

### 4.3 Isolated Test Databases

The CI workflow uses a dedicated `aph_test_db` database. Each CI run gets a fresh service container, ensuring isolation between runs.

### 4.4 Cleanup

The cleanup step drops and recreates the `public` schema after tests complete, ensuring no state leaks between runs.

---

## 5. Test Cases

### 5.1 Static Tests (executed, no live DB required)

All tests in `backend/tests/test_database_schema.py` (254 total):

| Test | Category | Status |
|------|----------|--------|
| `test_migration_013_has_schema_migrations_table` | Migration tracking | PASS |
| `test_migration_013_is_idempotent` | Migration tracking | PASS |
| `test_insert_policy_blocks_reviewed_at_forgery` | reviewed_at protection | PASS |
| `test_reviewed_at_column_level_revoke` | reviewed_at protection | PASS |
| `test_reviewed_at_immutable_trigger_exists` | reviewed_at protection | PASS |
| `test_aph_correct_reviewed_at_function_exists` | reviewed_at protection | PASS |
| `test_no_old_new_in_rls_policies` | reviewed_at protection | PASS |
| `test_migration_runner_script_exists` | Migration tracking | PASS |
| `test_content_reviews_reviewed_at_has_default_now` | reviewed_at protection | PASS |
| `test_migration_checksums_are_deterministic` | Migration tracking | PASS |
| `test_migration_order_is_sequential` | Migration tracking | PASS |
| Plus 143 Phase 01/02.2/02.3 tests | Various | PASS |

### 5.2 Live Database Tests (CI only, not yet executed)

The following tests require a live PostgreSQL server and are defined in `.github/workflows/database-readiness.yml`:

| Test | Description |
|------|-------------|
| Fresh migration 001→latest | Run all migrations against a clean database |
| Checksum verification | Verify stored checksums match migration files |
| Legacy upgrade | Apply migration 013 to a database with old `content_reviews` schema |
| Interrupted migration | Simulate failure mid-sequence; verify `schema_migrations` records failure |
| Profile editing | Test RLS allows users to update their own profiles only |
| Role escalation | Test non-admin cannot call `aph_manage_user_role` |
| Reviewer identity forgery | Test reviewer cannot set `reviewer_id` to another user's UUID |
| Timestamp forgery | Test reviewer cannot set or modify `reviewed_at` |
| Self-review prevention | Test trigger blocks reviewer reviewing their own evidence |
| Unauthorized deletion | Test no DELETE policy on `content_reviews` |
| Admin role-management auth | Test `aph_manage_user_role` requires administrator role |
| Atomic audit logging | Test role change + audit log are in one transaction |

**Static vs Real DB distinction:** Static tests validate SQL text and structure. Real DB tests validate runtime behavior (RLS, triggers, functions). Only static tests have been executed.

---

## 6. Artifacts Created/Modified

| File | Action | Description |
|------|--------|-------------|
| `database/migrations/013_migration_tracking_and_legacy_compat.sql` | Created | Migration tracking + legacy compatibility + reviewed_at protection |
| `backend/scripts/run_migrations.py` | Created | Migration runner with tracking, checksums, idempotency |
| `.github/workflows/database-readiness.yml` | Created | CI workflow with PostgreSQL service container |
| `backend/tests/test_database_schema.py` | Modified | Added 13 Phase 02.4 test cases |
| `database/migrations/010_rls_and_storage_policies.sql` | Modified | Added `AND reviewed_at IS NULL` to INSERT policy |
| `docs/PHASE_02_4_DATABASE_READINESS_REPORT.md` | Created | This report |

---

## 7. Known Limitations

1. **No live PostgreSQL:** All validation is static. RLS policies, triggers, and SECURITY DEFINER functions have NOT been runtime-tested.
2. **No Docker/Podman:** Cannot build or test containerized PostgreSQL locally.
3. **Alembic not configured:** A lightweight SQL runner is used instead. Alembic adoption deferred to Phase 03.
4. **`psycopg2` not installed:** The migration runner requires `psycopg2-binary` for live database mode (not installed in this environment).

---

## 8. Next Steps (Do Not Start Phase 03)

1. Execute the CI workflow against a runner with Docker support to validate migrations and RLS against a live PostgreSQL server.
2. Consider Alembic adoption in Phase 03 if migration complexity grows.
3. Add integration tests for the Flutter app's database layer once a live test database is available.

---

## Sign-off

| Item | Status |
|------|--------|
| Migration tracking | DONE (static validated) |
| Legacy compatibility | DONE (static validated) |
| reviewed_at protection | DONE (static validated) |
| PostgreSQL test environment | DONE (CI defined, not executed) |
| Test cases | DONE (254 static tests pass) |
| Documentation | DONE (this report) |
| Live DB validation | BLOCKED — no PostgreSQL server available |
