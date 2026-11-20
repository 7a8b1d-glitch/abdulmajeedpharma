# Abdulmajeedpharma (APH) — Phase 02.2 Independent Security Audit

**Auditor:** Independent Senior PostgreSQL Security Auditor  
**Branch:** `arena/fcc02306-abdulmajeedpharma`  
**Base commit:** `ef1ee81` (main)  
**Audit scope:** Phase 02.2 changes to migrations, tests, and docs  
**Audit method:** Source code inspection — no live PostgreSQL, no runtime execution  

---

## Executive Verdict: FAIL (Migration-Order Blocker)

**Phase 02.2 is NOT ready for Phase 03.** A CRITICAL migration-order defect prevents
clean sequential execution of migrations 001–011 on a blank PostgreSQL database.
Migration 005 will fail because it creates a foreign key to `public.user_profiles`,
which is not created until migration 006.

All other security controls are correctly designed at the source-code level but
have **not been executed against a live PostgreSQL database** and therefore cannot
be confirmed as runtime-safe.

---

## AUDIT 1 — Migration Order and Execution

### CRITICAL: Migration 005 references user_profiles before migration 006 creates it

**Files:** `database/migrations/005_scientific_evidence_and_reviews.sql`

**Lines 80–81** (`content_reviews` table definition):

```sql
reviewer_id        UUID NOT NULL
    REFERENCES public.user_profiles (user_id)
    ON DELETE RESTRICT,
```

**Lines 86–87:**

```sql
approved_by        UUID
    REFERENCES public.user_profiles (user_id)
    ON DELETE SET NULL,
```

**Problem:** `public.user_profiles` is created in **migration 006** (line 12 of
`006_users_and_permissions.sql`). Migration 005 runs **before** migration 006.
PostgreSQL validates FOREIGN KEY references at CREATE TABLE time — the referenced
table and column must already exist. Migration 005 will fail with:

```
ERROR:  relation "user_profiles" does not exist
```

**Impact:** A clean PostgreSQL database cannot execute migrations 001–011
sequentially. Execution stops at migration 005.

**Remediation:** Either (a) move the `content_reviews` table creation to migration
006 (after `user_profiles` exists), or (b) move the `user_profiles` table creation
to migration 005 (before `content_reviews`), or (c) create `user_profiles` in an
earlier migration (e.g. 001 or a new 000) and have 006 only add columns/indexes.

---

### HIGH: Migration 005 trigger references drug_evidence.created_by before it exists

**File:** `database/migrations/005_scientific_evidence_and_reviews.sql`

**Lines 140–149** (`assert_no_self_review()` function):

```sql
SELECT created_by INTO evidence_creator
FROM public.drug_evidence
WHERE id = NEW.drug_evidence_id;
```

**Problem:** The `created_by` column does not exist on `public.drug_evidence` at
migration 005 time. It is added by `ALTER TABLE ... ADD COLUMN created_by` in
**migration 010** (lines 21–24 of `010_rls_and_storage_policies.sql`).

**PostgreSQL behavior:** CREATE FUNCTION does NOT validate that referenced tables
or columns exist at function-creation time. The function will be created
successfully. However, when the trigger `trg_content_reviews_no_self_review`
fires on an INSERT or UPDATE to `content_reviews` **before migration 010 runs**,
it will fail with:

```
ERROR:  column "created_by" does not exist
```

After migration 010 completes, the trigger will work correctly. This is a
transient issue during sequential migration execution, but combined with the
CRITICAL FK issue above, migration 005 never completes successfully anyway.

---

### Migration-order dependency analysis

| Migration | Depends on | Creates | References tables from | Status |
|-----------|-----------|---------|----------------------|--------|
| 001 | — | extensions, set_updated_at(), aph_current_user_role() | — | OK (CREATE FUNCTION doesn't validate refs) |
| 002 | 001 | countries, body_systems, therapeutic_classes, pharmacological_classes, drug_classes | 001 (gen_random_uuid, set_updated_at) | OK |
| 003 | 001, 002 | drug catalog tables | 001, 002 | OK |
| 004 | 001, 002, 003 | companies, brands, presentations, markets, registrations | 002, 003 | OK |
| **005** | 001, 003, 004 | scientific_sources, drug_evidence, **content_reviews** | **006 (user_profiles — MISSING)**, 001, 003, 004 | **FAIL — FK to user_profiles** |
| 006 | 001 | user_profiles | 001, 002 | OK |
| 007 | 001, 006 | messaging tables | 001, 006 | OK |
| 008 | 001, 006 | import/audit tables | 001, 006 | OK |
| 009 | 001–008 | search indexes, tsvector columns | 001–008 | OK |
| 010 | 001–009 | RLS policies, column privileges, SECURITY DEFINER functions, created_by columns | 001–009 | OK |
| 011 | 002 | seed data | 002 | OK |

---

### NOT NULL on reviewed_at — No issue for clean database

**File:** `database/migrations/005_scientific_evidence_and_reviews.sql`, line ~75:

```sql
reviewed_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
```

**Analysis:** `content_reviews` is a new table created in migration 005. There are
no pre-existing rows with NULL values. Adding a NOT NULL column with DEFAULT now()
to a new table is safe. This would only be a problem if the column were being
altered on an existing table with data — which is not the case here.

---

### Foreign key type compatibility — All compatible

All FK references are UUID → UUID. Verified across migrations 002–008. No type
mismatches found.

---

### Trigger creation order — Correct within each migration

- Migration 002: `set_updated_at()` from migration 001 exists; triggers reference it. OK.
- Migration 003: same pattern. OK.
- Migration 005: `assert_no_self_review()` is defined before `CREATE TRIGGER` that references it. OK.
- Migration 001: `set_updated_at()` defined before any triggers reference it. OK.

---

### Repeatability — Partially correct

- Migrations use `CREATE OR REPLACE FUNCTION`, `CREATE EXTENSION IF NOT EXISTS`,
  `ADD COLUMN IF NOT EXISTS`, `DROP POLICY IF EXISTS`, `ON CONFLICT DO NOTHING`.
- **NOT repeatable:** `CREATE TABLE` statements have no `IF NOT EXISTS`. Re-running
  any migration after partial failure will fail on `CREATE TABLE ... already exists`.
- `REVOKE ALL ON FUNCTION ... FROM PUBLIC` is repeatable (no error if already revoked).
- `CREATE TRIGGER` is NOT repeatable — will fail if trigger already exists.

---

## AUDIT 2 — Profile Column Privileges

### Column-level REVOKE/GRANT — Correctly implemented

**File:** `database/migrations/010_rls_and_storage_policies.sql`

**Lines 245–249:**

```sql
REVOKE UPDATE ON public.user_profiles FROM PUBLIC;
REVOKE UPDATE ON public.user_profiles FROM authenticated;

GRANT UPDATE (full_name, phone, country_id, language) ON public.user_profiles TO authenticated;
```

**Verification:**

| Column | UPDATE on `authenticated` | Status |
|--------|--------------------------|--------|
| `full_name` | GRANTED | ✅ Safe — self-service field |
| `phone` | GRANTED | ✅ Safe — self-service field |
| `country_id` | GRANTED | ✅ Safe — self-service field |
| `language` | GRANTED | ✅ Safe — self-service field |
| `role` | REVOKED | ✅ Privileged — blocked |
| `is_active` | REVOKED | ✅ Privileged — blocked |
| `email_verified` | REVOKED | ✅ Privileged — blocked |
| `email` | No UPDATE grant | ✅ Managed by Supabase Auth |
| `user_id` | Primary key — immutable | ✅ |

All granted columns (`full_name`, `phone`, `country_id`, `language`) exist on
`public.user_profiles` (migration 006). ✅

### Column-level privileges + RLS interaction

**Critical understanding:** Column-level privileges are checked **independently** of
RLS. Even if an RLS policy permits an UPDATE on a row, PostgreSQL will reject the
statement if the user lacks UPDATE privilege on the specific column.

This means:
- An authenticated administrator **cannot** directly `UPDATE user_profiles SET role = 'administrator'` even through the `admins_manage_user_profiles_update` RLS policy, because the `role` column UPDATE privilege is revoked from `authenticated`.
- Administrators must use `aph_manage_user_role()` (SECURITY DEFINER) which runs as the function owner and bypasses column-level privilege checks. ✅ Correct by design.

### No other role has unintended UPDATE privileges

- `PUBLIC`: REVOKED (line 245)
- `authenticated`: REVOKED then GRANTED only on 4 safe columns (lines 246–249)
- No explicit GRANT to `editor`, `scientific_reviewer`, or `administrator` roles
  (these are not PostgreSQL roles; they are application roles stored in
  `user_profiles.role`)

**Note:** Supabase creates `authenticated` and `anon` as PostgreSQL roles. All
authenticated users are members of `authenticated`. The column-level privileges
apply to all of them uniformly.

---

## AUDIT 3 — Security Definer Functions

### aph_manage_user_role(target_user_id UUID, new_role VARCHAR(30))

**File:** `database/migrations/010_rls_and_storage_policies.sql`, lines ~255–330

| Security property | Implementation | Status |
|-------------------|---------------|--------|
| SECURITY DEFINER | `SECURITY DEFINER` clause | ✅ |
| Safe search_path | `SET search_path = pg_temp, public` | ⚠️ See below |
| EXECUTE restricted | `REVOKE ALL ON FUNCTION ... FROM PUBLIC` | ✅ |
| Caller identity | `auth.uid()` — not from user input | ✅ |
| Admin authorization | Checks `user_profiles.role = 'administrator'` | ✅ |
| Self-role-change prevention | `IF auth.uid() = target_user_id THEN RAISE EXCEPTION` | ✅ |
| Role value validation | `IF new_role NOT IN (...)` | ✅ |
| Atomic operation | Single PL/pgSQL block (UPDATE + INSERT) | ✅ |
| Audit trail | INSERT INTO audit_logs with old_role/new_role | ✅ |
| Fully qualified table names | `public.user_profiles`, `public.audit_logs` | ✅ |

**search_path analysis:** `SET search_path = pg_temp, public` places `pg_temp`
first. However, all table references in the function are **fully qualified**
(`public.user_profiles`, `public.audit_logs`), so search-path injection via temp
tables is not possible for this specific function. The `pg_temp, public` ordering
is not a vulnerability here because no unqualified table references exist.

**auth.uid() in SECURITY DEFINER:** In PostgreSQL/Supabase, `auth.uid()` inside a
SECURITY DEFINER function still resolves to the **caller's** authenticated user ID,
not the function owner's. This is correct behavior — the function identifies who
called it, then checks if that caller is an administrator.

**RLS/FORCE RLS interaction:** SECURITY DEFINER functions execute with the
function owner's privileges and **bypass RLS**. The UPDATE on `public.user_profiles`
inside `aph_manage_user_role` will succeed even though the caller might not have
RLS permission to update that row. This is intentional — the function is the
controlled gateway for admin operations. The function's own authorization check
(caller must be administrator) replaces the RLS check.

---

### aph_manage_user_profile(target_user_id UUID, is_active_param BOOLEAN, ...)

**File:** `database/migrations/010_rls_and_storage_policies.sql`, lines ~332–380

| Security property | Implementation | Status |
|-------------------|---------------|--------|
| SECURITY DEFINER | `SECURITY DEFINER` clause | ✅ |
| Safe search_path | `SET search_path = pg_temp, public` | ⚠️ Same as above — all refs fully qualified |
| EXECUTE restricted | `REVOKE ALL ON FUNCTION ... FROM PUBLIC` | ✅ |
| Caller identity | `auth.uid()` | ✅ |
| Admin authorization | Checks `user_profiles.role = 'administrator'` | ✅ |
| Atomic operation | Single PL/pgSQL block | ✅ |
| Audit trail | INSERT INTO audit_logs | ✅ |
| Fully qualified table names | `public.user_profiles`, `public.audit_logs` | ✅ |

---

### Helper functions called by SECURITY DEFINER functions

- `aph_manage_user_role` and `aph_manage_user_profile` do **not** call any other
  functions. They use direct SQL statements only. ✅

- `assert_no_self_review()` (migration 005) is a trigger function, not called by
  the SECURITY DEFINER RPCs. It uses `SET search_path = pg_temp, public` and
  references `public.drug_evidence` (fully qualified). ✅

---

### Failure cases and atomicity

Both SECURITY DEFINER functions perform UPDATE + INSERT in a single PL/pgSQL
block without explicit `COMMIT`. If any statement raises an exception, the entire
function call is rolled back. ✅ Atomic.

However, there is no explicit `SAVEPOINT` or `EXCEPTION` handling for partial
failures between the UPDATE and the INSERT. If the UPDATE succeeds but the
INSERT into audit_logs fails (e.g., due to a constraint violation), the entire
transaction rolls back, including the UPDATE. This is correct behavior — no
partial state is committed.

---

## AUDIT 4 — Scientific Review Integrity

### reviewer_id cannot be forged

- `reviewer_id` is `UUID NOT NULL REFERENCES public.user_profiles (user_id)` —
  the FK ensures the value exists in user_profiles. ✅
- RLS policy `reviewers_manage_content_reviews_insert` has `WITH CHECK` requiring
  `EXISTS (SELECT 1 FROM public.user_profiles up WHERE up.user_id = auth.uid() AND up.role IN ('scientific_reviewer','administrator'))`. ✅
- However, nothing prevents a reviewer from setting `reviewer_id` to a **different**
  user's UUID (not their own). The FK only ensures the referenced user exists, not
  that it matches `auth.uid()`. The RLS policy checks that `auth.uid()` is a
  reviewer, but does not check `reviewer_id = auth.uid()`. A malicious reviewer
  could insert a review record with `reviewer_id` set to another reviewer's UUID.

**Finding:** MEDIUM — reviewer_id is not bound to auth.uid() in INSERT policy.

---

### reviewed_at is assigned reliably

- `reviewed_at TIMESTAMPTZ NOT NULL DEFAULT now()` — defaults to current time. ✅
- CHECK constraint: `NOT (review_status = 'verified' AND reviewed_at IS NULL)` —
  redundant since reviewed_at is NOT NULL, but harmless. ✅

---

### Reviewer cannot review their own evidence

**Database trigger:** `trg_content_reviews_no_self_review` (BEFORE INSERT OR UPDATE)
calls `assert_no_self_review()` which checks `NEW.reviewer_id <> drug_evidence.created_by`. ✅

**RLS defense in depth:** `reviewers_manage_content_reviews_insert` policy includes:
```sql
AND NOT EXISTS (
    SELECT 1 FROM public.drug_evidence de
    WHERE de.id = content_reviews.drug_evidence_id
      AND de.created_by = auth.uid()
)
```
✅

**CRITICAL BLOCKER:** The trigger queries `drug_evidence.created_by` which doesn't
exist until migration 010. Migration 005 will fail before reaching migration 010
due to the FK issue. Even if that were fixed, the trigger would fail at runtime
until migration 010 adds the column.

---

### Editors cannot create verified evidence

**RLS policy `editors_insert_evidence`:**
```sql
WITH CHECK (
    created_by = auth.uid()
    AND is_verified = FALSE
    AND EXISTS (admin_or_editor check)
)
```
`is_verified = FALSE` is required. Editors cannot insert verified evidence. ✅

**RLS policy `editors_update_own_unverified_evidence`:**
```sql
USING (created_by = auth.uid() AND is_verified = FALSE ...)
WITH CHECK (created_by = auth.uid() AND is_verified = FALSE ...)
```
Editors cannot update evidence to verified. ✅

---

### Review records cannot be improperly deleted

- No DELETE policy exists on `content_reviews` for any role. ✅
- RLS is enabled on `content_reviews` (migration 010). ✅
- Without a DELETE policy, no authenticated user can DELETE through RLS. ✅
- The Supabase service role can bypass RLS and delete. This is by design but
  should be noted as a residual risk.

---

### Existing records compatibility with new constraints

- `content_reviews` is a new table in migration 005. No existing rows. ✅
- `reviewed_at NOT NULL DEFAULT now()` — all new rows get a timestamp. ✅
- `reviewer_id REFERENCES user_profiles` — new table, no existing data to violate FK. ✅

---

### Trigger works for INSERT and UPDATE

**File:** `database/migrations/005_scientific_evidence_and_reviews.sql`

```sql
CREATE TRIGGER trg_content_reviews_no_self_review
    BEFORE INSERT OR UPDATE ON public.content_reviews
    FOR EACH ROW EXECUTE FUNCTION assert_no_self_review();
```

The trigger function checks `IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE'`. ✅
The function returns `NEW` (row-level trigger). ✅

---

## AUDIT 5 — Regression Test Quality

### Test function count

| Metric | Count |
|--------|-------|
| Total test functions | 43 |
| Parametrized test functions | 7 |
| Non-parametrized test functions | 36 |
| Executed pytest test cases | 231 |
| New test functions in Phase 02.2 | 10 |

### Phase 02.2 new test functions

| # | Test Function | What it proves | Tests actual PG behavior? | Could pass while vulnerable? |
|---|---------------|---------------|---------------------------|------------------------------|
| 1 | `test_no_old_new_in_rls_policies` | No OLD/NEW in RLS expressions | No — text search only | No (if text absent, OLD/NEW absent) |
| 2 | `test_column_level_privileges_exclude_privileged_profile_columns` | REVOKE/GRANT on privileged columns | No — text search only | Yes (SQL text present but not executed) |
| 3 | `test_role_management_function_exists` | aph_manage_user_role is SECURITY DEFINER | No — text search only | Yes |
| 4 | `test_role_management_prevents_self_promotion` | Self-role-change prevented in function | No — text search only | Yes |
| 5 | `test_role_management_audits_changes` | Audit log entries in function | No — text search only | Yes |
| 6 | `test_review_timestamp_enforced` | reviewed_at is NOT NULL | No — text search only | No (column definition present) |
| 7 | `test_reviewer_id_has_foreign_key` | reviewer_id FK to user_profiles | No — text search only | Yes (FK text present but migration order broken) |
| 8 | `test_self_review_trigger_exists` | Self-review trigger exists | No — text search only | Yes |
| 9 | `test_content_reviews_no_delete_policy` | No DELETE on content_reviews | No — text search only | No (policy absence verified) |
| 10 | `test_editors_cannot_approve_own_evidence_in_rls` | Self-review prevention in RLS INSERT | No — text search only | Yes |

**Key limitation:** All Phase 02.2 security tests are **static text inspections** of
SQL migration files. None execute against a live PostgreSQL database. A test can
pass while the actual runtime behavior is broken (e.g., migration 005 fails due
to FK order, but the text pattern for the FK is present).

### Duplicate tests

The following test functions are duplicated (different names, same/similar purpose):

- `test_rls_enabled_on_all_tables` — defined twice (lines ~495 and ~677)
- `test_seed_is_idempotent` — defined twice (lines ~408 and ~685)
- `test_18_body_systems_seeded` / `test_seed_18_body_systems` — similar purpose
- `test_yemen_country_seeded` / `test_seed_yemen_country` — similar purpose
- `test_no_fake_drug_records_in_seed` — defined twice
- `test_no_unrestricted_public_policy_on_private_tables` / `test_no_unrestricted_policy_on_private_tables` — similar purpose
- `test_rls_uses_auth_uid` / `test_policies_reference_auth_uid` — similar purpose

---

### Test execution results

| Validation | Result |
|------------|--------|
| pytest all tests | 231/231 PASSED |
| pglast grammar (11 migrations) | 11/11 PARSE OK |
| Health check | 95/95 PASS |
| SQLAlchemy model imports | 39/39 tables |
| Secret scan | Clean |

**Important:** All test results are static validation only. No PostgreSQL runtime
execution was performed.

---

## AUDIT 6 — Required Output

### Migration-Order Analysis

**Can migrations execute sequentially on a clean PostgreSQL database?**

**NO.** Migration 005 will fail because it creates foreign keys to
`public.user_profiles` (lines 80–81 and 86–87 of `005_scientific_evidence_and_reviews.sql`),
but `user_profiles` is not created until migration 006.

**Exact remediation:**

Option A — Move `content_reviews` table to migration 006:
1. Remove `content_reviews` CREATE TABLE from `005_scientific_evidence_and_reviews.sql`
2. Remove `assert_no_self_review()` function and trigger from migration 005
3. Add `content_reviews` CREATE TABLE, trigger function, and trigger to `006_users_and_permissions.sql`
4. Move `reviewers_manage_content_reviews_*` RLS policies from migration 010 to... actually they can stay in 010 since 010 runs after 006

Option B — Move `user_profiles` to migration 005:
1. Move `user_profiles` CREATE TABLE from `006_users_and_permissions.sql` to `005_scientific_evidence_and_reviews.sql` (before `content_reviews`)
2. Migration 006 would then only contain indexes, triggers, and comments on `user_profiles`

Option C — Create `user_profiles` in migration 001:
1. Create `user_profiles` in migration 001 (after extensions)
2. Migrations 005–011 reference it without issue
3. Migration 006 removes the CREATE TABLE and keeps only indexes/triggers/comments

**Recommended:** Option A — it keeps the logical grouping (users and permissions in 006) and is the least disruptive.

---

### Security-Definer Analysis

| Function | Safe search_path | No dynamic SQL | Caller from auth.uid() | Admin check | Self-role prevention | Role validation | Audit trail | Atomic | EXECUTE revoked |
|----------|-----------------|----------------|------------------------|-------------|---------------------|-----------------|-------------|--------|-----------------|
| aph_manage_user_role | ✅ (all refs fully qualified) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| aph_manage_user_profile | ✅ (all refs fully qualified) | ✅ | ✅ | ✅ | N/A | N/A | ✅ | ✅ | ✅ |
| assert_no_self_review | ✅ (all refs fully qualified) | ✅ | N/A (trigger) | N/A | N/A | N/A | N/A | ✅ | ✅ |

**Note on search_path:** All three functions use `SET search_path = pg_temp, public`.
While `pg_temp` first is normally a search-path injection risk, all table
references in these functions are fully qualified (`public.table_name`), so the
risk is mitigated in this specific code. Best practice would be `public, pg_temp`
order or fully qualified names only.

---

### Privilege Analysis

| Privilege | Grant/Revoke | Target | Effective |
|-----------|-------------|--------|-----------|
| UPDATE on user_profiles | REVOKED | PUBLIC | ✅ No public UPDATE |
| UPDATE on user_profiles | REVOKED | authenticated | ✅ No authenticated UPDATE |
| UPDATE (full_name, phone, country_id, language) | GRANTED | authenticated | ✅ Only safe columns |
| UPDATE (role, is_active, email_verified) | NOT GRANTED | authenticated | ✅ Blocked by column-level REVOKE |
| EXECUTE on aph_manage_user_role | REVOKED | PUBLIC | ✅ Restricted |
| EXECUTE on aph_manage_user_profile | REVOKED | PUBLIC | ✅ Restricted |
| EXECUTE on assert_no_self_review | REVOKED | PUBLIC | ✅ Restricted |

**Gap:** No explicit GRANT EXECUTE on `aph_manage_user_role` or `aph_manage_user_profile`
to any role. The functions are created but EXECUTE is revoked from PUBLIC with no
subsequent GRANT. No role can currently execute them. The backend application
would need to explicitly GRANT EXECUTE to an administrator role (e.g. a PostgreSQL
role that administrators map to).

---

### Test Coverage Limitations

1. **No runtime execution:** All tests are static text inspections. None validate
   actual PostgreSQL behavior, RLS enforcement, or function execution.
2. **No migration execution test:** No test verifies that migrations can run
   sequentially on a clean database (which they currently cannot — see CRITICAL finding).
3. **No column-level privilege runtime test:** No test verifies that an actual
   UPDATE on `role` column by an authenticated user is rejected at runtime.
4. **No SECURITY DEFINER function execution test:** No test verifies that
   `aph_manage_user_role` actually prevents self-promotion at runtime.
5. **No RLS policy execution test:** No test verifies that RLS policies actually
   restrict data access at runtime.
6. **Duplicate tests:** Several tests cover the same ground with different names.

---

### PostgreSQL Runtime Testing Status

**Status:** NOT PERFORMED.

**Blocker:** No PostgreSQL server, `psql`, `pg_isready`, `initdb`, or `postgres`
binary available in the Arena environment. `apt` is available but installing
PostgreSQL would be a large system dependency, which should not be done blindly.

**All validation performed:** Static SQL parsing via pglast, regex text inspection,
SQLAlchemy model import, health check script.

---

### Findings Summary

| Severity | Count | Description |
|----------|-------|-------------|
| CRITICAL | 2 | (1) Migration 005 FK to user_profiles before 006 creates it; (2) Migration 005 trigger references drug_evidence.created_by before 010 adds it |
| HIGH | 1 | No EXECUTE GRANT on aph_manage_user_role or aph_manage_user_profile — functions are unusable |
| MEDIUM | 1 | reviewer_id not bound to auth.uid() — reviewer can forge reviewer_id on another user |
| LOW | 3 | Duplicate test functions; search_path pg_temp first (mitigated by fully qualified names); no runtime validation |

---

### Exact Remediation Steps for Every Blocker

**CRITICAL #1 — Migration 005 FK to user_profiles before 006:**

1. Open `database/migrations/005_scientific_evidence_and_reviews.sql`
2. Remove the `content_reviews` CREATE TABLE block (lines ~63–97)
3. Remove the `assert_no_self_review()` function and `trg_content_reviews_no_self_review` trigger (lines ~127–164)
4. Open `database/migrations/006_users_and_permissions.sql`
5. Add the `content_reviews` table creation after `user_profiles` table
6. Add the `assert_no_self_review()` function and trigger after the table
7. Verify migration 010 RLS policies still work (they run after 006)

**CRITICAL #2 — Trigger references missing column:**

Resolved by CRITICAL #1 fix — once `content_reviews` moves to migration 006 (after user_profiles), the trigger will still reference `drug_evidence.created_by` which is added in migration 010. Since migration 006 runs before 010, the trigger function will be created successfully (PostgreSQL doesn't validate function body references at creation time), and will work after migration 010 adds the column. No additional change needed beyond CRITICAL #1.

**HIGH — No EXECUTE GRANT on SECURITY DEFINER functions:**

1. Add `GRANT EXECUTE ON FUNCTION aph_manage_user_role(UUID, VARCHAR(30)) TO <admin_role>;` to migration 010
2. Add `GRANT EXECUTE ON FUNCTION aph_manage_user_profile(...) TO <admin_role>;` to migration 010
3. Replace `<admin_role>` with the appropriate PostgreSQL role that administrators map to (e.g., `authenticated` with additional application-level checks, or a dedicated `aph_admin` role)

**MEDIUM — reviewer_id not bound to auth.uid():**

1. In `database/migrations/010_rls_and_storage_policies.sql`, modify the
   `reviewers_manage_content_reviews_insert` policy WITH CHECK to include:
   ```sql
   AND reviewer_id = auth.uid()
   ```

**LOW — Duplicate tests:**

1. Remove duplicate test functions from `backend/tests/test_database_schema.py`
2. Consolidate `test_rls_enabled_on_all_tables`, `test_seed_is_idempotent`,
   `test_no_fake_drug_records_in_seed`, and similar duplicates

---

### Final Decision

| Question | Answer |
|----------|--------|
| Can migrations execute sequentially on clean PostgreSQL? | **NO** — blocked at migration 005 |
| Are profile and review security controls genuinely safe? | **Design is correct, but unvalidated at runtime** — static analysis only |
| Is Phase 02.2 ready for Phase 03? | **NO** — CRITICAL migration-order blocker must be fixed first |
| Exact remaining blockers | (1) Migration 005 FK to user_profiles before 006; (2) No runtime PostgreSQL validation performed |

**STOP: Phase 02.2 audit complete. Do not begin Phase 03.** Remediation of the
CRITICAL migration-order defect is required before any further work.