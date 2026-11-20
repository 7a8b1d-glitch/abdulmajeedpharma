# Abdulmajeedpharma (APH) — Phase 02.3 Remediation Report

**Project Owner:** Dr. Abdulmajeed Abdullah Almakhedhi  
**Phase:** Phase 02.3 — Critical Migration Order and Review Security Remediation  
**Branch:** `arena/fcc02306-abdulmajeedpharma`  
**Base commit:** `ef1ee81` (main)  
**Status:** Complete — remediation applied, validated, documented  

---

## Executive Summary

Phase 02.3 addressed four critical findings from the independent Phase 02.2 security
audit. The most critical finding was a migration-order defect: migration 005
created `content_reviews` with foreign keys to `user_profiles`, which is not
created until migration 006. This prevented sequential execution of migrations
on a clean PostgreSQL database. All four blockers have been remediated.

No live PostgreSQL database was available for runtime validation. All changes
were validated statically via pglast parsing and regex inspection.

---

## CRITICAL Fix #1 — Migration Order: content_reviews depends on user_profiles

### Problem

**File:** `database/migrations/005_scientific_evidence_and_reviews.sql`  
**Lines:** 78–87 (original)

Migration 005 created `content_reviews` with:
```sql
reviewer_id UUID NOT NULL REFERENCES public.user_profiles (user_id)
approved_by UUID REFERENCES public.user_profiles (user_id)
```

But `public.user_profiles` is created in **migration 006**, which runs after
migration 005. PostgreSQL validates FOREIGN KEY references at CREATE TABLE time,
so migration 005 would fail with `relation "user_profiles" does not exist`.

### Remediation Strategy

**Chosen approach:** Split `content_reviews` across migrations:

| Migration | Content | Reasoning |
|-----------|---------|-----------|
| 005 | `scientific_sources`, `drug_evidence` only | No dependency on `user_profiles` |
| 006 | `user_profiles` + `content_reviews` table | `user_profiles` created first, then `content_reviews` with FKs to it |
| 010 | RLS policies on `content_reviews` | Table exists from migration 006 |
| 012 | `assert_no_self_review()` function + trigger | `drug_evidence.created_by` exists from migration 010 |

**Why not a new migration 012 for the table?** Migration 010 creates RLS
policies on `content_reviews`. If the table were created in 012 (after 010),
those policies would fail at runtime because the table wouldn't exist when
migration 010 executes. Placing the table in migration 006 (after `user_profiles`
but before 010) preserves the correct dependency order.

**Forward compatibility:** Migration 012 uses `CREATE OR REPLACE FUNCTION` and
`DROP TRIGGER IF EXISTS` / `CREATE TRIGGER` for idempotent re-application on
already-migrated databases.

**Files changed:**
- `database/migrations/005_scientific_evidence_and_reviews.sql` — removed `content_reviews` table, indexes, trigger function, and trigger
- `database/migrations/006_users_and_permissions.sql` — added `content_reviews` table, indexes, and updated trigger
- `database/migrations/012_review_trigger.sql` — NEW: `assert_no_self_review()` function and trigger

---

## CRITICAL Fix #2 — Trigger dependency on drug_evidence.created_by

### Problem

**File:** `database/migrations/005_scientific_evidence_and_reviews.sql`  
**Lines:** 127–164 (original)

The `assert_no_self_review()` trigger function queried `drug_evidence.created_by`:
```sql
SELECT created_by INTO evidence_creator
FROM public.drug_evidence
WHERE id = NEW.drug_evidence_id;
```

But `created_by` is added to `drug_evidence` by `ALTER TABLE` in migration 010,
which runs after migration 005. The trigger would fail at runtime until migration
010 completes.

### Remediation

Moved `assert_no_self_review()` function and `trg_content_reviews_no_self_review`
trigger to migration 012, which runs after migration 010. At that point,
`drug_evidence.created_by` exists and the trigger works correctly.

**File:** `database/migrations/012_review_trigger.sql` (new)

---

## CRITICAL Fix #3 — Missing EXECUTE permissions on SECURITY DEFINER functions

### Problem

**File:** `database/migrations/010_rls_and_storage_policies.sql`

`aph_manage_user_role()` and `aph_manage_user_profile()` had `REVOKE ALL ...
FROM PUBLIC` but **no subsequent GRANT EXECUTE** to any role. No authenticated
user (including administrators) could execute these functions.

### Remediation

Added `GRANT EXECUTE ... TO authenticated` after each REVOKE:

| Function | REVOKE FROM PUBLIC | GRANT TO authenticated |
|----------|-------------------|----------------------|
| `aph_manage_user_role(UUID, VARCHAR(30))` | ✅ Added | ✅ Added |
| `aph_manage_user_profile(UUID, BOOLEAN, TEXT, VARCHAR(30), UUID, VARCHAR(10))` | ✅ Added | ✅ Added |

**Security analysis:** The functions themselves enforce administrator authorization
by checking `user_profiles.role = 'administrator'` via `auth.uid()`. Granting
EXECUTE to `authenticated` is safe because:
1. The function body checks the caller's role before performing any action
2. Non-administrators receive `RAISE EXCEPTION 'Only administrators can manage user roles.'`
3. `EXECUTE` remains revoked from `PUBLIC` (anonymous/unauthenticated users cannot call)

**File:** `database/migrations/010_rls_and_storage_policies.sql`

---

## CRITICAL Fix #4 — Reviewer identity not bound to auth.uid()

### Problem

**File:** `database/migrations/010_rls_and_storage_policies.sql`

The `reviewers_manage_content_reviews_insert` policy checked that `auth.uid()`
was a reviewer, but did **not** bind `reviewer_id` to `auth.uid()`. A malicious
reviewer could insert a review with `reviewer_id` set to another user's UUID,
forging authorship.

Similarly, the UPDATE policy did not bind `reviewer_id` in the USING or WITH CHECK
clauses, allowing a reviewer to change `reviewer_id` on an existing review to
another user's UUID.

### Remediation

Added `reviewer_id = auth.uid()` to both policies:

| Policy | Clause | Change |
|--------|--------|--------|
| `reviewers_manage_content_reviews_insert` | WITH CHECK | Added `reviewer_id = auth.uid()` as first condition |
| `reviewers_manage_content_reviews_update` | USING | Added `reviewer_id = auth.uid()` (can only update own reviews) |
| `reviewers_manage_content_reviews_update` | WITH CHECK | Added `reviewer_id = auth.uid()` (cannot forge reviewer_id) |

**Defense in depth:** The `assert_no_self_review()` trigger in migration 012
also prevents self-review, providing a second layer of protection.

**File:** `database/migrations/010_rls_and_storage_policies.sql`

---

## Before/After Dependency Order

### Before (broken)

| Migration | Creates | Forward Dependencies |
|-----------|---------|---------------------|
| 005 | `scientific_sources`, `drug_evidence`, **`content_reviews`** | **`content_reviews` → `user_profiles` (migration 006)** ❌ |
| 006 | `user_profiles` | — |
| 010 | RLS policies on `content_reviews` | Table may not exist (created in failed 005) |
| — | `assert_no_self_review` trigger | `drug_evidence.created_by` (migration 010) not yet added |

### After (fixed)

| Migration | Creates | Dependencies |
|-----------|---------|-------------|
| 005 | `scientific_sources`, `drug_evidence` | 001, 003, 004 ✅ |
| 006 | `user_profiles`, **`content_reviews`** | 001–005 ✅ |
| 010 | RLS policies on `content_reviews` (table exists from 006) | 001–009 ✅ |
| 012 | `assert_no_self_review()` function + trigger | 001–011 (created_by from 010) ✅ |

---

## Function Execution Permission Matrix

| Function | Security | search_path | EXECUTE REVOKE FROM PUBLIC | EXECUTE GRANT TO authenticated | Caller authorization |
|----------|----------|-------------|---------------------------|-------------------------------|---------------------|
| `aph_manage_user_role(UUID, VARCHAR)` | SECURITY DEFINER | pg_temp, public | ✅ | ✅ | Checks `role = 'administrator'` via `auth.uid()` |
| `aph_manage_user_profile(UUID, BOOLEAN, TEXT, VARCHAR(30), UUID, VARCHAR(10))` | SECURITY DEFINER | pg_temp, public | ✅ | ✅ | Checks `role = 'administrator'` via `auth.uid()` |
| `assert_no_self_review()` | Trigger function | pg_temp, public | ✅ | N/A (trigger only) | Executed by system on INSERT/UPDATE |

**Anonymous users:** Cannot execute either function because `auth.uid()` returns NULL
outside an authenticated request context, and the function checks `role = 'administrator'`
which would fail for NULL.

---

## Reviewer Identity Protection

| Protection | Mechanism | Location |
|------------|-----------|----------|
| `reviewer_id = auth.uid()` on INSERT | RLS WITH CHECK | Migration 010, `reviewers_manage_content_reviews_insert` |
| `reviewer_id = auth.uid()` on UPDATE (USING) | RLS USING | Migration 010, `reviewers_manage_content_reviews_update` |
| `reviewer_id = auth.uid()` on UPDATE (WITH CHECK) | RLS WITH CHECK | Migration 010, `reviewers_manage_content_reviews_update` |
| Reviewer cannot review own evidence | Database trigger | Migration 012, `assert_no_self_review()` |
| Self-review defense in depth | RLS NOT EXISTS subquery | Migration 010, both INSERT and UPDATE policies |
| `reviewed_at` NOT NULL | Column constraint | Migration 006, `content_reviews` table |
| `reviewer_id` FK to `user_profiles` | Foreign key | Migration 006, `content_reviews` table |
| No DELETE on content_reviews | No DELETE policy | Migration 010 |

---

## Test Counts

| Metric | Count |
|--------|-------|
| Total test functions | 54 |
| Parametrized test functions | 7 |
| Executed pytest test cases | 243 |
| Phase 02.3 new test functions | 11 |

### Phase 02.3 New Tests

| # | Test Function | What it proves |
|---|---------------|---------------|
| 1 | `test_migration_005_no_user_profiles_reference` | Migration 005 has no forward dependency on user_profiles |
| 2 | `test_migration_005_no_created_by_reference` | Migration 005 has no forward dependency on created_by |
| 3 | `test_migration_006_has_content_reviews` | content_reviews exists in migration 006 |
| 4 | `test_migration_012_has_trigger` | Migration 012 has trigger function and trigger |
| 5 | `test_reviewer_id_bound_to_auth_uid_on_insert` | INSERT binds reviewer_id = auth.uid() |
| 6 | `test_reviewer_id_bound_to_auth_uid_on_update` | UPDATE binds reviewer_id = auth.uid() |
| 7 | `test_manage_user_role_execute_granted_to_authenticated` | EXECUTE granted on aph_manage_user_role |
| 8 | `test_manage_user_profile_execute_granted_to_authenticated` | EXECUTE granted on aph_manage_user_profile |
| 9 | `test_privileged_functions_revoke_from_public` | EXECUTE revoked from PUBLIC |
| 10 | `test_no_trigger_before_created_by_column` | No trigger before migration 010 |
| 11 | `test_content_reviews_no_delete_policy_still_valid` | No DELETE on content_reviews |

**Static-only limitation:** All tests inspect SQL text. None execute against a live
PostgreSQL database. A test can pass while runtime behavior is broken (e.g., if
pglast parsing succeeds but the SQL fails at execution time).

---

## PostgreSQL Runtime Testing Status

**Status:** NOT PERFORMED — No PostgreSQL server available in the Arena environment.

**Blocker:** No `psql`, `pg_isready`, `initdb`, or `postgres` binary installed.
`apt` is available but installing PostgreSQL server would be a large system
dependency, which should not be done blindly per project constraints.

**What was validated instead:**
- pglast native PostgreSQL grammar parsing: 12/12 migrations PASS
- SQLAlchemy model imports: 39/39 tables
- Health check: 95/95 PASS
- Static security regression tests: 243/243 PASS
- Secret scan: Clean

**Reproducible test plan for external Supabase development project:**
See `docs/PHASE_02_2_INDEPENDENT_AUDIT.md` for the runtime validation test plan
(SQL statements to execute against a provisioned database).

---

## Files Changed

| File | Change |
|------|--------|
| `database/migrations/005_scientific_evidence_and_reviews.sql` | Removed content_reviews table, trigger function, and trigger; updated comments |
| `database/migrations/006_users_and_permissions.sql` | Added content_reviews table, indexes, trigger; updated dependency comment |
| `database/migrations/010_rls_and_storage_policies.sql` | Added reviewer_id = auth.uid() to INSERT/UPDATE policies; added GRANT EXECUTE on both SECURITY DEFINER functions |
| `database/migrations/012_review_trigger.sql` | NEW: assert_no_self_review() function and trigger |
| `backend/tests/test_database_schema.py` | Added 11 new Phase 02.3 tests; updated 3 existing tests for new migration locations |

---

## Remaining Risks

1. **No live PostgreSQL validation:** All changes validated statically only.
   Runtime validation against a provisioned database is required before production use.

2. **Column-level privileges apply to administrators too:** Administrators cannot
   directly UPDATE `role` or `is_active` on `user_profiles` — they must use
   `aph_manage_user_role` / `aph_manage_user_profile`. The backend API must route
   admin profile updates through these functions.

3. **Service-role compromise:** The Supabase service role bypasses both RLS and
   column-level privileges. Service-role keys must never be exposed to client
   applications.

4. **Function ownership:** SECURITY DEFINER functions run as the function owner.
   Functions should be owned by a restricted postgres role, not a superuser.

5. **RLS can be bypassed by table owner:** FORCE RLS is applied to user-private
   tables (user_profiles, conversations, etc.), but not to content_reviews or
   drug_evidence (service role writes these). Content review integrity relies on
   RLS policies and the database trigger.

---

## Git Status

- Branch: `arena/fcc02306-abdulmajeedpharma`
- Working tree: changes not committed (pending review)
- No `.env`, `.venv`, `node_modules`, database credentials, or private keys
- No commit, push, or PR created — pending user review

---

**STOP: Phase 02.3 complete. Do not begin Phase 03.**