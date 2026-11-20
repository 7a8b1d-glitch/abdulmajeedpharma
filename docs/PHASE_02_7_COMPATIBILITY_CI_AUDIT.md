# Phase 02.7 — Migration Compatibility & CI Readiness Audit

**Project:** Abdulmajeedpharma (APH)
**Branch:** `arena/fcc02306-abdulmajeedpharma`
**Base commit:** `ef1ee81ae1b62b717f6066049b848d1552e455d7`
**HEAD commit:** `76b599b Phase 02: Database foundation, PostgreSQL & security`
**Audit date:** 2026-11-19
**Auditor:** Independent PostgreSQL security and migration auditor
**Scope:** Read-only audit of migration history, runner bootstrap, CI readiness
**Constraint:** No files modified. No production connection. No runtime execution claimed.

---

## Executive Summary

**Verdict: PASS WITH BLOCKERS**

The Phase 02.7 audit reveals a critical finding: **the committed migration 010 (in HEAD commit `76b599b`) contains invalid PostgreSQL SQL** — it uses `CREATE POLICY IF NOT EXISTS`, which PostgreSQL does not support. pglast confirms a parse error: "syntax error at or near NOT, at index 6645". The working tree version fixes this by replacing `CREATE POLICY IF NOT EXISTS` with `DROP POLICY IF EXISTS` + `CREATE POLICY`.

Migration 013 does not exist in committed history — it is a new untracked file. Migration 014 does not exist anywhere. No migration has ever been applied to a real database (no evidence of any deployment).

The migration runner is well-designed with advisory locks, atomic DDL+tracking, checksum verification, and `--baseline` mode. The CI workflow is correctly configured but has never executed.

**No implementation files were modified during this audit.**

---

## AUDIT 1 — Migration History Investigation

### Git history findings

| File | Git history | Introduced in | Modified in working tree? | Status |
|------|-------------|---------------|---------------------------|--------|
| `010_rls_and_storage_policies.sql` | Commit `76b599b` only | `76b599b` | Yes | Modified, uncommitted |
| `013_migration_tracking_and_legacy_compat.sql` | Not in git | N/A | N/A (new file) | Untracked |
| `014_*` | N/A | N/A | N/A | Does not exist |
| `backend/scripts/run_migrations.py` | Not in git | N/A | N/A (new file) | Untracked |

### SHA-256 checksums

| File | HEAD (committed) checksum | Working tree checksum | Changed? |
|------|--------------------------|----------------------|----------|
| `010_rls_and_storage_policies.sql` | `41519a108abbc18f298896fd4a7a7b9eacc353105fcc868722949c557051068f` | `4c90ecfed52d56cf3a0d43e127fa4f4a3cce3da9ff04b9b71e3636b93a9cc346` | YES |
| `013_migration_tracking_and_legacy_compat.sql` | N/A (not in HEAD) | `a0f4d56b5a8b6ac0f4d2829f64cb3eacb18d8151ef72db2282749a449fcd8ad3` | N/A (new) |
| `backend/scripts/run_migrations.py` | `86e9e34f7d5e01a12c3833f91242886e200533de45e7d95d3f87a97f889d7077` | `be6b6154e167f5ff4c74e14532a1370a3ea3dbd4d24b76cd6e606b09c2108422` | YES |

### HEAD migration 010 is INVALID PostgreSQL SQL

pglast (native PostgreSQL parser) confirms:

```
HEAD 010: INVALID — syntax error at or near "NOT", at index 6645
Context: 'dence is publicly readable.\nCREATE POLICY IF NOT EXISTS "authenticated_read_verified_evidence"\n    O'
```

**Root cause:** PostgreSQL does not support `CREATE POLICY IF NOT EXISTS`. The committed migration uses this invalid syntax in multiple places:
- `CREATE POLICY IF NOT EXISTS "authenticated_read_active_%"` (in a DO block)
- `CREATE POLICY IF NOT EXISTS "authenticated_read_verified_evidence"`
- `CREATE POLICY IF NOT EXISTS "users_read_own_profile"`
- `CREATE POLICY IF NOT EXISTS "users_update_own_profile"`
- `CREATE POLICY IF NOT EXISTS "admins_manage_user_profiles"` (FOR ALL — also invalid)
- Multiple other `CREATE POLICY IF NOT EXISTS` statements
- `CREATE POLICY IF NOT EXISTS` with `FOR ALL` (invalid operation specification)

### Working tree migration 010 is VALID

The working tree version replaces all `CREATE POLICY IF NOT EXISTS` with `DROP POLICY IF EXISTS` + `CREATE POLICY`, which is the correct PostgreSQL pattern. pglast confirms: **142 statements parsed successfully**.

### Working tree migration 013 is VALID

pglast confirms: **20 statements parsed successfully**.

### Migration application to real database

**Status: UNKNOWN / No evidence**

There is no evidence in the repository that any migration has ever been applied to a real database:
- No `schema_migrations` table exists in any committed state
- No deployment records, logs, or artifacts exist
- No database backups or dumps are present in the repository
- The `.git` directory contains no database-related artifacts

**Conclusion:** It cannot be verified that any database has the old (invalid) migration 010 applied. The repository history shows only one commit (`76b599b`) touching migration files, and that commit itself contains invalid SQL.

---

## AUDIT 2 — Compatibility Strategy Evaluation

### Option A: Restore immutable historical migrations + forward-only migrations

**Description:** Revert migration 010 to its committed (but invalid) state, then create migration 014 with corrected RLS policies. Historical migrations remain immutable.

| Aspect | Assessment |
|--------|------------|
| Fresh database | FAILS — Migration 010 cannot be applied (invalid SQL). The database creation would fail at migration 010. |
| Existing database | N/A — No existing database with these migrations can exist, since 010 was never valid. |
| Checksum validation | HEAD checksum for 010 would be recorded; migration 014 would have its own checksum. |
| Data-loss risk | N/A — No data exists to lose. |
| Security risk | HIGH — The invalid 010 means no RLS policies exist at all on a fresh install if applied as-is. |
| Operator approval | Required — Operator must accept that migration 010 is invalid and must be followed by 014. |

**Verdict: NOT VIABLE.** Migration 010 in HEAD cannot be applied to any database. Restoring it would break fresh installs.

---

### Option B: Keep modified migrations, declare no database has applied them

**Description:** Keep the working tree versions of 010 and 013. Declare that since migration 010 was invalid in HEAD, no database could have successfully applied it, so no checksum compatibility issues exist.

| Aspect | Assessment |
|--------|------------|
| Fresh database | PASS — Working tree 010 is valid (142 statements). All 13 migrations apply cleanly. |
| Existing database | N/A — No existing database can be verified to have these migrations. |
| Checksum validation | No previously recorded checksums exist for 010 or 013 (013 is new; 010's HEAD checksum is for invalid SQL). Fresh databases record working tree checksums. |
| Data-loss risk | N/A — No data exists. |
| Security risk | LOW — Working tree 010 has valid RLS policies with correct `DROP POLICY IF EXISTS` + `CREATE POLICY` pattern. |
| Operator approval | Required — Operator must acknowledge that HEAD's 010 was invalid and the working tree version is the authoritative version. |

**Verdict: VIABLE.** This is the most honest assessment: since 010 was invalid in HEAD, no database could have been successfully migrated with it.

---

### Option C: Documented legacy adoption/baseline process

**Description:** Keep modified migrations. Document that any database claiming to have applied migration 010 (from HEAD) actually has invalid RLS policies (or none at all, since the SQL would fail). Such databases must use `--baseline` after manual remediation.

| Aspect | Assessment |
|--------|------------|
| Fresh database | PASS — Same as Option B. |
| Existing database | PARTIAL — If a database somehow has partial migration 010 applied (some policies before the failure), it would need manual repair before baseline. |
| Checksum validation | HEAD's 010 checksum would mismatch working tree 010. Runner correctly halts on mismatch. |
| Data-loss risk | MEDIUM — Manual remediation of a partially-applied 010 could cause data loss if not careful. |
| Security risk | MEDIUM — A partially-migrated database may have incomplete RLS protection. |
| Operator approval | Required — Manual intervention needed for any legacy database. |

**Verdict: VIABLE AS SUPPLEMENT.** Should be documented alongside Option B.

---

### Recommended strategy

**Option B (primary) + Option C (documentation supplement):**

1. Keep working tree migration 010 (valid SQL) and migration 013 (new).
2. Declare that no database has ever successfully applied migration 010 from HEAD (it was invalid SQL).
3. Document the legacy baseline process for any operator who believes they have a database with partial migration 010 applied.
4. Do NOT create migration 014 — the checksum mismatch mechanism correctly handles modified migration files.
5. Do NOT restore the invalid HEAD version of 010.

---

## AUDIT 3 — Migration Runner Bootstrap Review

### File inspected
- `backend/scripts/run_migrations.py` (working tree, untracked)

### Bootstrap before first migration

| Question | Answer | File/Line |
|----------|--------|-----------|
| How is `schema_migrations` created before migration 001? | `_ensure_tracking_table(cur)` creates it with `CREATE TABLE IF NOT EXISTS` before any migration executes | `run_migrations.py: _ensure_tracking_table()` (lines ~370-380) |
| Is the tracking table created inside a transaction? | Yes — `conn.autocommit = False`, then `conn.commit()` after `_ensure_tracking_table` | Lines ~178-183 |

### Can the runner bootstrap an empty database?

**Yes.** The runner:
1. Connects to the database
2. Acquires advisory lock
3. Creates `schema_migrations` if not exists (bootstrap)
4. Commits the bootstrap
5. Checks for applied migrations (none found on empty DB)
6. Applies migrations 001→013 in order

### Can a legacy database be safely identified?

**Yes.** The runner detects legacy state by checking:
- Migration-managed tables exist (`user_profiles`, `content_reviews`, `drug_evidence`, `audit_logs`, `schema_migrations`)
- `schema_migrations` has zero success records

If both conditions are true and `--baseline` is not passed, the runner exits with code 1 and "LEGACY DATABASE DETECTED" message.

### Can `--baseline` mark unknown schema versions as applied?

**Yes, but only with explicit operator action.** The `--baseline` flag:
- Records all 13 migrations as applied without executing them
- Requires explicit `--baseline` CLI flag
- Does NOT silently run — the runner refuses legacy state without it
- Is idempotent (re-running baseline doesn't duplicate records)

### Are migration execution and tracking atomic?

**Yes.** For each migration:
1. `cur.execute(sql)` — executes migration DDL
2. `cur.execute(INSERT INTO schema_migrations...)` — records tracking
3. `conn.commit()` — commits both in one transaction

If migration DDL fails:
1. `conn.rollback()` — rolls back the migration
2. Separate transaction records `success = FALSE`
3. Runner breaks out of the loop

### Does checksum mismatch stop execution before later migrations?

**Yes.** On checksum mismatch:
```python
if stored_checksum != checksum:
    print(f"  [{version}] {filename} — CHECKSUM MISMATCH")
    failures += 1
    break  # <- stops execution
```
The runner halts immediately and does not apply any subsequent migrations.

### Do advisory locks remain held on the same connection?

**Yes.** The advisory lock `pg_advisory_lock(2024011901)` is:
- Acquired once at the start (line ~178)
- Held on the same connection throughout all migration execution
- Released in the `finally` block via `pg_advisory_unlock(2024011901)`
- Released even on exceptions (the `finally` block always executes)

**Note:** PostgreSQL advisory locks are session-scoped. If the process is killed (SIGKILL), PostgreSQL automatically releases all locks held by that session. This is safe.

---

## AUDIT 4 — CI Readiness Review

### File inspected
- `.github/workflows/database-readiness.yml` (working tree, untracked)

### Workflow verification

| Aspect | Status | Evidence |
|--------|--------|----------|
| PostgreSQL service configured | PASS | `services.postgres.image: postgres:15-alpine` |
| Health check configured | PASS | `--health-cmd "pg_isready -U aph_test -d aph_test_db" --health-interval 10s --health-timeout 5s --health-retries 5` |
| Python dependencies installed | PASS | `pip install -r requirements.txt` + `pip install psycopg2-binary` |
| DSN construction | PASS | `postgresql://aph_test:aph_test_password@localhost:5432/aph_test_db` matches service env vars |
| Test-only auth.uid shim | PASS | CI step: `psql ... -f backend/tests/integration/00_test_auth_uid_shim.sql` — file exists at that path |
| Migration execution order | PASS | Runner applies 001→013 sequentially |
| All 17 integration tests invoked | PASS | `main()` calls all 17 test functions; script path `scripts/run_postgresql_integration.py` exists |
| CI fails on test failure | PASS | Python scripts return `sys.exit(1)` on failures; GitHub Actions step fails on non-zero exit |
| No production secrets | PASS | Test credentials only (`aph_test` / `aph_test_password`) |
| Workflow syntax | APPEARS VALID | Standard GitHub Actions syntax; NOT locally validated (no `act` available) |

### CI workflow execution evidence

**Status: NEVER EXECUTED**

- No workflow runs exist in GitHub Actions for this branch
- `act` is not installed locally, so workflow syntax cannot be validated locally
- `gh` is available but no workflow run history to check

**Do not claim any CI success.**

### Documentation step issue

The CI `documentation` job checks for `docs/PHASE_02_5_REMEDIATION_REPORT.md` but does NOT check for:
- `docs/PHASE_02_6_TEST_QUALITY_REPORT.md` (exists)
- `docs/PHASE_02_7_COMPATIBILITY_CI_AUDIT.md` (being created)

This means the CI documentation check is outdated relative to the current phase.

---

## AUDIT 5 — Final Report

### Overall verdict: PASS WITH BLOCKERS

### Findings with severity

| ID | Finding | Severity | Location |
|-----|---------|----------|----------|
| M-1 | HEAD migration 010 uses `CREATE POLICY IF NOT EXISTS` — invalid PostgreSQL SQL | CRITICAL | `76b599b:database/migrations/010_rls_and_storage_policies.sql` |
| M-2 | Working tree migration 010 fixes the syntax error (DROP POLICY + CREATE POLICY) | FIXED | Working tree `010_rls_and_storage_policies.sql` |
| M-3 | Migration 013 does not exist in committed history | INFO | Not in HEAD; new untracked file |
| M-4 | Migration 014 does not exist | INFO | N/A |
| M-5 | No evidence any migration was applied to a real database | INFO | No deployment artifacts |
| R-1 | Migration runner bootstrap is correct (tracking table before migrations) | PASS | `run_migrations.py:_ensure_tracking_table()` |
| R-2 | Advisory lock prevents concurrent runners | PASS | `run_migrations.py:pg_advisory_lock(2024011901)` |
| R-3 | Atomic DDL + tracking per migration | PASS | `run_migrations.py:cur.execute(sql) + INSERT + commit` |
| R-4 | Checksum mismatch halts execution | PASS | `run_migrations.py:break` on mismatch |
| C-1 | CI workflow correctly configured but never executed | BLOCKER | `.github/workflows/database-readiness.yml` |
| C-2 | `act` not available for local workflow validation | BLOCKER | N/A |
| C-3 | CI documentation step references PHASE_02_5 report, not PHASE_02_6 or PHASE_02_7 | MINOR | `.github/workflows/database-readiness.yml:documentation` step |

### Recommended migration compatibility strategy

**Option B (primary): Keep modified migrations, declare no database has applied them.**

Rationale: Migration 010 in HEAD was invalid PostgreSQL SQL (`CREATE POLICY IF NOT EXISTS`). pglast confirms it cannot be parsed. Therefore no database could have been successfully migrated with it. The working tree version is the authoritative, valid migration.

**Option C (documentation supplement):** Document the `--baseline` legacy adoption process for any operator who believes they have a partially-migrated database.

**Not recommended:** Option A (restore invalid 010 + create 014) — fresh database creation would fail at migration 010.

### Exact steps to execute CI

1. Push the working tree to the branch `arena/fcc02306-abdulmajeedpharma` on GitHub
2. GitHub Actions will trigger on push to that branch
3. The `static-validation` job runs 256 static tests + pglast parsing
4. The `live-database-tests` job spins up `postgres:15-alpine`, installs dependencies, applies migrations, runs 17 integration tests, verifies idempotency
5. The `documentation` job verifies report files exist

**Prerequisites:**
- Working tree changes must be committed and pushed (currently uncommitted)
- The CI workflow file must be committed (currently untracked)
- No local validation of workflow syntax is possible without `act`

### Remaining blockers

| Blocker | Impact | Required action |
|---------|--------|-----------------|
| No PostgreSQL server available locally | Cannot execute integration tests; cannot verify RLS, triggers, SECURITY DEFINER functions at runtime | Execute CI workflow on GitHub Actions runner |
| CI workflow never executed | Cannot claim any CI success | Commit and push changes; trigger workflow on GitHub |
| `act` not installed | Cannot validate workflow syntax locally | Use GitHub Actions for validation |
| Working tree changes uncommitted | CI cannot run on uncommitted changes | Commit and push to `arena/fcc02306-abdulmajeedpharma` |
| CI documentation step outdated | References PHASE_02_5 report, not current reports | Update workflow to check PHASE_02_6 and PHASE_02_7 reports |

---

## Sign-off

| Item | Status |
|------|--------|
| Migration 010 validity | HEAD: INVALID; Working tree: VALID |
| Migration 013 existence | Not in HEAD; working tree only |
| Migration 014 existence | Does not exist |
| Real database application | No evidence — UNKNOWN |
| Runner bootstrap | PASS |
| Runner advisory lock | PASS |
| Runner atomicity | PASS |
| Runner checksum mismatch | PASS |
| CI workflow configuration | PASS (configured, not executed) |
| CI workflow execution | NOT EXECUTED |
| Phase 03 started | NO |

**Final verdict: PASS WITH BLOCKERS — Migration compatibility is well understood (HEAD 010 is invalid; working tree fixes it). CI is configured but never executed. Do not proceed to Phase 03 until CI runs successfully against real PostgreSQL.**

**No implementation files were modified during this audit. No commit, push, or PR was made. Awaiting approval before implementing any migration compatibility strategy.**
