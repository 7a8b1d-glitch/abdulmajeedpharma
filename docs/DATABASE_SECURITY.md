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
3. **Ordinary users cannot self-assign privileged roles.** Role changes
   are restricted to administrators.
4. **Editors cannot independently approve sensitive scientific content.**
   Content review decisions require `scientific_reviewer` or
   `administrator` role.
5. **Administrators have controlled access** but remain auditable via
   `audit_logs`.
6. **SECURITY DEFINER functions** (`aph_current_user_role`) use a
   restricted `search_path = pg_temp, public` and execution is revoked
   from PUBLIC.
7. **Audit logs are append-only for application roles.** The backend
   service writes audit entries using the service role (RLS bypass);
   application roles can only SELECT.

### Policy summary by table category

| Category | Tables | Read | Write |
|----------|--------|------|-------|
| Public reference | countries, body_systems, therapeutic_classes, pharmacological_classes, drug_classes, active_ingredients, drugs, brand_products, etc. | Authenticated: `is_active = TRUE` | Admin/editor (owners for drafts) |
| Scientific evidence | drug_evidence | Authenticated: `is_verified = TRUE`; reviewers: all | Editors/admins: insert drafts |
| Content reviews | content_reviews | Reviewers/admins; editors: own evidence reviews | Reviewers/admins only |
| User profiles | user_profiles | Own profile; admins: all | Own profile (limited fields); admins: all |
| Messaging | conversations, messages, attachments, receipts | Participants only | Sender (messages); participants (membership, receipts) |
| Notifications | notifications | Own notifications | Own (mark read); system (insert) |
| Import | import_batches, items, errors | Uploader: own batches; admins: all | Uploader: insert own; admins: all |
| Audit | audit_logs | Admins only | Service role only (no app role write) |
| Sync | sync_records | Admins only | Admins only |

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

## Known Risks

- No real PostgreSQL database was available in Phase 02; RLS policies were
  validated statically (SQL parsing), not executed against a live database.
- RLS policy performance with subqueries on `user_profiles` should be
  monitored under load; consider materialized role lookups if needed.
- `SECURITY DEFINER` function `aph_current_user_role` must be kept
  ownership-restricted to prevent privilege escalation.
