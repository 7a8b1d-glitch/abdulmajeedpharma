# Abdulmajeedpharma (APH) — Phase 02.2 Remediation Report

**Project Owner:** Dr. Abdulmajeed Abdullah Almakhedhi  
**Phase:** Phase 02.2 — Final Role Security and Review Integrity Fix  
**Branch:** `arena/fcc02306-abdulmajeedpharma`  
**Base commit:** `ef1ee81` (main)  
**Status:** Complete — remediation applied, validated, documented  

---

## Executive Summary

Phase 02.2 addressed a critical runtime defect discovered during targeted
security audit: the use of `OLD`/`NEW` row variables in RLS policy expressions
(which are invalid in PostgreSQL's RLS context). The remediation replaced the
invalid trigger-style references with a robust defense-in-depth permission
model combining column-level privileges, SECURITY DEFINER functions for
controlled admin operations, and database-enforced scientific review
traceability.

All changes are static (no live PostgreSQL available for runtime validation).

---

## CRITICAL Fix — Invalid OLD/NEW in RLS Policy

### Finding

**File:** `database/migrations/010_rls_and_storage_policies.sql`  
**Policy:** `users_update_own_profile`  
**Lines:** 192–194 (original)

```sql
WITH CHECK (
    user_id = auth.uid()
    AND role = OLD.role
    AND email_verified = OLD.email_verified
    AND is_active = OLD.is_active
)
```

**Problem:** `OLD`/`NEW` are trigger-specific row variables available only
inside PL/pgSQL trigger function bodies. They are **invalid** in PostgreSQL
RLS `USING`/`WITH CHECK` expressions. At RLS evaluation time, `OLD` would be
resolved as an undefined table alias, causing the UPDATE to fail with a runtime
error. pglast syntax parsing does not catch this because `OLD.role` is
syntactically valid SQL — pglast has no knowledge of RLS execution semantics.

**Fix:** Removed all `OLD`/`NEW` references from RLS policy expressions.
Replaced with column-level privileges:

```sql
REVOKE UPDATE ON public.user_profiles FROM PUBLIC;
REVOKE UPDATE ON public.user_profiles FROM authenticated;
GRANT UPDATE (full_name, phone, country_id, language) ON public.user_profiles TO authenticated;
```

The `users_update_own_profile` RLS policy now only restricts row access
(`user_id = auth.uid()`), while column-level privileges restrict which columns
can be modified.

**Validation:** `test_no_old_new_in_rls_policies` — verifies no OLD/NEW
references exist in any RLS policy expression across all 11 migrations.

---

## Column-Level Profile Security

### Design

Ordinary authenticated users may UPDATE only explicitly permitted profile
columns. Privileged columns are protected by column-level REVOKE.

| Column | Privilege on `authenticated` | Modified via |
|--------|------------------------------|--------------|
| `full_name` | GRANT UPDATE | Direct UPDATE (own row, RLS restricted) |
| `phone` | GRANT UPDATE | Direct UPDATE (own row, RLS restricted) |
| `country_id` | GRANT UPDATE | Direct UPDATE (own row, RLS restricted) |
| `language` | GRANT UPDATE | Direct UPDATE (own row, RLS restricted) |
| `role` | REVOKED | `aph_manage_user_role()` (admin only) |
| `is_active` | REVOKED | `aph_manage_user_profile()` (admin only) |
| `email_verified` | REVOKED | Supabase Auth only |
| `email` | No UPDATE | Supabase Auth only |
| `user_id` | No UPDATE (PK) | Immutable |

**File:** `database/migrations/010_rls_and_storage_policies.sql`

**Security properties:**
- Column-level REVOKE prevents direct SQL or API updates to privileged columns
- RLS `USING (user_id = auth.uid())` restricts row access to own profile
- Defense in depth: even if RLS is bypassed, column-level privileges still apply
- Column-level privileges apply to all authenticated users including
  administrators; admins must use SECURITY DEFINER functions for privileged ops

**Validation:** `test_column_level_privileges_exclude_privileged_profile_columns`

---

## Controlled Admin Role Management

### `aph_manage_user_role(target_user_id UUID, new_role VARCHAR(30))`

**File:** `database/migrations/010_rls_and_storage_policies.sql`

A SECURITY DEFINER function enabling authorized administrators to change
another user's role through a controlled, audited workflow.

**Security properties:**

| Property | Implementation |
|----------|---------------|
| SECURITY DEFINER | Runs as function owner (postgres/supabase admin), bypassing column-level privilege checks for the caller |
| `SET search_path = pg_temp, public` | Prevents search-path injection attacks |
| EXECUTE revoked from PUBLIC | Only explicitly granted roles can call |
| Caller must be administrator | Verified via `user_profiles.role` lookup using `auth.uid()` |
| Self-role-change prevented | `auth.uid() = target_user_id` raises exception; requires a second administrator |
| Role value validation | `new_role` must be in `('user','editor','scientific_reviewer','administrator')` |
| Atomic operation | Role UPDATE + audit log INSERT in one transaction |
| Full audit trail | Records actor_id, actor_role, target_user_id, old_role, new_role, timestamp |

**Why this is safe:**
- The function runs as the owner, so column-level REVOKEs on `authenticated`
  do not block the internal UPDATE
- `auth.uid()` is used to identify the caller, not a client-supplied value
- Role values are validated against the allowed set
- Self-promotion is explicitly prevented
- Every role change is immutably recorded in `audit_logs`

**Validation:** `test_role_management_function_exists`,
`test_role_management_prevents_self_promotion`, `test_role_management_audits_changes`

---

## Admin Profile Management

### `aph_manage_user_profile(...)`

**File:** `database/migrations/010_rls_and_storage_policies.sql`

A SECURITY DEFINER function allowing administrators to update non-role profile
fields (e.g. `is_active` for deactivation) on behalf of another user.

**Security properties:**
- Caller must be administrator (verified via `auth.uid()`)
- Only non-privileged fields can be updated through this function
- All updates are recorded in `audit_logs`
- Atomic operation within a single transaction

**Account deactivation:** Uses `is_active = FALSE` rather than profile deletion.
No DELETE policy exists on `user_profiles` for any role.

---

## Scientific Review Traceability

### Database-Enforced Constraints

**File:** `database/migrations/005_scientific_evidence_and_reviews.sql`

| Constraint | Implementation |
|------------|---------------|
| `reviewer_id` references `user_profiles` | FOREIGN KEY constraint |
| `reviewed_at` NOT NULL | Ensures review timestamp is always recorded |
| `review_status` controlled values | CHECK constraint on allowed statuses |
| Reviewer cannot review own evidence | Trigger `trg_content_reviews_no_self_review` + RLS policy defense |

### Trigger: `assert_no_self_review()`

**File:** `database/migrations/005_scientific_evidence_and_reviews.sql`

A BEFORE INSERT OR UPDATE trigger on `content_reviews` that raises an
exception if the reviewer is the creator of the evidence being reviewed.

### RLS Defense in Depth

**File:** `database/migrations/010_rls_and_storage_policies.sql`

The `reviewers_manage_content_reviews_insert` policy includes a `NOT EXISTS`
subquery checking that `drug_evidence.created_by <> auth.uid()`, providing
defense in depth alongside the database trigger.

**No DELETE policy** exists on `content_reviews` — review history is
append-only; corrections are made via superseding reviews.

**Validation:** `test_review_timestamp_enforced`,
`test_reviewer_id_has_foreign_key`, `test_self_review_trigger_exists`,
`test_content_reviews_no_delete_policy`,
`test_editors_cannot_approve_own_evidence_in_rls`

---

## Administrator Role Changes

### Who may change roles

| Caller | Can change own role? | Can change other users' roles? | Method |
|--------|---------------------|-------------------------------|--------|
| Ordinary user | No | No | — |
| Editor | No | No | — |
| Scientific reviewer | No | No | — |
| Administrator | No (requires second admin) | Yes | `aph_manage_user_role()` |

An administrator **cannot** change their own role through `aph_manage_user_role`.
This prevents self-promotion and requires a second authorized administrator
for sensitive role changes, including self-role changes.

### What administrators may NOT do

- Ordinary users promoting themselves — blocked by column-level REVOKE + RLS
- Editors assigning administrator roles — blocked by `aph_manage_user_role` caller check
- Reviewers assigning administrator roles — blocked by `aph_manage_user_role` caller check
- Unauthenticated callers — `auth.uid()` returns NULL, function raises exception
- Direct SQL UPDATE on `role` column — blocked by column-level REVOKE

---

## Security Regression Tests (New in Phase 02.2)

| # | Test Function | Purpose |
|---|---------------|---------|
| 1 | `test_no_old_new_in_rls_policies` | No OLD/NEW references in any RLS policy expression |
| 2 | `test_column_level_privileges_exclude_privileged_profile_columns` | REVOKE/GRANT on privileged columns |
| 3 | `test_role_management_function_exists` | `aph_manage_user_role` is SECURITY DEFINER with safe search_path |
| 4 | `test_role_management_prevents_self_promotion` | Self-role-change is prevented |
| 5 | `test_role_management_audits_changes` | Role changes generate audit log entries |
| 6 | `test_review_timestamp_enforced` | `reviewed_at` is NOT NULL |
| 7 | `test_reviewer_id_has_foreign_key` | `reviewer_id` references `user_profiles` |
| 8 | `test_self_review_trigger_exists` | No-self-review trigger exists |
| 9 | `test_content_reviews_no_delete_policy` | No DELETE on content_reviews |
| 10 | `test_editors_cannot_approve_own_evidence_in_rls` | RLS self-review prevention (defense in depth) |

### Removed test

`test_users_cannot_modify_own_role` — removed because it required `OLD.role`
in an RLS policy expression, which is invalid PostgreSQL. Replaced by
`test_column_level_privileges_exclude_privileged_profile_columns`.

### Total test count

| Phase | Test Functions | Executed pytest Cases |
|-------|---------------|----------------------|
| Phase 02 (pre-02.2) | 12 | 198 |
| Phase 02.2 additions | 13 | 33 |
| **Phase 02.2 total** | **25** | **231** |

All 231 tests pass. Exit code 0.

---

## Files Changed

| File | Change |
|------|--------|
| `database/migrations/005_scientific_evidence_and_reviews.sql` | Added `reviewed_at NOT NULL`, `reviewer_id` FK, `assert_no_self_review()` trigger, removed invalid subquery CHECK |
| `database/migrations/010_rls_and_storage_policies.sql` | Removed OLD/NEW from RLS; added column-level REVOKE/GRANT; added `aph_manage_user_role()`; added `aph_manage_user_profile()`; added content_reviews self-review prevention in RLS |
| `backend/tests/test_database_schema.py` | Removed OLD.role test; added 10 new security regression tests |
| `docs/DATABASE_SECURITY.md` | Updated security principles, column-level security, SECURITY DEFINER functions, known risks |
| `docs/RLS_POLICY_MATRIX.md` | Updated user_profiles row, added column-level security table, added SECURITY DEFINER functions table |
| `docs/DATABASE_SCHEMA.md` | Updated content_reviews description, added column-level security section, added SECURITY DEFINER functions section |
| `docs/DEVELOPMENT_STATUS.md` | Updated test counts, added column-level security and review traceability |
| `docs/PHASE_02_2_REMEDIATION_REPORT.md` | New — this report |

---

## Validation Results

| Validation | Result |
|------------|--------|
| pglast native PostgreSQL grammar (11 migrations) | 11/11 PASS |
| Security regression tests (pytest) | 231/231 PASS |
| Health check (`scripts/health_check.py`) | 95/95 PASS |
| SQLAlchemy model imports | 39/39 models import |
| Secret scan (git diff) | No secrets found |
| `.env` / `.venv` / `node_modules` committed | None |

---

## PostgreSQL Test Environment

**Status:** BLOCKED — No PostgreSQL server available in the Arena environment.

**Blocker details:**
- No `psql`, `pg_isready`, `initdb`, or `postgres` binary installed
- `apt` is available but installing PostgreSQL server would be a large system dependency, which should not be done blindly per project constraints
- Docker is not installed
- No database environment variables (`DATABASE_URL`, `PGHOST`, etc.) configured

**Reproducible test plan for external Supabase development project:**

1. Provision a Supabase development project (or local PostgreSQL 15+)
2. Apply migrations 001–011 in order
3. Run the following runtime validation:
   ```sql
   -- Test 1: Ordinary user cannot update role column
   UPDATE public.user_profiles SET role = 'administrator' WHERE user_id = '<test-user-id>';
   -- Expected: ERROR - column-level privilege denial

   -- Test 2: Administrator can change another user's role via function
   SELECT aph_manage_user_role('<target-user-id>', 'editor');
   -- Expected: success + audit_log entry

   -- Test 3: Administrator cannot change own role via function
   SELECT aph_manage_user_role('<admin-user-id>', 'editor');
   -- Expected: ERROR - self-role-change prevented

   -- Test 4: Editor cannot insert verified evidence
   INSERT INTO public.drug_evidence (...) VALUES (..., TRUE, ...);
   -- Expected: ERROR - RLS WITH CHECK denial

   -- Test 5: Reviewer cannot review own evidence
   INSERT INTO public.content_reviews (...) VALUES (..., '<evidence-creator-id>', ...);
   -- Expected: ERROR - trigger assertion

   -- Test 6: No DELETE on content_reviews
   DELETE FROM public.content_reviews WHERE id = '<review-id>';
   -- Expected: ERROR - no DELETE policy
   ```

**Note:** Never use production credentials. Use a dedicated development
environment with test data only.

---

## Remaining Risks (documented, not fixed)

1. **No live PostgreSQL validation:** RLS policies, column-level privileges,
   and SECURITY DEFINER functions were validated statically (pglast parsing +
   regex inspection), not executed against a running database. Runtime
   validation against a provisioned database is required before production use.

2. **Column-level privileges apply to administrators too:** Administrators
   cannot directly UPDATE `role` or `is_active` on `user_profiles` even through
   their RLS policies — they must use `aph_manage_user_role` /
   `aph_manage_user_profile`. This is intentional but requires the backend
   API to route admin profile updates through these functions.

3. **Service-role compromise:** The Supabase service role bypasses both RLS
   and column-level privileges. Service-role keys must never be exposed to
   client applications.

4. **Function ownership:** SECURITY DEFINER functions run as the function
   owner. If the function owner is compromised, all protections are void.
   Functions should be owned by a restricted postgres role, not a superuser.

---

## Git Status

- Branch: `arena/fcc02306-abdulmajeedpharma`
- Working tree: changes not committed (pending review)
- No `.env`, `.venv`, `node_modules`, database credentials, or private keys
- No commit, push, or PR created — pending user review

---

**STOP: Phase 02.2 complete. Do not begin Phase 03.**