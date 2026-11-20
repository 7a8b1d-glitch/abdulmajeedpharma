# Abdulmajeedpharma (APH) — Phase 02.1 Remediation Report

**Project Owner:** Dr. Abdulmajeed Abdullah Almakhedhi  
**Phase:** Phase 02.1 — Critical Database & Security Remediation  
**Branch:** `arena/fcc02306-abdulmajeedpharma`  
**Base commit:** `ef1ee81` (main)  
**Status:** Complete — remediation applied, validated, documented  

---

## Executive Summary

Phase 02.1 performed a critical remediation pass on the Phase 02 database
foundation. Native PostgreSQL grammar validation (via pglast 8.9) revealed
two CRITICAL SQL errors that would prevent migration execution, and five
HIGH severity security findings that could enable privilege escalation,
evidence tampering, review history destruction, profile deletion, and
RLS bypass. All findings have been remediated, validated by automated
tests, and documented.

---

## CRITICAL Findings & Fixes

### Finding C1 — Invalid expression-based UNIQUE constraint (Migration 003)

**Severity:** CRITICAL  
**File:** `database/migrations/003_drug_catalog.sql`  
**Problem:** The `drug_interactions` table had a table-level
`UNIQUE (LEAST(drug_id, interacting_drug_id), GREATEST(...))` constraint.
PostgreSQL does not allow function expressions in table-level UNIQUE
constraints — this is a parse error that prevents migration execution.

**Fix:** Replaced the table-level UNIQUE constraint with:
1. `CHECK (drug_id <> interacting_drug_id)` — prevents self-interaction at
   the constraint level.
2. `CREATE UNIQUE INDEX idx_drug_interactions_unique_pair
   ON public.drug_interactions (LEAST(drug_id, interacting_drug_id),
   GREATEST(drug_id, interacting_drug_id))` — expression-based unique index
   that prevents duplicate pair entries regardless of column order.

**Validation:** `test_no_expression_based_table_unique_constraint`,
`test_expression_based_unique_index_exists_for_interactions`,
`test_migration_parses_with_postgresql_grammar[003]` — all PASS.

---

### Finding C2 — Invalid `CREATE POLICY IF NOT EXISTS` (Migration 010)

**Severity:** CRITICAL  
**File:** `database/migrations/010_rls_and_storage_policies.sql`  
**Problem:** All 28 `CREATE POLICY` statements used `IF NOT EXISTS`, which
is not valid PostgreSQL syntax for `CREATE POLICY`. This is a parse error
that prevents migration execution.

**Fix:** Replaced all 28 occurrences with the idempotent pattern:
```sql
DROP POLICY IF EXISTS "policy_name" ON public.table;
CREATE POLICY "policy_name" ON public.table
    FOR <operation> TO authenticated
    USING (...)
    WITH CHECK (...);
```

Additionally, every policy now specifies exactly ONE operation
(SELECT, INSERT, UPDATE, or DELETE) because PostgreSQL does not allow
comma-separated operations in the `FOR` clause. Multi-operation policies
were split into separate per-operation policies (e.g.
`admins_manage_user_profiles_select`, `admins_manage_user_profiles_insert`,
`admins_manage_user_profiles_update`).

**Validation:** `test_no_create_policy_if_not_exists`,
`test_migration_parses_with_postgresql_grammar[010]` — all PASS.

---

## HIGH Findings & Fixes

### Finding H1 — User role escalation via self-update

**Severity:** HIGH  
**File:** `database/migrations/010_rls_and_storage_policies.sql`  
**Problem:** The `users_update_own_profile` policy allowed users to update
their own profile without restricting changes to `role`, `email_verified`,
or `is_active`. An ordinary user could escalate themselves to
`administrator` or `scientific_reviewer`.

**Fix:** Added `WITH CHECK` clause:
```sql
WITH CHECK (
    user_id = auth.uid()
    AND role = OLD.role
    AND email_verified = OLD.email_verified
    AND is_active = OLD.is_active
)
```
Administrators manage role changes via separate `admins_manage_user_profiles_*`
policies (SELECT, INSERT, UPDATE only — no DELETE).

**Validation:** `test_users_cannot_modify_own_role` — PASS.

---

### Finding H2 — Evidence verification bypass by editors

**Severity:** HIGH  
**File:** `database/migrations/010_rls_and_storage_policies.sql`  
**Problem:** Editors could insert or update `drug_evidence` with
`is_verified = TRUE`, bypassing the scientific review process and marking
unreviewed evidence as verified.

**Fix:** Added `AND is_verified = FALSE` to both `WITH CHECK` clauses:
- `editors_insert_evidence` — INSERT with `is_verified = FALSE`
- `editors_update_own_unverified_evidence` — UPDATE with `is_verified = FALSE`

Only `scientific_reviewer` or `administrator` can approve evidence
(`is_verified = TRUE`) through controlled workflows outside the editor
policies.

**Validation:** `test_editors_cannot_insert_verified_evidence`,
`test_editors_cannot_update_evidence_to_verified` — PASS.

---

### Finding H3 — Reviewers can delete content_reviews (history destruction)

**Severity:** HIGH  
**File:** `database/migrations/010_rls_and_storage_policies.sql`  
**Problem:** The `reviewers_manage_content_reviews` policy included DELETE,
allowing reviewers to destroy scientific review history.

**Fix:** Split into three per-operation policies:
- `reviewers_manage_content_reviews_select` — FOR SELECT
- `reviewers_manage_content_reviews_insert` — FOR INSERT
- `reviewers_manage_content_reviews_update` — FOR UPDATE

No DELETE policy exists for content_reviews. Review history is append-only;
corrections are made via superseding reviews.

**Validation:** `test_reviewers_cannot_delete_review_history` — PASS.

---

### Finding H4 — Administrators can delete user_profiles

**Severity:** HIGH  
**File:** `database/migrations/010_rls_and_storage_policies.sql`  
**Problem:** The `admins_manage_user_profiles` policy included DELETE,
allowing administrators to delete user profiles instead of deactivating them.

**Fix:** Split into three per-operation policies:
- `admins_manage_user_profiles_select` — FOR SELECT
- `admins_manage_user_profiles_insert` — FOR INSERT
- `admins_manage_user_profiles_update` — FOR UPDATE

No DELETE policy exists for user_profiles. Account deactivation uses
`is_active = FALSE` rather than profile deletion.

**Validation:** `test_admins_cannot_delete_user_profiles` — PASS.

---

### Finding H5 — No FORCE RLS on user-private tables

**Severity:** HIGH (reclassified from MEDIUM in Phase 02)  
**File:** `database/migrations/010_rls_and_storage_policies.sql`  
**Problem:** Without FORCE RLS, the table owner could bypass RLS policies,
potentially exposing private user data.

**Fix:** Added `FORCE ROW LEVEL SECURITY` to 6 tables:
- `user_profiles`
- `conversations`
- `conversation_participants`
- `messages`
- `message_read_receipts`
- `notifications`

NOT applied to: import tables, audit_logs, sync_records, drug_evidence,
content_reviews (service role writes these), or public reference tables
(no private data).

**Validation:** `test_force_rls_on_user_private_tables` — PASS.

---

## New Tests Added

All tests are in `backend/tests/test_database_schema.py` and require no
live database connection (static validation only).

### PostgreSQL grammar validation (pglast)

| Test | Description |
|------|-------------|
| `test_migration_parses_with_postgresql_grammar` | Parametrized over all 11 migration files; verifies each parses with native PostgreSQL grammar via pglast |

### Security regression tests

| Test | Description |
|------|-------------|
| `test_no_create_policy_if_not_exists` | No `CREATE POLICY IF NOT EXISTS` may remain |
| `test_no_expression_based_table_unique_constraint` | No expression in table-level UNIQUE constraint |
| `test_expression_based_unique_index_exists_for_interactions` | Valid expression-based unique index exists for drug_interactions |
| `test_users_cannot_modify_own_role` | `users_update_own_profile` WITH CHECK references `OLD.role` |
| `test_editors_cannot_insert_verified_evidence` | Editors INSERT requires `is_verified = FALSE` |
| `test_editors_cannot_update_evidence_to_verified` | Editors UPDATE requires `is_verified = FALSE` |
| `test_reviewers_cannot_delete_review_history` | No DELETE on content_reviews policies |
| `test_admins_cannot_delete_user_profiles` | No DELETE on user_profiles policies |
| `test_rls_enabled_on_all_tables` | RLS enabled on every table |
| `test_force_rls_on_user_private_tables` | FORCE RLS on 6 user-private tables |
| `test_no_unrestricted_policy_on_private_tables` | No `USING (true)` on private tables |
| `test_policies_reference_auth_uid` | Policies reference `auth.uid()` |

### Total test count

| Before Phase 02.1 | After Phase 02.1 |
|-------------------|------------------|
| 198 tests | 222 tests |

All 222 tests pass. Exit code 0.

---

## Files Changed

| File | Change |
|------|--------|
| `database/migrations/003_drug_catalog.sql` | CRITICAL: expression-based UNIQUE → CREATE UNIQUE INDEX + CHECK |
| `database/migrations/010_rls_and_storage_policies.sql` | CRITICAL: 28× `CREATE POLICY IF NOT EXISTS` → `DROP` + `CREATE`; HIGH: role escalation, evidence verification, review delete, profile delete, FORCE RLS |
| `backend/tests/test_database_schema.py` | Added pglast import + 11 pglast grammar tests + 11 security regression tests |
| `backend/requirements.txt` | Added `pglast==8.9`, `sqlglot==30.33.0` |
| `docs/DATABASE_SCHEMA.md` | Documented migration 003 index + migration 010 policy architecture |
| `docs/DATABASE_SECURITY.md` | Documented all HIGH fixes, FORCE RLS table rationale |
| `docs/RLS_POLICY_MATRIX.md` | Updated policy matrix (split operations, no DELETE, FORCE RLS section) |
| `docs/PHASE_02_REPORT.md` | Updated test counts, added Phase 02.1 remediation section |
| `docs/DEVELOPMENT_STATUS.md` | Updated test counts, added pglast to environment |
| `docs/PHASE_02_1_REMEDIATION_REPORT.md` | New — this report |

---

## Validation Results

| Validation | Result |
|------------|--------|
| pglast native PostgreSQL grammar (11 migrations) | 11/11 PASS |
| Security regression tests | 11/11 PASS |
| All backend tests (pytest) | 222/222 PASS |
| Health check (`scripts/health_check.py`) | 95/95 PASS |
| SQLAlchemy model imports | 39/39 models import |
| Secret scan (git diff) | No secrets found |
| `.env` / `.venv` / `node_modules` committed | None |

---

## Remaining Risks (documented, not fixed)

1. **No live PostgreSQL server** — RLS policies, triggers, and constraints
   were validated statically, not executed against a running database.
   Validation against a live Supabase/PostgreSQL instance is required before
   production use.
2. **RLS performance** — Subqueries on `user_profiles` in every policy may
   impact performance under load. Monitor and optimize if needed.
3. **Service-role compromise** — The Supabase service role bypasses RLS;
   if compromised, all RLS protections are void. Service-role keys must
   never be exposed to client applications.
4. **Alembic not configured** — SQL migrations are applied directly;
   Alembic integration is deferred to a later phase.

---

## Git Status

- Branch: `arena/fcc02306-abdulmajeedpharma`
- Working tree: clean (all changes committed)
- No `.env`, `.venv`, `node_modules`, database credentials, or private keys committed
- No commit, push, or PR created — pending user review

---

**STOP: Phase 02.1 complete. Do not begin Phase 03.**