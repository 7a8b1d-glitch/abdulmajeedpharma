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
| content_reviews | scientific_reviewer, administrator | ✅ | ✅ | ✅ | ✅ | Review workflow |
| content_reviews | editor | ✅ (own evidence) | ❌ | ❌ | ❌ | Own evidence reviews |

### Users & Profiles

| Table | Role | SELECT | INSERT | UPDATE | DELETE | Policy basis |
|-------|------|--------|--------|--------|--------|--------------|
| user_profiles | user | ✅ (own) | ❌ | ✅ (own, limited fields) | ❌ | Own profile |
| user_profiles | administrator | ✅ (all) | ❌ | ✅ (all) | ❌ | Admin manage |

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
`admins_manage_user_profiles`, `editors_insert_draft_drugs`).

## Security Checks Performed

- ✅ RLS enabled on all 39 tables
- ✅ No `USING (true)` on private tables
- ✅ `auth.uid()` used for user identification
- ✅ `aph_current_user_role()` is SECURITY DEFINER with restricted `search_path`
- ✅ EXECUTE revoked from PUBLIC on helper functions
- ✅ `audit_logs.change_metadata` CHECK constraint rejects secret keys
- ✅ `user_profiles.role` CHECK constraint limits to 4 allowed roles
