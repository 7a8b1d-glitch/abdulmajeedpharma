# Phase 02.5 — Critical Database Security Remediation Report

**Project:** Abdulmajeedpharma (APH)
**Branch:** `arena/fcc02306-abdulmajeedpharma`
**Base commit:** `ef1ee81ae1b62b717f6066049b848d1552e455d7`
**Date:** 2026-11-19
**Status:** COMPLETE (static validation only — no live PostgreSQL available)

---

## Executive Summary

Phase 02.5 remediates all five CRITICAL and four HIGH findings from the independent Phase 02.4 audit. All changes are minimal, carefully reviewed, and preserve existing data. No PostgreSQL runtime testing has been performed — no server is available in this environment. All verification is static (256/256 tests pass, 13/13 migrations parse with pglast).

**No files were committed, pushed, or PR'd. No production database was connected.**

---

## CRITICAL Findings and Fixes

### C1 — reviewed_at INSERT Policy Rejects Legitimate Inserts

**Finding:** The `reviewed_at IS NULL` condition in the content_reviews INSERT RLS policy (migration 010) rejected ALL legitimate reviewer inserts because PostgreSQL applies column DEFAULT (`now()`) before evaluating RLS WITH CHECK clauses. A row with `DEFAULT now()` always has a non-NULL `reviewed_at` at RLS evaluation time.

**Fix:** Removed `AND reviewed_at IS NULL` from the INSERT RLS policy in `database/migrations/010_rls_and_storage_policies.sql`.

**Additional protection:** Added column-level INSERT privileges in `database/migrations/013_migration_tracking_and_legacy_compat.sql`:
- `REVOKE INSERT ON public.content_reviews FROM PUBLIC, authenticated`
- `GRANT INSERT (reviewer_id, drug_evidence_id, review_status, review_notes, content_version, approved_by) ON public.content_reviews TO authenticated` — explicitly excludes `reviewed_at`

**Result:**
- Legitimate INSERT without `reviewed_at` → DEFAULT `now()` applies → RLS checks pass → INSERT succeeds
- INSERT with explicit `reviewed_at` → column-level privilege denies → INSERT rejected
- `reviewer_id = auth.uid()` preserved in RLS policy
- `reviewed_at` remains `NOT NULL`

---

### C2 — Custom GUC Bypass for reviewed_at Protection

**Finding:** The `assert_reviewed_at_immutable()` trigger used `current_setting('aph.allow_reviewed_at_change', true)` to authorize changes. Any authenticated user could execute `set_config('aph.allow_reviewed_at_change', 'true', true)` to bypass timestamp immutability.

**Fix:** Removed the entire GUC-based trigger mechanism from `database/migrations/013_migration_tracking_and_legacy_compat.sql`:
- Dropped `assert_reviewed_at_immutable()` function
- Dropped `trg_content_reviews_reviewed_at_immutable` trigger
- Removed `SET LOCAL aph.allow_reviewed_at_change = 'true'` from `aph_correct_reviewed_at()`
- Removed all references to `aph.allow_reviewed_at_change`

**Replacement:** Protection relies solely on:
1. Column-level `REVOKE UPDATE (reviewed_at) FROM PUBLIC, authenticated` — prevents non-owners from modifying the column
2. `SECURITY DEFINER` function `aph_correct_reviewed_at()` — runs as function owner, bypasses column-level REVOKE, verifies administrator role internally, audits the correction
3. No session variable or GUC can be set by ordinary clients to bypass

---

### C3 — Zero Real PostgreSQL Integration Tests

**Finding:** All 254 Phase 02.4 tests were static text or Python unit tests. Zero tests executed actual SQL against a live PostgreSQL database.

**Fix:** Created `backend/scripts/run_postgresql_integration.py` with 14 integration tests that execute against a live PostgreSQL 15 database:
1. Fresh migrations 001 through latest
2. Migration tracking bootstrap
3. Checksum mismatch rejection
4. Legacy baseline validation
5. Legitimate content_reviews INSERT
6. Forged reviewed_at INSERT rejection
7. Forged reviewer_id rejection
8. reviewed_at UPDATE rejection
9. Custom GUC bypass attempt
10. Self-review rejection
11. Unauthorized DELETE rejection
12. Admin correction authorization
13. Atomic audit logging
14. Concurrent migration runner protection

**Also created:** `backend/tests/integration/00_test_auth_uid_shim.sql` — a test-only Supabase `auth.uid()` compatibility function that reads `current_setting('request.jwt.claim.sub', true)`. **Test databases only — never production.**

**Status:** Integration tests cannot be executed locally (no PostgreSQL server). Configured in CI workflow but unverified.

---

### C4 — Migration Runner Cannot Handle Legacy Databases

**Finding:** The runner blindly executed all migrations from 001 on databases without tracking records, which would fail on legacy schemas with existing data.

**Fix:** Rewrote `backend/scripts/run_migrations.py` with:
- **Advisory lock** (`pg_advisory_lock(2024011901)`) to prevent concurrent runners
- **Legacy detection:** detects migration-managed tables without tracking records, refuses to proceed, and directs operator to use `--baseline`
- **`--baseline` flag:** operator-controlled procedure to record all migrations as applied without executing them (for legacy databases migrated externally)
- **Never silently marks unknown migrations as applied**
- **Checksum verification** for already-applied migrations
- **Clear failure messages** on modified historical migrations
- **Safe failure recording:** failed migrations recorded with `success = FALSE` and transaction rolled back
- **Per-migration atomicity:** DDL + tracking record in same transaction

---

### C5 — auth.uid() Not Available in Plain PostgreSQL CI

**Finding:** `auth.uid()` is Supabase-specific and does not exist in plain `postgres:15-alpine` containers.

**Fix:** Created `backend/tests/integration/00_test_auth_uid_shim.sql` — a test-only function that reads `current_setting('request.jwt.claim.sub', true)`. Applied only in test databases via CI step before integration tests.

**Updated CI workflow** (`.github/workflows/database-readiness.yml`) to:
- Install the auth.uid() shim before integration tests
- Run the integration test script against the live PostgreSQL service container
- Document that the workflow is configured but unverified (no local PostgreSQL)

---

## HIGH Findings and Fixes

### H1 — ALTER COLUMN SET NOT NULL Fails on Existing NULLs

**Finding:** Migration 013's `ALTER COLUMN reviewed_at SET NOT NULL` fails if any legacy rows have NULL `reviewed_at`.

**Status:** No code change — this is correct behavior (no data fabrication). The migration fails loudly rather than inventing timestamps. Operators must remediate NULL values manually before applying migration 013 on legacy databases.

### H2 — FK Additions Fail on Referential Integrity Violations

**Finding:** Migration 013's FK constraint additions fail if existing data violates referential integrity.

**Status:** No code change — correct behavior. The migration fails loudly. Operators must clean up orphaned references before applying migration 013 on legacy databases.

### H3 — No Advisory Lock for Concurrent Runners

**Finding:** The migration runner had no concurrency protection.

**Fix:** Added `pg_advisory_lock(2024011901)` acquired at start and released in `finally` block in `backend/scripts/run_migrations.py`.

### H4 — CI Test Roles Have No Table Privileges

**Finding:** CI test roles were created with only `USAGE ON SCHEMA`, no table-level privileges, so RLS could not be evaluated.

**Fix:** Updated `backend/scripts/run_postgresql_integration.py` to grant:
- `SELECT` on `user_profiles` and `drug_evidence` to all test roles
- `INSERT` on content_reviews columns (excluding `reviewed_at`) to reviewer roles
- `UPDATE` on non-`reviewed_at` columns to reviewer roles

Updated CI workflow to run the integration test script which handles privilege grants.

---

## SQL Privilege Matrix

### content_reviews Table Privileges

| Role | INSERT | UPDATE | SELECT | DELETE | Column Restrictions |
|------|--------|--------|--------|--------|---------------------|
| PUBLIC | REVOKED | REVOKED (reviewed_at) | RLS policy | No policy | No INSERT on `reviewed_at` |
| authenticated | Column-level (excl. reviewed_at) | Column-level (excl. reviewed_at) | RLS policy | No policy | INSERT: reviewer_id, drug_evidence_id, review_status, review_notes, content_version, approved_by |
| Table owner (postgres) | Full | Full (bypasses column-level REVOKE) | Full | Full | N/A |
| SECURITY DEFINER functions | Full (as owner) | Full (as owner) | Full (as owner) | N/A | `aph_correct_reviewed_at()` can UPDATE `reviewed_at` |

### Reviewed_at Protection Layers

| Layer | Mechanism | File | Enforcement |
|-------|-----------|------|-------------|
| Default assignment | `DEFAULT now()` | `006_users_and_permissions.sql` line 74 | Server assigns on INSERT |
| Column-level INSERT | `GRANT INSERT (..., excluding reviewed_at)` | `013` line ~217 | Clients cannot specify `reviewed_at` |
| Column-level UPDATE | `REVOKE UPDATE (reviewed_at)` | `013` line ~217 | Non-owners cannot modify after INSERT |
| RLS INSERT policy | `reviewer_id = auth.uid()` | `010` line ~625 | Reviewer identity bound to auth.uid() |
| Admin correction | `SECURITY DEFINER aph_correct_reviewed_at()` | `013` | Only administrators, audited, atomic |

---

## Migration Runner: Recovery and Baseline Procedures

### Fresh Database

```bash
python scripts/run_migrations.py --dsn "postgresql://user:pass@host:5432/db"
```
Applies migrations 001→013 in order, records each in `schema_migrations`.

### Legacy Database (Already Migrated Externally)

**Step 1:** Detect legacy state:
```bash
python scripts/run_migrations.py --dsn "postgresql://user:pass@host:5432/db"
```
→ Reports "LEGACY DATABASE DETECTED" and exits with code 1.

**Step 2:** Operator validates that all migrations 001-012 have been successfully applied externally, then baselines:
```bash
python scripts/run_migrations.py --dsn "postgresql://user:pass@host:5432/db" --baseline
```
Records all 13 migrations as applied without executing them.

**Step 3:** For new migrations after baseline, run normally:
```bash
python scripts/run_migrations.py --dsn "postgresql://user:pass@host:5432/db"
```
Skips baselined migrations (checksum verified), applies only new ones.

### Failed Migration Recovery

1. Fix the error that caused the failure
2. Re-run: `python scripts/run_migrations.py --dsn "..."`
3. Already-applied migrations are skipped (checksum verified)
4. The failed migration is retried

### Partial Migration Execution

Each migration is committed individually. If the runner is interrupted:
- Completed migrations are recorded in `schema_migrations`
- Re-running resumes from the first unapplied migration
- Advisory lock prevents concurrent runners from conflicting

---

## PostgreSQL Integration Test Evidence

**Status:** NOT EXECUTED — no PostgreSQL server available in this environment.

**Tests configured (14):** See `backend/scripts/run_postgresql_integration.py`.

**Test-only auth.uid() shim:** `backend/tests/integration/00_test_auth_uid_shim.sql` — reads `current_setting('request.jwt.claim.sub', true)`, applies only in test databases.

**CI workflow:** `.github/workflows/database-readiness.yml` — configured with `postgres:15-alpine` service container, but never executed.

**Cannot claim:** Any PostgreSQL runtime test result.

---

## CI Execution Status

| Job | Status | Notes |
|-----|--------|-------|
| static-validation | Configured | Runs 256 static tests + pglast parsing |
| live-database-tests | Configured, unverified | Requires PostgreSQL service container; never executed |
| documentation | Configured | Verifies PHASE_02_5_REMEDIATION_REPORT.md exists |

**No workflow run has occurred.** All CI results are pending.

---

## Remaining Blockers

| Blocker | Impact | Resolution |
|---------|--------|------------|
| No PostgreSQL server available | Cannot execute integration tests; cannot verify RLS, triggers, SECURITY DEFINER functions at runtime | Configure CI with PostgreSQL service container; execute when runner available |
| No Docker/Podman | Cannot build containerized test environment locally | Use GitHub Actions service containers |
| `auth.uid()` is Supabase-specific | Plain PostgreSQL CI container lacks this function | Test-only shim provided; CI step installs it |
| Integration tests never executed | Cannot claim any runtime test result | Mark all integration test results as "pending CI execution" |

---

## Files Changed

| File | Action | Description |
|------|--------|-------------|
| `database/migrations/010_rls_and_storage_policies.sql` | Modified | Removed `reviewed_at IS NULL` from INSERT RLS policy |
| `database/migrations/013_migration_tracking_and_legacy_compat.sql` | Modified | Removed GUC-based trigger; added column-level INSERT privileges; updated comments |
| `backend/scripts/run_migrations.py` | Modified | Added advisory lock, legacy baseline detection, `--baseline` flag, safe failure recording |
| `backend/scripts/run_postgresql_integration.py` | Created | 14 PostgreSQL integration tests |
| `backend/tests/integration/00_test_auth_uid_shim.sql` | Created | Test-only `auth.uid()` compatibility function |
| `.github/workflows/database-readiness.yml` | Modified | Added shim installation, integration test step, updated documentation check |
| `backend/tests/test_database_schema.py` | Modified | Updated 4 tests to match new secure design (removed GUC tests, added column-level privilege tests) |
| `docs/PHASE_02_5_REMEDIATION_REPORT.md` | Created | This report |

---

## Verification Results

| Check | Result |
|-------|--------|
| Static tests (pytest) | 256/256 PASS |
| pglast migration parsing | 13/13 PASS |
| Migration runner dry-run | PASS |
| Health check | 95/95 PASS |
| PostgreSQL integration tests | NOT EXECUTED (no server) |
| CI workflow execution | NOT EXECUTED |

---

## Sign-off

| Item | Status |
|------|--------|
| C1 — reviewed_at INSERT fix | FIXED (static validated) |
| C2 — GUC bypass removal | FIXED (static validated) |
| C3 — Integration tests | CREATED (not executed) |
| C4 — Migration runner legacy handling | FIXED (static validated) |
| C5 — auth.uid() test shim | CREATED (not executed) |
| H1 — NULL reviewed_at handling | DOCUMENTED (correct behavior) |
| H2 — FK data validation | DOCUMENTED (correct behavior) |
| H3 — Advisory lock | FIXED (static validated) |
| H4 — CI role privileges | FIXED (in integration test script) |
| PostgreSQL runtime evidence | NONE — no server available |
| Phase 03 started | NO |

**Final verdict: Phase 02.5 remediation complete (static validation only). Integration tests and CI workflow are configured but unverified pending access to a PostgreSQL server.**
