# Phase 02.4 — Independent PostgreSQL Security and Migration Audit

**Project:** Abdulmajeedpharma (APH)
**Branch:** `arena/fcc02306-abdulmajeedpharma`
**Base commit:** `ef1ee81ae1b62b717f6066049b848d1552e455d7`
**Audit date:** 2026-11-19
**Auditor:** Independent senior PostgreSQL database auditor
**Scope:** Phase 02.4 implementation (migrations 006, 010, 012, 013; runner script; CI workflow; tests)
**Constraint:** No files were modified during this audit. No live PostgreSQL instance is available.

---

## Executive Summary

**Verdict: FAIL**

The Phase 02.4 implementation contains **CRITICAL** design flaws that prevent legitimate database operation and undermine timestamp security. The most severe finding is that the `reviewed_at IS NULL` condition in the content_reviews INSERT RLS policy (migration 010) will reject ALL legitimate reviewer inserts because PostgreSQL applies column defaults before evaluating RLS WITH CHECK clauses. Additionally, the custom GUC `aph.allow_reviewed_at_change` (migration 013) can be set by any authenticated user, creating a bypass path for the reviewed_at immutability trigger if column-level privileges are ever circumvented. The migration runner lacks advisory locking and cannot safely handle legacy databases without pre-existing tracking records. No real PostgreSQL integration tests exist — all 254 tests are static text or Python unit tests that cannot detect runtime failures.

**No PostgreSQL runtime testing has been performed.** The CI workflow is configured but unverified.

---

## AUDIT 1 — reviewed_at INSERT POLICY

### Files inspected
- `database/migrations/006_users_and_permissions.sql` — line 74
- `database/migrations/010_rls_and_storage_policies.sql` — lines ~625-649
- `database/migrations/013_migration_tracking_and_legacy_compat.sql` — lines ~217-243, 247-266, 310
- `database/migrations/012_review_trigger.sql` — full file

### Column definition (migration 006, line 74)

```sql
reviewed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
```

### INSERT RLS policy (migration 010, lines 625-649)

```sql
CREATE POLICY "reviewers_manage_content_reviews_insert"
    ON public.content_reviews
    FOR INSERT TO authenticated
    WITH CHECK (
        reviewer_id = auth.uid()
        AND EXISTS (...)
        AND reviewed_at IS NULL
        AND NOT EXISTS (...)
    );
```

### CRITICAL FINDING A1-1: Legitimate reviewer INSERTs will be rejected

PostgreSQL applies column defaults **before** evaluating RLS WITH CHECK clauses. When a reviewer inserts a row without specifying `reviewed_at`:

1. The column DEFAULT `now()` is applied → `reviewed_at` becomes `2026-11-19T00:00:00Z` (non-NULL)
2. RLS WITH CHECK evaluates `reviewed_at IS NULL` → **FALSE**
3. **INSERT is rejected**

**Consequence:** No legitimate reviewer can ever insert a content_reviews row. The policy blocks the very operation it is meant to permit.

**Reproducing the failure (conceptual, no live DB available):**

```sql
-- Reviewer attempts to insert a review (legitimate operation)
INSERT INTO public.content_reviews (reviewer_id, drug_evidence_id, review_status)
VALUES ('reviewer-uuid', 'evidence-uuid', 'draft');
-- Result: RLS policy rejects because reviewed_at IS NULL is FALSE
-- (DEFAULT now() already set reviewed_at to a non-NULL timestamp)
```

The only way to pass the `reviewed_at IS NULL` check is to explicitly set `reviewed_at = NULL` in the INSERT, but:
- The column is `NOT NULL` → column constraint violation
- Even if it worked, the reviewer could instead set `reviewed_at = '2020-01-01'` to forge a timestamp, which would also pass the `IS NULL` check (since the value is non-NULL)

### Triggers affecting content_reviews

| Trigger | Migration | Event | Purpose |
|---------|-----------|-------|---------|
| `trg_content_reviews_updated_at` | 006 | BEFORE UPDATE | Sets `updated_at` via `set_updated_at()` |
| `trg_content_reviews_no_self_review` | 012 | BEFORE INSERT OR UPDATE | Prevents self-review (references `NEW.*`) |
| `trg_content_reviews_reviewed_at_immutable` | 013 | BEFORE UPDATE OF reviewed_at | Blocks direct `reviewed_at` changes |

Note: `trg_content_reviews_no_self_review` references `NEW.drug_evidence_id` and `NEW.reviewer_id` — this is valid in a trigger (unlike RLS policies). No OLD/NEW references appear in any RLS policy expression (verified).

### CRITICAL FINDING A1-2: The `reviewed_at IS NULL` check is logically incompatible with `DEFAULT now()`

The design intent is sound (server assigns the timestamp), but the implementation is self-contradictory:
- Column DEFAULT assigns a non-NULL value on insert
- RLS policy requires the value to be NULL
- These cannot both be true at RLS evaluation time

### Secure design proposal for reviewed_at

**Option A: Remove `reviewed_at IS NULL` from INSERT policy (RECOMMENDED)**

```sql
-- Migration 010 INSERT policy — corrected
CREATE POLICY "reviewers_manage_content_reviews_insert"
    ON public.content_reviews
    FOR INSERT TO authenticated
    WITH CHECK (
        reviewer_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid()
              AND up.role IN ('scientific_reviewer','administrator')
        )
        -- REMOVE: AND reviewed_at IS NULL  -- defaults fire before RLS evaluation
        AND NOT EXISTS (
            SELECT 1 FROM public.drug_evidence de
            WHERE de.id = content_reviews.drug_evidence_id
              AND de.created_by = auth.uid()
        )
    );
```

**Rationale:** The column `DEFAULT now()` already guarantees server-assigned timestamps. Column-level `REVOKE UPDATE (reviewed_at)` prevents modification after insert. The trigger `assert_reviewed_at_immutable` provides defense in depth. The `IS NULL` check is unnecessary and harmful.

**Option B: Make `reviewed_at` nullable with a CHECK constraint**

```sql
-- Column: reviewed_at TIMESTAMPTZ DEFAULT now()  (nullable)
-- Constraint: CHECK (reviewed_at IS NOT NULL)  -- enforced after insert
```

This is less clean than Option A and requires careful ordering of constraint validation vs. default application.

**Option C: Remove the INSERT policy's `reviewed_at IS NULL` and rely solely on column-level REVOKE + trigger**

This is equivalent to Option A but explicitly documents that protection comes from column-level privileges and the immutable trigger, not from the INSERT policy.

### Summary of A1

| Requirement | Status |
|-------------|--------|
| Database assigns reviewed_at | PASS (DEFAULT now()) |
| Clients cannot forge/backdate | PARTIAL (INSERT policy blocks explicit values but rejects legitimate inserts) |
| Legitimate reviewer inserts succeed | FAIL (IS NULL check rejects all inserts) |
| Reviewer identity bound to auth.uid() | PASS (reviewer_id = auth.uid() in INSERT and UPDATE policies) |
| No OLD/NEW in RLS expressions | PASS |

---

## AUDIT 2 — Custom GUC / SET LOCAL Bypass

### Files inspected
- `database/migrations/013_migration_tracking_and_legacy_compat.sql` — lines ~217-310

### GUC name found in repository

`aph.allow_reviewed_at_change` — used in:
- `assert_reviewed_at_immutable()` trigger (line 247-248): checks `current_setting('aph.allow_reviewed_at_change', true)`
- `aph_correct_reviewed_at()` function (line 310): `SET LOCAL aph.allow_reviewed_at_change = 'true'`

### Trigger function (lines 217-248)

```sql
IF OLD.reviewed_at IS DISTINCT FROM NEW.reviewed_at THEN
    IF current_setting('aph.allow_reviewed_at_change', true) IS NULL
       OR current_setting('aph.allow_reviewed_at_change', true) <> 'true' THEN
        RAISE EXCEPTION 'reviewed_at cannot be modified directly...';
    END IF;
END IF;
```

### Correction function (lines 286-310)

```sql
SET LOCAL aph.allow_reviewed_at_change = 'true';

UPDATE public.content_reviews
SET reviewed_at = corrected_at, updated_at = now()
WHERE id = review_id;
```

### CRITICAL FINDING A2-1: Any authenticated user can set the bypass GUC

An ordinary authenticated user can execute:

```sql
SELECT set_config('aph.allow_reviewed_at_change', 'true', true);
```

This sets the GUC for the current session/transaction. If the user also has UPDATE privilege on the `reviewed_at` column, they can then modify `reviewed_at` directly and the trigger will permit it because `current_setting(...)` returns `'true'`.

**However**, the column-level `REVOKE UPDATE (reviewed_at) ON public.content_reviews FROM authenticated` (migration 013, lines 217-218) prevents authenticated users from updating the column at all. The trigger is therefore a secondary defense-in-depth measure.

**Classification:** The GUC bypass is not directly exploitable due to the column-level REVOKE, but it is a **design weakness** that would become CRITICAL if:
- The column-level REVOKE is removed or not applied
- A superuser or table owner executes the UPDATE (bypassing both column-level privileges and RLS)
- The SECURITY DEFINER function's `SET LOCAL` is intercepted or the GUC is set before calling the function

### SECURITY DEFINER function privilege model

`aph_correct_reviewed_at()` is `SECURITY DEFINER`, meaning it runs as the function owner (typically `postgres` or the Supabase admin). The table owner bypasses:
- Column-level privileges (REVOKE does not apply to the owner)
- RLS policies (owners bypass RLS unless FORCE RLS is enabled)

Since `content_reviews` does NOT have `FORCE ROW LEVEL SECURITY` (confirmed in migration 010 — FORCE RLS is only on user_profiles, conversations, conversation_participants, messages, message_read_receipts, notifications), the table owner can bypass RLS entirely.

### Secure alternative

**Remove the GUC mechanism entirely.** Since `aph_correct_reviewed_at()` is SECURITY DEFINER, it runs as the table owner and bypasses column-level privileges. The trigger `assert_reviewed_at_immutable` would still block the UPDATE unless the GUC is set — but the GUC is the only way to allow it, and it's user-settable.

**Recommended fix:** Drop the `assert_reviewed_at_immutable` trigger entirely and rely on:
1. Column-level `REVOKE UPDATE (reviewed_at) FROM PUBLIC, authenticated` — prevents non-owners from modifying the column
2. SECURITY DEFINER `aph_correct_reviewed_at()` — runs as owner, bypasses column-level REVOKE, can update `reviewed_at` directly
3. Audit logging inside the SECURITY DEFINER function

This eliminates the user-settable GUC bypass vector entirely.

**Alternative if trigger is required:** Replace the user-settable GUC with a mechanism that cannot be set by ordinary clients, such as:
- Checking `pg_backend_pid()` against a registered admin session
- Using a temporary table that only the SECURITY DEFINER function can write to
- Simply not having a trigger at all (column-level REVOKE is sufficient)

### Summary of A2

| Requirement | Status |
|-------------|--------|
| Custom GUC cannot be set by ordinary users | FAIL — `set_config('aph.allow_reviewed_at_change', 'true', true)` works for any session |
| Column-level REVOKE provides actual enforcement | PASS — `REVOKE UPDATE (reviewed_at) FROM authenticated` |
| SECURITY DEFINER correction function works | PASS (but depends on GUC) |
| No bypass path when column-level REVOKE is in place | PASS (REVOKE blocks before trigger fires) |
| Bypass becomes active if REVOKE removed | CRITICAL risk |

---

## AUDIT 3 — Migration Runner Bootstrap

### File inspected
- `backend/scripts/run_migrations.py` — full file
- `database/migrations/013_migration_tracking_and_legacy_compat.sql` — full file

### Bootstrap flow

1. Runner connects to database
2. `_ensure_tracking_table(cur)` creates `schema_migrations` with `CREATE TABLE IF NOT EXISTS` (line ~290)
3. Runner commits the bootstrap table creation
4. Runner queries `schema_migrations` for already-applied versions
5. Runner iterates through migrations in order (001→013)
6. For each migration: executes SQL, inserts tracking record, commits
7. On failure: rolls back migration, inserts failure record, commits, breaks

### FINDING A3-1: Tracking table bootstrapped before migration 013

`_ensure_tracking_table` creates `schema_migrations` before any migration runs. Migration 013 then executes `CREATE TABLE IF NOT EXISTS public.schema_migrations` which is a no-op (table already exists). This works functionally but means:

- The tracking table exists before migration 013 is "applied"
- Migration 013's own SQL does not insert itself into `schema_migrations` — the runner does this after execution
- If migration 013's SQL fails, the tracking table still exists (bootstrapped separately) but migration 013 is recorded as failed

### FINDING A3-2: Failed migration recording

On migration failure, the runner:
1. Rolls back the migration SQL transaction
2. Attempts to insert a `success = FALSE` record into `schema_migrations`
3. Commits the failure record
4. Breaks out of the loop

This works correctly — the failure is recorded and the runner stops.

### FINDING A3-3: Resume after interruption

If the runner is interrupted mid-sequence:
- Already-applied migrations are skipped (checksum verified)
- The runner continues from the first unapplied migration
- Each migration is committed individually (`conn.commit()` after each)

**This works correctly for resumption.**

### FINDING A3-4: No advisory lock for concurrent runners

The runner does not use `pg_advisory_lock` or any equivalent mechanism. Two concurrent runner instances could:
- Both read the same set of unapplied migrations
- Both attempt to apply the same migration
- One succeeds, the other fails with duplicate object errors (most migrations use IF NOT EXISTS, but some DDL may not be idempotent)

**Gap:** No concurrency protection.

### FINDING A3-5: Checksums compared before skipping

When a migration is already in `schema_migrations` with `success = TRUE`, the runner compares the stored checksum against the current file's checksum. If they differ, the runner reports CHECKSUM MISMATCH and halts.

**This works correctly** — edited historical migrations are detected.

### FINDING A3-6: Legacy databases without tracking records

If a database has migrations applied manually (without the runner), `schema_migrations` will be empty. The runner will attempt to apply ALL migrations from 001:

- Most migrations use `IF NOT EXISTS` / `ADD COLUMN IF NOT EXISTS` / `ON CONFLICT DO NOTHING` — these are idempotent
- However, some statements may not be idempotent (e.g., plain `ALTER TABLE ... ADD COLUMN` without `IF NOT EXISTS`, plain `CREATE INDEX` without `IF NOT EXISTS`)
- Migration 013 has prerequisite checks: `user_profiles` must exist, `drug_evidence.created_by` must exist — these will pass on a fully migrated legacy database
- **Critical gap:** `ALTER TABLE public.content_reviews ALTER COLUMN reviewed_at SET NOT NULL` will FAIL if any existing rows have NULL `reviewed_at`

**Legacy databases without tracking records cannot be safely migrated by this runner.**

### FINDING A3-7: Migration 013 records its own execution

Migration 013's SQL does NOT insert itself into `schema_migrations`. The runner inserts the tracking record after the SQL executes successfully. This is by design (to avoid circular dependencies — the table is created by migration 013 itself, but the runner bootstraps it separately).

**This works but is architecturally awkward:** the bootstrap table creation in `_ensure_tracking_table` duplicates the table definition in migration 013. If the two definitions diverge, inconsistencies arise.

### Summary of A3

| Requirement | Status |
|-------------|--------|
| schema_migrations bootstrapped before migration 001 | PASS (via `_ensure_tracking_table`) |
| Migration 013 records its own execution | PASS (runner inserts after SQL execution) |
| Failed migration recorded safely | PASS (separate transaction after rollback) |
| Resume after interruption | PASS (individual commits + skip logic) |
| Transactions used correctly | PASS (per-migration transactions) |
| DDL + tracking atomic per migration | PASS (same transaction) |
| Concurrent runner prevention | FAIL — no advisory lock |
| Checksums compared before skipping | PASS |
| Edited historical migration detection | PASS (CHECKSUM MISMATCH halt) |
| Legacy databases without tracking records | FAIL — runner attempts all migrations from 001 |

---

## AUDIT 4 — Legacy Migration Compatibility

### File inspected
- `database/migrations/013_migration_tracking_and_legacy_compat.sql` — full file (legacy section: lines 92-174)

### Legacy compatibility logic (migration 013, lines 92-174)

The `DO $$` block:
1. Checks if `content_reviews` exists
2. Adds missing FK constraints (reviewer_id, drug_evidence_id, approved_by)
3. `ALTER COLUMN reviewed_at SET NOT NULL`
4. `ALTER COLUMN reviewed_at SET DEFAULT now()`
5. Adds missing columns (content_version, review_notes)
6. Creates indexes with `IF NOT EXISTS`
7. Ensures `trg_content_reviews_updated_at` exists
8. Validates `user_profiles` exists
9. Validates `drug_evidence.created_by` exists

### FINDING A4-1: Existing NULL reviewed_at values will cause failure

`ALTER TABLE public.content_reviews ALTER COLUMN reviewed_at SET NOT NULL` (line ~158) will fail with:

```
ERROR:  column "reviewed_at" contains null values
```

if any existing rows have NULL `reviewed_at`. There is no check for existing NULL values before attempting the NOT NULL constraint. No fabricated dates are assigned — the migration simply fails.

**This is correct behavior (no data fabrication), but it means legacy databases with NULL reviewed_at cannot be upgraded without manual data remediation.**

### FINDING A4-2: Existing data violations will block FK additions

`ADD CONSTRAINT fk_content_reviews_reviewer FOREIGN KEY (reviewer_id) REFERENCES public.user_profiles (user_id)` will fail if any existing `reviewer_id` value does not exist in `user_profiles.user_id`. Same for `drug_evidence_id` and `approved_by`.

No data validation or cleanup is performed before adding constraints.

### FINDING A4-3: Duplicate indexes and triggers are safe

- Indexes use `CREATE INDEX IF NOT EXISTS` — safe on reapplication
- Trigger uses `IF NOT EXISTS` check via `pg_trigger` query — safe on reapplication
- Table uses `CREATE TABLE IF NOT EXISTS` — safe on reapplication
- All ALTER operations are guarded by `IF NOT EXISTS` checks — safe on reapplication

### FINDING A4-4: Repeated execution is safe

Migration 013 can be applied repeatedly without error (assuming the initial application succeeds). All DDL is idempotent.

### FINDING A4-5: Old migration checksums not handled

Migration 013 does not reference or validate checksums of previous migrations (001-012). Checksum validation is handled by the runner script, not by the migration SQL itself.

### FINDing A4-6: Fresh install vs legacy upgrade

| Scenario | Path | Result |
|----------|------|--------|
| Fresh install | 001→013 in order | content_reviews created correctly in 006; 013 adds tracking + protection |
| Legacy 001-011 DB | Apply 012, then 013 | 013 repairs content_reviews schema; may fail on data integrity issues |
| Partially applied DB | Runner skips applied, applies missing | Works if tracking records exist; fails if no tracking records |

### Summary of A4

| Requirement | Status |
|-------------|--------|
| Existing data preserved | PASS (additive changes only) |
| No fabricated dates for NULL reviewed_at | PASS (migration fails rather than fabricating) |
| Existing reviewer IDs checked before FK | FAIL — no data validation; FK addition fails on violations |
| Duplicate indexes/triggers not created | PASS (IF NOT EXISTS / existence checks) |
| Repeated execution safe | PASS |
| Old migration checksums handled | FAIL — not in migration SQL (runner handles it) |
| Fresh install and legacy upgrade reach same schema | PARTIAL — legacy path may fail on data issues |

---

## AUDIT 5 — GitHub Actions Workflow

### File inspected
- `.github/workflows/database-readiness.yml` — full file

### FINDING A5-1: Workflow not actually executed

No PostgreSQL server is available in this environment. The workflow has **never been run**. It is configured but unverified.

### FINDING A5-2: `auth.uid()` is Supabase-specific, not standard PostgreSQL

The RLS test step (lines ~115-155) attempts to test RLS with roles like `reviewer_alice`, `reviewer_bob`, etc. However, `auth.uid()` is a **Supabase-specific function** provided by the `supabase` extension. A plain `postgres:15-alpine` container does NOT have this function.

When the RLS test step attempts:
```sql
SET ROLE reviewer_alice;
INSERT INTO public.content_reviews (...) VALUES (...);
```

PostgreSQL will evaluate RLS policies that reference `auth.uid()`, which will fail with:
```
ERROR:  function auth.uid() does not exist
```

The workflow needs to either:
- Install the Supabase PostgreSQL extension in the container
- Use a different RLS testing approach that doesn't depend on `auth.uid()`
- Mock `auth.uid()` as a custom function

### FINDING A5-3: RLS test INSERT will fail for legitimate inserts too

The test attempts to insert with a forged `reviewed_at`:
```sql
INSERT INTO public.content_reviews (reviewer_id, drug_evidence_id, review_status, reviewed_at)
VALUES ('...', '...', 'draft', '2020-01-01T00:00:00Z');
```

But as found in AUDIT 1, even a legitimate INSERT without `reviewed_at` would be rejected by the `reviewed_at IS NULL` check. The test is testing the wrong thing — it tests forgery prevention but doesn't test that legitimate inserts succeed.

### FINDING A5-4: No table privileges granted to test roles

The test roles (`reviewer_alice`, etc.) are created but only `GRANT USAGE ON SCHEMA public` is given. No `GRANT SELECT/INSERT/UPDATE` on tables. RLS policies only apply when the user has some table privilege; without table-level grants, the roles can't access any tables at all. The test would fail with "permission denied" before RLS is even evaluated.

### FINDING A5-5: Database URL is correct

`postgresql://aph_test:aph_test_password@localhost:5432/aph_test_db` matches the service container environment variables. PASS.

### FINDING A5-6: Python dependencies installed

`psycopg2-binary` is installed in the live-database-tests job. PASS.

### FINDING A5-7: All migrations executed in order

The runner applies migrations 001→013 sequentially. PASS (in design, unverified at runtime).

### FINDING A5-8: CI fails on failures

The runner exits with code 1 on failure. `set -e` is not explicitly used but the Python script returns non-zero. PASS.

### FINDING A5-9: No production secrets

The workflow uses test credentials (`aph_test` / `aph_test_password`). PASS.

### FINDING A5-10: Workflow syntax appears valid

Standard GitHub Actions syntax. PASS (unverified).

### Cleanup step issue

The cleanup step runs `DROP SCHEMA public CASCADE; CREATE SCHEMA public;` which drops the `schema_migrations` table along with everything else. This is fine for a test database but means no state persists between runs (which is the intent).

### Summary of A5

| Requirement | Status |
|-------------|--------|
| PostgreSQL service starts and becomes healthy | UNVERIFIED (workflow not run) |
| Correct DSN passed to runner | PASS |
| Python dependencies installed | PASS |
| All migrations executed in order | PASS (design) |
| RLS tests use appropriate roles | PARTIAL — roles created but no table grants; `auth.uid()` not available in plain PostgreSQL |
| Tests verify actual DB behavior | PARTIAL — RLS test cannot work without `auth.uid()` extension |
| CI fails on migration/security failures | PASS (design) |
| No production secrets | PASS |
| Workflow syntax valid | PASS (unverified) |
| Workflow actually executed | FAIL — never run |

---

## AUDIT 6 — Test Quality

### Test classification

| Category | Count | Examples |
|----------|-------|----------|
| Static text tests (regex on SQL) | ~52 | `test_reviewer_id_bound_to_auth_uid_on_insert`, `test_manage_user_role_execute_granted_to_authenticated`, etc. |
| SQL grammar tests (pglast parsing) | 13 | `test_migration_parses_with_postgresql_grammar` (parametrized, 13 migrations) |
| Python unit tests | ~13 | `test_sqlalchemy_models_match_tables`, `test_backend_app_imports`, `test_uuid_primary_keys`, etc. |
| Real PostgreSQL integration tests | 0 | None exist |

Total test functions: 65
Total test cases executed: 254 (including parametrized cases)

### Tests that cannot detect critical failures

| Failure mode | Can tests detect? | Why not |
|-------------|-------------------|---------|
| `reviewed_at IS NULL` rejects legitimate inserts | NO | All tests are static text; no runtime INSERT is attempted |
| Custom GUC bypass via `set_config` | NO | No test checks GUC behavior |
| Migration runner bootstrap failure | NO | Dry-run only; no live DB execution |
| Legacy migration checksum mismatch | PARTIAL | Dry-run checks file checksums, not runtime DB state |
| `auth.uid()` not available in plain PostgreSQL | NO | No runtime RLS testing |
| Column-level REVOKE not enforced | NO | Static text test only checks SQL text exists |

### FINDING A6-1: Zero integration tests

There are **zero** real PostgreSQL integration tests. All 254 passing tests validate SQL text structure, not runtime behavior. A database could be completely broken at runtime and all tests would still pass.

### FINDING A6-2: The `test_insert_policy_blocks_reviewed_at_forgery` test passes despite the policy being broken

This test checks that `AND reviewed_at IS NULL` appears in the INSERT policy WITH CHECK clause. It passes because the text is present. But as shown in AUDIT 1, this text is precisely what makes the policy reject legitimate inserts. The test validates the presence of a self-defeating condition.

---

## AUDIT 7 — Final Report

### Overall verdict: FAIL

The Phase 02.4 implementation cannot support legitimate database operations and contains critical security design weaknesses. **No PostgreSQL runtime testing has been performed.**

---

### CRITICAL Findings

| ID | Finding | Severity | Location |
|----|---------|----------|----------|
| C1 | `reviewed_at IS NULL` in INSERT RLS policy rejects ALL legitimate inserts because PostgreSQL applies column DEFAULT before RLS WITH CHECK evaluation | CRITICAL | `database/migrations/010_rls_and_storage_policies.sql`, lines ~646-648 |
| C2 | Custom GUC `aph.allow_reviewed_at_change` can be set by any authenticated user via `set_config()`, creating a bypass path for the reviewed_at immutability trigger | CRITICAL | `database/migrations/013_migration_tracking_and_legacy_compat.sql`, lines 247-248, 310 |
| C3 | No real PostgreSQL integration tests exist — all 254 tests are static text or Python unit tests | CRITICAL | `backend/tests/test_database_schema.py` |
| C4 | Migration runner cannot handle legacy databases without pre-existing tracking records | CRITICAL | `backend/scripts/run_migrations.py`, `apply_migrations()` |
| C5 | `auth.uid()` is Supabase-specific and will not work in plain PostgreSQL CI container | CRITICAL | `.github/workflows/database-readiness.yml`, RLS test step |

### HIGH Findings

| ID | Finding | Severity | Location |
|----|---------|----------|----------|
| H1 | `ALTER COLUMN reviewed_at SET NOT NULL` fails if any existing rows have NULL reviewed_at; no data validation before constraint addition | HIGH | `database/migrations/013_migration_tracking_and_legacy_compat.sql`, line ~158 |
| H2 | FK constraint additions fail if existing data violates referential integrity; no data validation | HIGH | `database/migrations/013_migration_tracking_and_legacy_compat.sql`, lines 100-135 |
| H3 | No advisory lock to prevent concurrent migration runners | HIGH | `backend/scripts/run_migrations.py`, `apply_migrations()` |
| H4 | CI RLS test creates roles but grants no table privileges — roles cannot access tables | HIGH | `.github/workflows/database-readiness.yml`, RLS test step |

### MEDIUM Findings

| ID | Finding | Severity | Location |
|----|---------|----------|----------|
| M1 | Migration 013 does not reference old migration checksums (checksum validation is runner-only) | MEDIUM | `database/migrations/013_migration_tracking_and_legacy_compat.sql` |
| M2 | Bootstrap table definition in `_ensure_tracking_table` duplicates migration 013's table definition; divergence risk | MEDIUM | `backend/scripts/run_migrations.py`, `_ensure_tracking_table()` |
| M3 | GUC-based bypass mechanism is unnecessary — column-level REVOKE already provides enforcement | MEDIUM | `database/migrations/013_migration_tracking_and_legacy_compat.sql`, lines 217-310 |

---

### PostgreSQL Runtime Evidence

**No PostgreSQL runtime testing has been performed.**

| Tool | Available | Version |
|------|-----------|---------|
| `psql` / `pg_isready` / `postgres` / `initdb` | NO | — |
| Docker | NO | — |
| Podman | NO | — |
| `psycopg2` / `psycopg2-binary` | NO | — |
| pglast | YES | 8.9 |

All validation to date is static SQL parsing with pglast (13/13 migrations parse cleanly) and regex-based text tests (254/254 pass). **No migration has been executed against a live PostgreSQL database. No RLS policy has been runtime-tested. No trigger has been runtime-tested.**

---

### Fresh-Install Compatibility

**Status: UNVERIFIED (design only)**

A fresh install applying migrations 001→013 in order should work because:
- Migration 006 creates `content_reviews` with correct schema including `reviewed_at TIMESTAMPTZ NOT NULL DEFAULT now()`
- Migration 010 adds RLS policies (but the INSERT policy has the C1 flaw)
- Migration 012 adds the self-review trigger
- Migration 013 adds tracking table, legacy repair (no-op on fresh install), and reviewed_at protection

**However**, the C1 flaw means no reviewer can insert a content_reviews row, making the review workflow non-functional from day one.

---

### Legacy-Upgrade Compatibility

**Status: UNVERIFIED (design only, likely to fail)**

Migration 013 attempts to repair legacy `content_reviews` tables, but:
- `ALTER COLUMN reviewed_at SET NOT NULL` will fail if any NULL values exist (H1)
- FK additions will fail if existing data violates referential integrity (H2)
- Databases without `schema_migrations` tracking records cannot be safely migrated by the runner (C4)

**Manual data remediation would be required before migration 013 can succeed on most legacy databases.**

---

### Migration Runner Bootstrap Assessment

| Aspect | Status |
|--------|--------|
| Tracking table bootstrap | PASS (created before migrations) |
| Migration 013 self-recording | PASS (runner inserts after SQL) |
| Failed migration recording | PASS |
| Resume after interruption | PASS |
| Atomic DDL + tracking | PASS |
| Concurrent runner prevention | FAIL (no advisory lock) |
| Checksum verification | PASS |
| Edited migration detection | PASS |
| Legacy DB without tracking records | FAIL |

---

### Timestamp Security Assessment

| Layer | Status | Notes |
|-------|--------|-------|
| Column DEFAULT now() | PASS | Server assigns timestamp on insert |
| Column-level REVOKE UPDATE (reviewed_at) | PASS | Prevents authenticated users from modifying the column |
| RLS INSERT `reviewed_at IS NULL` | FAIL | Rejects legitimate inserts (C1) |
| RLS UPDATE `reviewer_id = auth.uid()` | PASS | Reviewers can only update own reviews |
| Trigger `assert_reviewed_at_immutable` | PARTIAL | Blocked by GUC bypass (C2) |
| SECURITY DEFINER `aph_correct_reviewed_at` | PARTIAL | Depends on GUC (C2) |
| No OLD/NEW in RLS | PASS | Verified |

**Bottom line:** Column-level REVOKE provides the actual enforcement. The trigger + GUC mechanism is redundant and introduces a bypass vector. The INSERT policy's `IS NULL` check is actively harmful.

---

### CI Workflow Assessment

| Aspect | Status |
|--------|--------|
| Workflow configured | PASS |
| Workflow actually executed | FAIL (never run) |
| PostgreSQL service | UNVERIFIED |
| `auth.uid()` compatibility | FAIL (Supabase-specific, not in plain PostgreSQL) |
| RLS test validity | FAIL (no table grants, `auth.uid()` missing, tests forgery not legitimacy) |
| Migration execution | PASS (design) |
| Idempotency test | PASS (design) |
| Cleanup | PASS |
| No production secrets | PASS |

---

### Exact Remediation Steps

#### R1: Fix the INSERT RLS policy (CRITICAL — C1)

**File:** `database/migrations/010_rls_and_storage_policies.sql`

Remove `AND reviewed_at IS NULL` from the `reviewers_manage_content_reviews_insert` policy. The column DEFAULT `now()` already guarantees server-assigned timestamps. Column-level REVOKE + the immutable trigger prevent modification.

**Before:**
```sql
AND reviewed_at IS NULL
```

**After:** (delete this line)

#### R2: Remove the user-settable GUC bypass (CRITICAL — C2)

**File:** `database/migrations/013_migration_tracking_and_legacy_compat.sql`

Either:
- **Option A:** Drop the `assert_reviewed_at_immutable` trigger entirely. Column-level `REVOKE UPDATE (reviewed_at)` prevents non-owners from modifying the column. The SECURITY DEFINER `aph_correct_reviewed_at()` function runs as owner and can update the column without needing a GUC flag.
- **Option B:** Replace the GUC check with a mechanism that cannot be set by ordinary clients.

#### R3: Add real PostgreSQL integration tests (CRITICAL — C3)

Create tests that execute against a live PostgreSQL database and verify:
- Legitimate reviewer INSERT succeeds
- Reviewer cannot forge `reviewer_id`
- Reviewer cannot forge/backdate `reviewed_at`
- Administrator can correct `reviewed_at` via `aph_correct_reviewed_at()`
- Self-review is blocked by trigger
- No DELETE on content_reviews

#### R4: Fix migration runner for legacy databases (CRITICAL — C4)

**File:** `backend/scripts/run_migrations.py`

- Detect legacy databases without tracking records
- For such databases, either skip to migration 013 (assuming 001-012 already applied) or provide a `--legacy` mode
- Add `pg_advisory_lock` for concurrent runner prevention

#### R5: Fix CI workflow for PostgreSQL compatibility (CRITICAL — C5)

**File:** `.github/workflows/database-readiness.yml`

- Install `auth.uid()` function (Supabase extension) or mock it in the test container
- Grant table privileges to test roles
- Test that legitimate INSERT succeeds (not just that forgery fails)

#### R6: Add data validation before legacy schema repairs (HIGH — H1, H2)

**File:** `database/migrations/013_migration_tracking_and_legacy_compat.sql`

Before `ALTER COLUMN reviewed_at SET NOT NULL`, check for NULL values and report them rather than failing silently. Before adding FKs, validate existing data integrity.

---

### Sign-off

| Item | Status |
|------|--------|
| Audit 1 — reviewed_at INSERT policy | FAIL — C1 |
| Audit 2 — Custom GUC bypass | FAIL — C2 |
| Audit 3 — Migration runner bootstrap | PARTIAL — C4 |
| Audit 4 — Legacy migration compatibility | PARTIAL — H1, H2 |
| Audit 5 — GitHub Actions workflow | UNVERIFIED — C5 |
| Audit 6 — Test quality | FAIL — C3 |
| PostgreSQL runtime evidence | NONE — never executed |
| Fresh-install compatibility | UNVERIFIED (design flawed by C1) |
| Legacy-upgrade compatibility | UNVERIFIED (likely fails on H1, H2) |

**Final verdict: FAIL — Do not deploy to production. Remediate C1-C5 before Phase 03.**
