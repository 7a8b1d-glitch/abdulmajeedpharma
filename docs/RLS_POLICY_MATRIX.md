# Abdulmajeedpharma (APH) — RLS Policy Matrix

**Project Owner:** Dr. Abdulmajeed Abdullah Almakhedhi  
**Phase:** Phase 02 — Database Foundation

## Roles

| Role | Capabilities |
|------|-------------|
| `user` | Own profile, conversations, messages, notifications. Cannot modify catalog. |
| `editor` | Create/edit draft catalog content. Cannot approve sensitive scientific content. |
| `scientific_reviewer` | Review scientific content. Submit review decisions and notes. |
| `administrator` | Manage catalog, users, workflows, operational data. Auditable. |

## Policy Matrix

### Public Reference Tables (read-only public content)

| Table | Role | SELECT | INSERT | UPDATE | DELETE | Policy basis |
|-------|------|--------|--------|--------|--------|--------------|
| countries | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| body_systems | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| therapeutic_classes | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| pharmacological_classes | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| drug_classes | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| active_ingredients | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| drugs | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| drug_ingredients | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| drug_class_links | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| drug_indications | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| drug_contraindications | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| drug_adverse_effects | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| drug_interactions | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| drug_dosage_information | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| drug_special_populations | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| drug_images | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| manufacturers | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| marketing_authorization_holders | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| suppliers | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| distributors | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| brand_products | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| product_presentations | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| product_markets | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| product_registration_records | authenticated | ✅ (approved status) | ❌ | ❌ | ❌ | Public read |
| scientific_sources | authenticated | ✅ (is_active=TRUE) | ❌ | ❌ | ❌ | Public read |
| drug_evidence | authenticated | ✅ (is_verified=TRUE) | ❌ | ❌ | ❌ | Verified only |

### Catalog Write (editors/administrators)

| Table | Role | INSERT | UPDATE | DELETE | Policy basis |
|-------|------|--------|--------|--------|--------------|
| active_ingredients | editor, administrator | ✅ (own, draft) | ✅ (own, inactive) | ✅ (admin only) | Ownership + role |
| drugs | editor, administrator | ✅ (own, draft) | ✅ (own, inactive) | ✅ (admin only) | Ownership + role |
| brand_products | editor, administrator | ✅ (own, draft) | ✅ (own, inactive) | ✅ (admin only) | Ownership + role |
| product_presentations | administrator | ✅ | ✅ | ✅ | Admin only |
| product_markets | administrator | ✅ | ✅ | ✅ | Admin only |
| product_registration_records | administrator | ✅ | ✅ | ✅ | Admin only |
| manufacturers | administrator | ✅ | ✅ | ✅ | Admin only |
| marketing_authorization_holders | administrator | ✅ | ✅ | ✅ | Admin only |
| suppliers | administrator | ✅ | ✅ | ✅ | Admin only |
| distributors | administrator | ✅ | ✅ | ✅ | Admin only |

### Scientific Evidence & Reviews

| Table | Role | SELECT | INSERT | UPDATE | DELETE | Policy basis |
|-------|------|--------|--------|--------|--------|--------------|
| drug_evidence | authenticated | ✅ (is_verified=TRUE) | ❌ | ❌ | ❌ | Verified public |
| drug_evidence | editor, administrator | ✅ | ✅ (own, draft) | ✅ (own) | ❌ | Ownership + role |
| drug_evidence | scientific_reviewer, administrator | ✅ (all) | ❌ | ❌ | ❌ | Review access |
| content_reviews | scientific_reviewer, administrator | ✅ | ✅ | ✅ | ❌ | Review workflow — append-only; no DELETE; reviewer_id = auth.uid() |
| content_reviews | editor | ✅ (own evidence) | ❌ | ❌ | ❌ | Own evidence reviews — cannot set reviewer_id to another user |
| content_reviews | editor | ✅ (own evidence) | ❌ | ❌ | ❌ | Own evidence reviews |

### Users & Profiles

| Table | Role | SELECT | INSERT | UPDATE | DELETE | Policy basis |
|-------|------|--------|--------|--------|--------|--------------|
| user_profiles | user | ✅ (own) | ❌ | ✅ (own, full_name/phone/country_id/language only) | ❌ | Own profile — column-level REVOKEs block role/is_active/email_verified |
| user_profiles | administrator | ✅ (all) | ✅ (via aph_manage_user_role/aph_manage_user_profile) | ✅ (via SECURITY DEFINER functions) | ❌ | Admin manage — no DELETE; deactivation via is_active = FALSE |

### Messaging & Notifications

| Table | Role | SELECT | INSERT | UPDATE | DELETE | Policy basis |
|-------|------|--------|--------|--------|--------|--------------|
| conversations | authenticated | ✅ (participant) | ✅ (admin only) | ❌ | ❌ | Participation |
| conversation_participants | authenticated | ✅ (own) | ✅ (own) | ✅ (own) | ✅ (own) | Own membership |
| messages | authenticated | ✅ (participant) | ✅ (sender) | ❌ | ❌ | Participation/sender |
| message_attachments | authenticated | ✅ (participant) | ❌ | ❌ | ❌ | Participation |
| message_read_receipts | authenticated | ✅ (own) | ✅ (own) | ✅ (own) | ✅ (own) | Own receipt |
| notifications | user | ✅ (own) | ❌ | ✅ (own, mark read) | ❌ | Own notifications |

### Import Management

| Table | Role | SELECT | INSERT | UPDATE | DELETE | Policy basis |
|-------|------|--------|--------|--------|--------|--------------|
| import_batches | user | ✅ (own) | ✅ (own) | ❌ | ❌ | Own batches |
| import_batches | administrator | ✅ (all) | ❌ | ✅ (all) | ❌ | Admin manage |
| import_batch_items | user | ✅ (own batch) | ❌ | ❌ | ❌ | Own batch |
| import_errors | user | ✅ (own batch) | ❌ | ❌ | ❌ | Own batch |

### Audit & Sync

| Table | Role | SELECT | INSERT | UPDATE | DELETE | Policy basis |
|-------|------|--------|--------|--------|--------|--------------|
| audit_logs | administrator | ✅ (all) | ❌ (service role only) | ❌ | ❌ | Admin read; service writes |
| sync_records | administrator | ✅ (all) | ✅ (all) | ✅ (all) | ❌ | Admin manage |

## Policy Naming Convention

Policies in `010_rls_and_storage_policies.sql` follow the pattern:
`<role>_<action>_<scope>_<table>` (e.g. `users_read_own_profile`,
`admins_manage_user_profiles_select`, `editors_insert_draft_drugs`).

Each operation (SELECT, INSERT, UPDATE, DELETE) has a separate policy because
PostgreSQL does not allow comma-separated operations in the `FOR` clause.

## FORCE ROW LEVEL SECURITY

FORCE RLS ensures policies apply even to the table owner, preventing bypass
via ownership. Applied to:

| Table | Reason |
|-------|--------|
| `user_profiles` | Contains private user data; owner bypass must be prevented |
| `conversations` | Private user messaging data |
| `conversation_participants` | Private user membership data |
| `messages` | Private user message content |
| `message_read_receipts` | Private user read-status data |
| `notifications` | Private user notification data |

NOT applied to: import tables, audit_logs, sync_records, drug_evidence,
content_reviews (service role writes these), or public reference tables
(no private data).

## Column-Level Security (user_profiles)

Column-level privileges work with RLS: RLS restricts row access, column-level
privileges restrict column modification.

| Column | UPDATE on `authenticated` | Privileged? | Modified via |
|--------|---------------------------|-------------|--------------|
| `full_name` | ✅ GRANTED | No | Direct UPDATE (own row only) |
| `phone` | ✅ GRANTED | No | Direct UPDATE (own row only) |
| `country_id` | ✅ GRANTED | No | Direct UPDATE (own row only) |
| `language` | ✅ GRANTED | No | Direct UPDATE (own row only) |
| `role` | ❌ REVOKED | Yes | `aph_manage_user_role()` (admin only) |
| `is_active` | ❌ REVOKED | Yes | `aph_manage_user_profile()` (admin only) |
| `email_verified` | ❌ REVOKED | Yes | Supabase Auth only |
| `email` | ❌ No UPDATE | Yes | Supabase Auth only |
| `user_id` | ❌ No UPDATE (PK) | Yes | Immutable |

## SECURITY DEFINER Functions

| Function | Purpose | Caller Restriction | search_path | EXECUTE |
|----------|---------|-------------------|-------------|---------|
| `aph_current_user_role()` | Resolve caller's application role | Revoked from PUBLIC | pg_temp, public | Revoked from PUBLIC |
| `aph_manage_user_role(UUID, VARCHAR)` | Change another user's role | Administrator only | pg_temp, public | Revoked from PUBLIC |
| `aph_manage_user_profile(...)` | Update non-role profile fields | Administrator only | pg_temp, public | Revoked from PUBLIC |

## Security Checks Performed

- ✅ RLS enabled on all 39 tables
- ✅ FORCE RLS on 6 user-private tables
- ✅ No `USING (true)` on private tables
- ✅ `auth.uid()` used for user identification
- ✅ No `OLD`/`NEW` references in RLS policy expressions (invalid in RLS context)
- ✅ Column-level REVOKE on `role`, `is_active`, `email_verified` from `authenticated`
- ✅ Column-level GRANT on `full_name`, `phone`, `country_id`, `language` to `authenticated`
- ✅ `aph_manage_user_role()` is SECURITY DEFINER with restricted `search_path`
- ✅ `aph_manage_user_role()` prevents self-role-change
- ✅ `aph_manage_user_role()` validates role values
- ✅ `aph_manage_user_role()` records audit log entries (old_role, new_role)
- ✅ EXECUTE revoked from PUBLIC on all SECURITY DEFINER functions
- ✅ `audit_logs.change_metadata` CHECK constraint rejects secret keys
- ✅ `user_profiles.role` CHECK constraint limits to 4 allowed roles
- ✅ Editors cannot set `is_verified = TRUE` on evidence insert/update
- ✅ Reviewers cannot DELETE content_reviews (append-only)
- ✅ Administrators cannot DELETE user_profiles (no DELETE policy)
- ✅ No `CREATE POLICY IF NOT EXISTS` (invalid PostgreSQL syntax)
- ✅ Expression-based UNIQUE index on drug_interactions (no expression in table constraint)
- ✅ `content_reviews.reviewed_at` is NOT NULL
- ✅ `content_reviews.reviewer_id` references `user_profiles.user_id`
- ✅ Trigger prevents reviewers from reviewing their own evidence claims
- ✅ RLS policies on content_reviews include self-review prevention (defense in depth)
- ✅ reviewer_id = auth.uid() in content_reviews INSERT and UPDATE policies (prevents reviewer_id forgery)
- ✅ GRANT EXECUTE on aph_manage_user_role and aph_manage_user_profile to authenticated
- ✅ EXECUTE revoked from PUBLIC on all SECURITY DEFINER functions
