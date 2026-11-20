# Abdulmajeedpharma (APH) — Database Security

**Project Owner:** Dr. Abdulmajeed Abdullah Almakhedhi  
**Phase:** Phase 02 — Database Foundation  
**Target:** Supabase PostgreSQL

## Identity Provider

Supabase Auth is the intended identity provider. Application user profiles
live in `public.user_profiles` with `user_id` referencing `auth.users(id)`.

## Roles

| Role | Description |
|------|-------------|
| `user` | Ordinary user; owns profile, conversations, messages, notifications |
| `editor` | Creates and edits draft catalog content; cannot approve sensitive scientific content |
| `scientific_reviewer` | Reviews scientific evidence; submits review decisions and notes |
| `administrator` | Manages catalog, users, workflows, operational data; auditable |

Roles are stored in `user_profiles.role` with a CHECK constraint limiting
values to the four roles above.

## Passwords & Secrets

- **No plaintext passwords** are stored in this database. Supabase Auth
  handles password hashing and verification.
- **No access tokens, service keys, or secrets** are stored in `audit_logs`
  or any other table. A CHECK constraint on `audit_logs.change_metadata`
  rejects keys named `password`, `access_token`, or `service_key`.
- Supabase **service-role keys** are backend-only. They must never be
  exposed to the Flutter mobile app or the Next.js admin frontend.
- `.env.example` contains placeholder names only; real credentials are
  never committed.

## Row Level Security (RLS)

RLS is enabled on **all 39 tables**. Policies are defined in
`database/migrations/010_rls_and_storage_policies.sql` and summarized in
`docs/RLS_POLICY_MATRIX.md`.

### Security principles applied

1. **`auth.uid()`** is used to identify the authenticated user in policy
   expressions.
2. **No unrestricted `USING (true)`** policies on private tables
   (user_profiles, conversations, messages, notifications, import_*,
   audit_logs, sync_records, content_reviews, drug_evidence).
3. **Ordinary users cannot self-assign privileged roles.** Column-level
   privileges REVOKE UPDATE on `role`, `is_active`, and `email_verified`
   from `authenticated`, and GRANT UPDATE only on self-service columns
   (`full_name`, `phone`, `country_id`, `language`). The
   `users_update_own_profile` RLS policy restricts updates to the user's
   own row (`user_id = auth.uid()`). No `OLD`/`NEW` references are used
   in RLS policy expressions (they are invalid in the RLS context).
4. **Role changes require a controlled workflow.** The SECURITY DEFINER
   function `aph_manage_user_role()` allows only verified administrators
   to change another user's role. It validates role values, prevents
   self-role-change, records an audit log entry, and runs with
   `SET search_path = pg_temp, public`. EXECUTE is revoked from PUBLIC
   and granted only to `authenticated` (administrators pass the internal
   role check; all others are rejected).
5. **Editors cannot independently approve sensitive scientific content.**   Editors
   can only insert/update evidence with `is_verified = FALSE` (`WITH CHECK`
   clauses enforce this on both INSERT and UPDATE). Only `scientific_reviewer`
   or `administrator` can approve evidence (`is_verified = TRUE`) via
   controlled workflows outside the editor policies.

6. **Reviewer identity is bound to authenticated caller.** RLS policies on
   `content_reviews` require `reviewer_id = auth.uid()` in both INSERT and
   UPDATE policies, preventing a reviewer from forging another user's UUID
   as the reviewer. A database trigger (`assert_no_self_review`, migration
   012) prevents reviewers from reviewing their own evidence claims.
   `reviewed_at` is NOT NULL and `reviewer_id` references `user_profiles`.
6. **Review history is append-only and traceable.** Reviewers/admins can
   SELECT, INSERT, and UPDATE content_reviews but cannot DELETE them.
   `reviewed_at` is NOT NULL, `reviewer_id` references `user_profiles`, and
   a database trigger prevents reviewers from reviewing their own evidence
   claims. Corrections are made via superseding reviews.
7. **Administrators cannot delete user profiles.** Admin policies on
   user_profiles cover SELECT, INSERT, and UPDATE only — no DELETE.
   Account deactivation uses `is_active = FALSE` rather than profile deletion.
   Profile field updates by administrators go through the SECURITY DEFINER
   function `aph_manage_user_profile()`.
8. **FORCE RLS on user-private tables.** `user_profiles`, `conversations`,
   `conversation_participants`, `messages`, `message_read_receipts`, and
   `notifications` use `FORCE ROW LEVEL SECURITY` so RLS applies even to
   the table owner (preventing bypass via ownership).
9. **SECURITY DEFINER functions** (`aph_current_user_role`,
   `aph_manage_user_role`, `aph_manage_user_profile`) use a
   restricted `search_path = pg_temp, public` and execution is revoked
   from PUBLIC.
10. **Audit logs are append-only for application roles.** The backend
    service writes audit entries using the service role (RLS bypass);
    application roles can only SELECT. All privileged operations through
    `aph_manage_user_role` and `aph_manage_user_profile` generate audit
    log entries.

### Policy summary by table category

| Category | Tables | Read | Write |
|----------|--------|------|-------|
| Public reference | countries, body_systems, therapeutic_classes, pharmacological_classes, drug_classes, active_ingredients, drugs, brand_products, etc. | Authenticated: `is_active = TRUE` | Admin/editor (owners for drafts) |
| Scientific evidence | drug_evidence | Authenticated: `is_verified = TRUE`; reviewers: all | Editors/admins: insert unverified drafts only; reviewers: read all |
| Content reviews | content_reviews | Reviewers/admins; editors: own evidence reviews | Reviewers/admins: SELECT+INSERT+UPDATE (no DELETE) |
| User profiles | user_profiles | Own profile; admins: all | Own profile (role/email_verified/is_active frozen); admins: all (no DELETE) |
| Messaging | conversations, messages, attachments, receipts | Participants only | Sender (messages); participants (membership, receipts) |
| Notifications | notifications | Own notifications | Own (mark read); system (insert) |
| Import | import_batches, items, errors | Uploader: own batches; admins: all | Uploader: insert own; admins: all |
| Audit | audit_logs | Admins only | Service role only (no app role write) |
| Sync | sync_records | Admins only | Admins only |

### FORCE RLS Tables

| Table | Reason |
|-------|--------|
| `user_profiles` | Contains private user data; owner bypass must be prevented |
| `conversations` | Private user messaging data |
| `conversation_participants` | Private user membership data |
| `messages` | Private user message content |
| `message_read_receipts` | Private user read-status data |
| `notifications` | Private user notification data |

FORCE RLS is NOT applied to: import tables, audit_logs, sync_records,
drug_evidence, content_reviews (service role writes these), or public reference
tables (no private data).

## Storage Policies

Supabase Storage policies (for product images and message attachments)
should be configured to:
- Allow public read on published product images.
- Restrict attachment access to conversation participants.
- Restrict write to authenticated users with appropriate roles.

Storage path metadata is stored in `drug_images.storage_path` and
`message_attachments.storage_path` but paths are not exposed to
unrelated users via RLS.

## Auditability

`audit_logs` captures: actor, actor_role, action, entity_type, entity_id,
timestamp, safe change_metadata, ip_address, user_agent. No secrets are
stored. All privileged operations should be accompanied by an audit log
entry written by the backend service.

## Column-Level Security

| Column | Privilege | Rationale |
|--------|-----------|-----------|
| `full_name` | GRANT UPDATE to authenticated | Self-service profile field |
| `phone` | GRANT UPDATE to authenticated | Self-service profile field |
| `country_id` | GRANT UPDATE to authenticated | Self-service profile field |
| `language` | GRANT UPDATE to authenticated | Self-service profile field |
| `role` | REVOKED from authenticated | Only via `aph_manage_user_role()` |
| `is_active` | REVOKED from authenticated | Only via `aph_manage_user_profile()` |
| `email_verified` | REVOKED from authenticated | Managed by Supabase Auth |
| `email` | No UPDATE | Managed by Supabase Auth |
| `user_id` | No UPDATE | Primary key, immutable |

All column-level privileges work together with RLS: RLS restricts which
rows can be accessed, column-level privileges restrict which columns can
be modified.

## Known Risks

- No real PostgreSQL database was available in Phase 02/02.2; RLS policies,
  column-level privileges, and SECURITY DEFINER functions were validated
  statically (SQL parsing via pglast), not executed against a live database.
- RLS policy performance with subqueries on `user_profiles` should be
  monitored under load; consider materialized role lookups if needed.
- `SECURITY DEFINER` functions must be kept ownership-restricted to prevent
  privilege escalation. `aph_manage_user_role` and `aph_manage_user_profile`
  run as the function owner and bypass column-level privilege checks for
  the caller — this is intentional but requires careful ownership management.
- Service-role compromise could bypass all RLS and column-level protections.
- Column-level privileges apply to all authenticated users including
  administrators; administrators must use `aph_manage_user_role` /
  `aph_manage_user_profile` for privileged operations.
