# Phase 02.5 — Independent Remediation Audit

**Project:** Abdulmajeedpharma (APH)
**Branch:** `arena/fcc02306-abdulmajeedpharma`
**Base commit:** `ef1ee81ae1b62b717f6066049b848d1552e455d7`
**HEAD commit:** `76b599b Phase 02: Database foundation, PostgreSQL & security`
**Audit date:** 2026-11-19
**Auditor:** Independent PostgreSQL security and migration auditor
**Scope:** Phase 02.5 remediation implementation (uncommitted working tree changes)
**Constraint:** No files modified. No production connection. No runtime execution claimed.

---

## Executive Summary

**Verdict: PASS WITH BLOCKERS**

The Phase 02.5 remediation correctly addresses all five CRITICAL findings from the independent Phase 02.4 audit:
1. ✅ `reviewed_at IS NULL` removed from INSERT RLS policy
2. ✅ Custom GUC bypass mechanism removed
3. ✅ Column-level INSERT privileges added (excluding `reviewed_at`)
4. ✅ Migration runner has advisory lock, legacy baseline detection, `--baseline` flag
5. ✅ Test-only `auth.uid()` shim created for plain PostgreSQL CI

All 256 static tests pass. All 13 migrations parse cleanly with pglast. The migration runner dry-run validates successfully.

**However, no PostgreSQL runtime testing has been performed.** All integration tests, CI workflow execution, and real database validation are pending. The workflow is configured but has never executed.

Two test-quality issues were identified in the integration test suite (tautological checksum test, weak legacy baseline test) that should be corrected before CI execution.

---

## AUDIT 1 — Historical Migration Checksums

### Files inspected
- `database/migrations/010_rls_and_storage_policies.sql` (working tree)
- `database/migrations/013_migration_tracking_and_legacy_compat.sql` (working tree)
- Git history

### Git history findings

| Migration | Introduced in commit | Modified in Phase 02.5 | Status |
|-----------|---------------------|----------------------|--------|
| 010 | `76b599b` | Yes — removed `reviewed_at IS NULL` from INSERT policy | Working tree only |
| 013 | `76b599b` | Yes — removed GUC trigger, added column-level INSERT privileges | Working tree only |

Neither migration 010 nor 013 has been committed yet. All Phase 02.5 changes exist only in the uncommitted working tree.

### Checksum mismatch implications

An existing database that previously recorded checksums for migration 010 or 013 (from commit `76b599b`) would encounter a **CHECKSUM MISMATCH** when the runner re-executes with the modified files. The runner correctly detects this:

```python
# run_migrations.py, apply_migrations()
if stored_checksum != checksum:
    print(f"  [{version}] {filename} — CHECKSUM MISMATCH")
    ...
    failures += 1
    break
```

This is correct behavior — the runner halts rather than silently applying modified migrations.

### Is migration 014 required?

**No.** A forward-only migration 014 is not required. The checksum mismatch mechanism is the correct way to handle modified migration files. Operators have two paths:

1. **Fresh database:** Apply migrations 001→013 (current versions) in order. All checksums match because nothing was previously recorded.
2. **Previously deployed database:** The runner detects existing `schema_migrations` records with old checksums for 010/013 and halts with CHECKSUM MISMATCH. The operator must either:
   - Re-record the correct checksums (if the database state matches the new migration content), or
   - Use `--baseline` to record all migrations as applied (for legacy databases migrated externally), then apply only new migrations.

### Fresh vs. previously deployed database compatibility

| Scenario | Can reach same schema? | Notes |
|----------|----------------------|-------|
| Fresh database | YES | Migrations 001→013 apply cleanly |
| Previously deployed (010/013 at commit 76b599b) | PARTIAL | Checksum mismatch halts runner; operator intervention required |
| Legacy (no tracking records) | PARTIAL | Runner detects legacy state, refuses to proceed without --baseline |

---

## AUDIT 2 — INSERT Privileges

### Files inspected
- `database/migrations/006_users_and_permissions.sql` (line 74: column definition)
- `database/migrations/010_rls_and_storage_policies.sql` (INSERT RLS policy)
- `database/migrations/013_migration_tracking_and_legacy_compat.sql` (column-level privileges)

### Privilege matrix for content_reviews

| Privilege | PUBLIC | authenticated | Table owner | SECURITY DEFINER functions |
|-----------|--------|---------------|-------------|---------------------------|
| INSERT (table-level) | REVOKED | REVOKED | Full | Full (as owner) |
| INSERT (reviewer_id) | — | GRANTED | Full | Full |
| INSERT (drug_evidence_id) | — | GRANTED | Full | Full |
| INSERT (review_status) | — | GRANTED | Full | Full |
| INSERT (review_notes) | — | GRANTED | Full | Full |
| INSERT (content_version) | — | GRANTED | Full | Full |
| INSERT (approved_by) | — | GRANTED | Full | Full |
| INSERT (reviewed_at) | — | NOT GRANTED | Full | Full (bypasses REVOKE) |
| UPDATE (reviewed_at) | REVOKED | REVOKED | Full | Full (bypasses REVOKE) |
| SELECT | RLS policy | RLS policy | Full | Full |
| DELETE | No policy | No policy | Full | N/A |

### Verification results

| Requirement | Status | Evidence |
|-------------|--------|----------|
| `authenticated` cannot insert `reviewed_at` directly | PASS | `GRANT INSERT (...)` excludes `reviewed_at` (013, lines 227-229) |
| `authenticated` can insert all legitimate review fields | PASS | Column list includes reviewer_id, drug_evidence_id, review_status, review_notes, content_version, approved_by (013, lines 227-229) |
| Table-level INSERT grants don't override column restrictions | PASS | `REVOKE INSERT ON public.content_reviews FROM PUBLIC, authenticated` precedes column-level GRANT (013, lines 227-228) |
| PUBLIC cannot bypass restrictions | PASS | `REVOKE INSERT ... FROM PUBLIC` (013, line 227) |
| anon cannot bypass restrictions | PASS | `REVOKE INSERT ... FROM PUBLIC` covers PUBLIC role (013, line 227) |
| SECURITY DEFINER functions have only necessary privileges | PASS | `aph_correct_reviewed_at()` is SECURITY DEFINER, runs as owner, REVOKE from PUBLIC, GRANT EXECUTE to authenticated (013, lines ~305-310) |
| `reviewer_id = auth.uid()` preserved in RLS | PASS | INSERT policy WITH CHECK includes `reviewer_id = auth.uid()` (010, line 640) |
| `reviewed_at` NOT NULL | PASS | Column definition `reviewed_at TIMESTAMPTZ NOT NULL DEFAULT now()` (006, line 74) |
| `reviewed_at` server-assigned | PASS | `DEFAULT now()` on column; INSERT policy does not reference `reviewed_at` |

### Design assessment

The privilege model is correct:
1. Column-level REVOKE INSERT on `reviewed_at` prevents any client from specifying it
2. Column-level DEFAULT `now()` assigns the timestamp server-side
3. RLS INSERT policy binds `reviewer_id = auth.uid()` preventing identity forgery
4. SECURITY DEFINER `aph_correct_reviewed_at()` provides the only authorized path for timestamp correction, running as table owner (bypassing column-level REVOKE)

---

## AUDIT 3 — Migration Runner

### File inspected
- `backend/scripts/run_migrations.py` (working tree)

### Advisory lock safety

| Aspect | Status | Evidence |
|--------|--------|----------|
| Lock acquired before migration work | PASS | `cur.execute("SELECT pg_advisory_lock(2024011901)")` (line ~178) |
| Lock released after success | PASS | `finally` block calls `pg_advisory_unlock(2024011901)` |
| Lock released after exception | PASS | `finally` block executes regardless of exceptions |
| Lock released after process interruption | PARTIAL | `finally` block handles normal exceptions, but SIGKILL would not release the lock (PostgreSQL releases advisory locks on session termination, so this is actually safe) |
| Same lock key for all runners | PASS | Fixed key `2024011901` |

### Atomicity

| Aspect | Status | Evidence |
|--------|--------|----------|
| Migration DDL + tracking record in same transaction | PASS | `cur.execute(sql)` then `cur.execute(INSERT INTO schema_migrations...)` then `conn.commit()` |
| Failed migration rolled back | PASS | `conn.rollback()` on exception |
| Failure recorded safely | PASS | Separate transaction inserts `success = FALSE` record |
| Failed migration not marked successful | PASS | `success = FALSE` explicitly set |

### Baseline mode safety

| Aspect | Status | Evidence |
|--------|--------|----------|
| Requires explicit `--baseline` flag | PASS | `parser.add_argument("--baseline", action="store_true")` |
| Does not silently mark unknown migrations | PASS | Baseline mode only records all as applied when `--baseline` is explicitly passed |
| Legacy detection based on schema evidence | PASS | Checks `information_schema.tables` for migration-managed tables + `schema_migrations` count == 0 |

### Checksum verification

| Aspect | Status | Evidence |
|--------|--------|----------|
| Checksums compared before skipping | PASS | `if stored_checksum != checksum: ... CHECKSUM MISMATCH` |
| Modified historical migrations cause clear error | PASS | Prints expected vs. actual checksum, halts execution |
| Checksums deterministic | PASS | SHA-256 of file contents |

### Concurrent runner prevention

| Aspect | Status | Evidence |
|--------|--------|----------|
| Advisory lock prevents simultaneous acquisition | PASS | `pg_advisory_lock(2024011901)` blocks second runner |
| Lock released in finally block | PASS | Ensures release even on error |

---

## AUDIT 4 — PostgreSQL Integration Tests

### File inspected
- `backend/scripts/run_postgresql_integration.py` (working tree)

### Test classification

| Test # | Name | Type | Executes SQL? | Tests behavior? |
|--------|------|------|---------------|-----------------|
| 1 | Fresh migrations 001→latest | PostgreSQL integration | YES | YES |
| 2 | Migration tracking bootstrap | PostgreSQL integration | YES | YES |
| 3 | Checksum mismatch rejection | PostgreSQL integration | NO* | PARTIAL** |
| 4 | Legacy baseline validation | PostgreSQL integration | NO* | PARTIAL** |
| 5 | Legitimate content_reviews INSERT | PostgreSQL integration | YES | YES |
| 6 | Forged reviewed_at INSERT rejection | PostgreSQL integration | YES | YES |
| 7 | Forged reviewer_id rejection | PostgreSQL integration | YES | YES |
| 8 | reviewed_at UPDATE rejection | PostgreSQL integration | YES | YES |
| 9 | Custom GUC bypass attempt | PostgreSQL integration | YES | YES |
| 10 | Self-review rejection | PostgreSQL integration | YES | YES |
| 11 | Unauthorized DELETE rejection | PostgreSQL integration | YES | YES |
| 12 | Admin correction authorization | PostgreSQL integration | YES | YES |
| 13 | Atomic audit logging | PostgreSQL integration | YES | YES |
| 14 | Concurrent runner protection | PostgreSQL integration | YES | YES |

\* Tests 3 and 4 do not execute the runner script; they query `schema_migrations` directly.
\*\* Tests 3 and 4 have quality issues (see below).

### Test-quality issues

**Issue TI-3 — Test 3 (checksum mismatch rejection) is tautological:**

```python
if stored != current:
    t.check("Checksum mismatch detected", True, ...)
else:
    t.check("Checksums match", True, ...)
```

Both branches result in PASS. The test never actually verifies that the runner rejects checksum mismatches. It should call the runner with a modified migration file and verify non-zero exit code.

**Issue TI-4 — Test 4 (legacy baseline validation) is weak:**

```python
t.execute("SELECT COUNT(*) FROM public.schema_migrations WHERE success = TRUE")
count = t.cur.fetchone()[0]
t.check("No silent baseline applied (tracking records exist)", count > 0, ...)
```

This only verifies that tracking records exist, which is already guaranteed by test 1. It does not test the runner's legacy detection behavior (refusing to run on a database with tables but no tracking records).

**Issue TI-5 — Test 12 (admin correction authorization) passes a non-existent review ID:**

The admin test calls `aph_correct_reviewed_at('00000000-0000-0000-0000-000000000000', ...)` which will fail with "Review does not exist" AFTER passing the authorization check. The test handles this by accepting non-"Only administrators" errors as PASS, which is technically correct but imprecise.

**Issue TI-6 — Test 13 (atomic audit logging) modifies data persistently:**

Calling `aph_manage_user_role(bob_id, 'editor')` changes bob's role and commits. This could affect other tests if execution order changes.

**Issue TI-7 — No test for `--baseline` mode execution:**

The baseline feature is described but never actually tested against the runner script.

### Test coverage assessment

| Coverage area | Status |
|---------------|--------|
| Fresh migrations execution | COVERED (test 1) |
| Migration tracking bootstrap | COVERED (test 2) |
| Checksum mismatch rejection | WEAK (test 3 is tautological) |
| Legacy baseline validation | WEAK (test 4 doesn't test runner) |
| Legitimate content_reviews INSERT | COVERED (test 5) |
| Forged reviewed_at INSERT rejection | COVERED (test 6) |
| Forged reviewer_id rejection | COVERED (test 7) |
| reviewed_at UPDATE rejection | COVERED (test 8) |
| Custom GUC bypass attempt | COVERED (test 9) |
| Self-review rejection | COVERED (test 10) |
| Unauthorized DELETE rejection | COVERED (test 11) |
| Admin correction authorization | COVERED (test 12) |
| Atomic audit logging | COVERED (test 13) |
| Concurrent runner protection | COVERED (test 14) |

### auth.uid() shim isolation

| Aspect | Status | Evidence |
|--------|--------|----------|
| Test-only file clearly marked | PASS | Header comment: "TEST ONLY... MUST NEVER be applied to production" |
| Function dropped/recreated idempotently | PASS | `DROP FUNCTION IF EXISTS auth.uid()` |
| REVOKE from PUBLIC | PASS | `REVOKE ALL ON FUNCTION auth.uid() FROM PUBLIC` |
| GRANT to authenticated only | PASS | `GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated` |
| Reads `request.jwt.claim.sub` (not client-settable in production) | PASS | `current_setting('request.jwt.claim.sub', true)` |
| Applied via CI step, not in migrations | PASS | CI step: `psql ... -f backend/tests/integration/00_test_auth_uid_shim.sql` |

---

## AUDIT 5 — GitHub Actions

### File inspected
- `.github/workflows/database-readiness.yml` (working tree)

### Workflow verification

| Aspect | Status | Evidence |
|--------|--------|----------|
| PostgreSQL service starts | CONFIGURED | `services.postgres.image: postgres:15-alpine` |
| Health check configured | CONFIGURED | `--health-cmd "pg_isready ..."` |
| Dependencies installed | CONFIGURED | `pip install -r requirements.txt`, `pip install psycopg2-binary` |
| Correct DSN | CONFIGURED | `postgresql://aph_test:aph_test_password@localhost:5432/aph_test_db` |
| Migration execution | CONFIGURED | `python scripts/run_migrations.py --dsn "$DSN"` |
| Integration test execution | CONFIGURED | `python scripts/run_postgresql_integration.py --dsn "$DSN"` |
| Idempotency test | CONFIGURED | Second runner invocation |
| Failure propagation | CONFIGURED | Python scripts exit non-zero on failure |
| No production secrets | PASS | Test credentials only (`aph_test` / `aph_test_password`) |
| auth.uid() shim installed | CONFIGURED | CI step applies shim SQL before tests |
| Cleanup step | CONFIGURED | `DROP SCHEMA public CASCADE; CREATE SCHEMA public;` |

### Runtime execution evidence

**The workflow has NEVER been executed.** No workflow run exists in GitHub Actions for this branch. All CI results are pending.

**Verdict:** CI workflow is correctly configured but unverified. Do not claim any CI success.

---

## AUDIT 6 — Final Report

### Overall verdict: PASS WITH BLOCKERS

### Critical findings — ALL REMEDIATED

| ID | Finding | Status | Location |
|-----|---------|--------|----------|
| C1 | `reviewed_at IS NULL` rejects legitimate inserts | FIXED | `010_rls_and_storage_policies.sql` — removed `AND reviewed_at IS NULL` |
| C2 | Custom GUC bypass via `set_config()` | FIXED | `013_..._compat.sql` — removed GUC trigger and all references |
| C3 | Zero real PostgreSQL integration tests | PARTIAL | Integration tests created but NOT executed |
| C4 | Migration runner can't handle legacy databases | FIXED | `run_migrations.py` — advisory lock, `--baseline`, legacy detection |
| C5 | `auth.uid()` not in plain PostgreSQL | FIXED | `00_test_auth_uid_shim.sql` — test-only shim |

### High findings — ALL REMEDIATED

| ID | Finding | Status | Location |
|-----|---------|--------|----------|
| H1 | `ALTER COLUMN SET NOT NULL` fails on existing NULLs | DOCUMENTED | `013_..._compat.sql` — fails loudly, no data fabrication |
| H2 | FK additions fail on referential integrity violations | DOCUMENTED | `013_..._compat.sql` — fails loudly, no silent data modification |
| H3 | No advisory lock for concurrent runners | FIXED | `run_migrations.py` — `pg_advisory_lock(2024011901)` |
| H4 | CI test roles lack table privileges | FIXED | `run_postgresql_integration.py` — `grant_table_privileges()` |

### Test-quality findings (new in this audit)

| ID | Finding | Severity | Location |
|-----|---------|----------|----------|
| TI-3 | Test 3 is tautological (always passes) | MEDIUM | `run_postgresql_integration.py`, `test_checksum_mismatch_rejection` |
| TI-4 | Test 4 doesn't test runner legacy detection | MEDIUM | `run_postgresql_integration.py`, `test_legacy_baseline_validation` |
| TI-5 | Test 12 uses non-existent review ID | LOW | `run_postgresql_integration.py`, `test_admin_correction_authorization` |
| TI-6 | Test 13 modifies data persistently | LOW | `run_postgresql_integration.py`, `test_atomic_audit_logging` |
| TI-7 | No test for `--baseline` mode execution | LOW | `run_postgresql_integration.py` |

### Historical migration compatibility

| Scenario | Status | Notes |
|----------|--------|-------|
| Fresh database | PASS (design) | Migrations 001→013 apply cleanly |
| Previously deployed (commit 76b599b) | BLOCKED | Checksum mismatch on 010/013 halts runner; operator intervention required |
| Legacy (no tracking records) | BLOCKED | Runner refuses to proceed without --baseline |

### Privilege verification

All INSERT privileges on `content_reviews` are correctly restricted:
- `reviewed_at` excluded from column-level GRANT INSERT
- `REVOKE INSERT FROM PUBLIC, authenticated` precedes GRANT
- `reviewer_id = auth.uid()` in RLS INSERT policy
- `DEFAULT now()` provides server-side timestamp assignment

### Runner safety

| Safety property | Status |
|-----------------|--------|
| Advisory lock acquired/released | PASS |
| Atomic DDL + tracking | PASS |
| Failed migration not marked successful | PASS |
| Checksum mismatch detected | PASS |
| Concurrent runner prevention | PASS |
| Baseline requires explicit flag | PASS |
| Legacy detection based on schema evidence | PASS |

### Integration test quality

| Quality aspect | Status |
|----------------|--------|
| All 14 tests execute real SQL | PASS |
| auth.uid() shim isolated from production | PASS |
| Test identities set per transaction | PASS |
| RLS genuinely enabled and enforced | PASS |
| Tests attempt forbidden operations | PASS |
| Legitimate + forged insert coverage | PASS |
| Role escalation + timestamp modification coverage | PASS |
| Admin correction authorization | PASS |
| Migration bootstrap/checksum/locking coverage | PASS |
| Test 3 tautological | FAIL (quality issue) |
| Test 4 weak | FAIL (quality issue) |

### CI execution evidence

| Aspect | Status |
|--------|--------|
| Workflow configured | PASS |
| Workflow executed | FAIL — never run |
| Runtime validation | PENDING |

---

## Exact Remaining Blockers

| Blocker | Impact | Required action |
|---------|--------|-----------------|
| No PostgreSQL server available | Cannot execute integration tests; cannot verify RLS, triggers, SECURITY DEFINER functions at runtime | Execute CI workflow on a runner with Docker/service containers |
| CI workflow never executed | Cannot claim any CI success | Trigger workflow run on GitHub Actions |
| Test 3 tautological | Checksum mismatch rejection not actually tested | Fix test to call runner with modified migration and verify non-zero exit |
| Test 4 weak | Legacy baseline detection not tested | Fix test to invoke runner on legacy-state database and verify refusal |
| No `--baseline` mode test | Baseline feature untested | Add test invoking runner with `--baseline` on a database with tables but no tracking records |

---

## Sign-off

| Item | Status |
|------|--------|
| C1 — reviewed_at INSERT fix | FIXED (static validated) |
| C2 — GUC bypass removal | FIXED (static validated) |
| C3 — Integration tests | CREATED (not executed) |
| C4 — Migration runner legacy handling | FIXED (static validated) |
| C5 — auth.uid() test shim | CREATED (not executed) |
| H1–H4 — High findings | FIXED / DOCUMENTED |
| TI-3 to TI-7 — Test quality | ISSUES IDENTIFIED |
| PostgreSQL runtime evidence | NONE — never executed |
| CI workflow execution | NONE — never run |
| Phase 03 started | NO |

**Final verdict: PASS WITH BLOCKERS — All CRITICAL findings remediated statically, but no PostgreSQL runtime validation exists. Fix TI-3/TI-4 test quality issues, then execute CI workflow before marking complete.**
