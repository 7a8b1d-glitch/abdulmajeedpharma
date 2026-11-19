# Abdulmajeedpharma (APH) — Database Schema

**Project Owner:** Dr. Abdulmajeed Abdullah Almakhedhi  
**Phase:** Phase 02 — Database Foundation  
**Target:** Supabase PostgreSQL

## Overview

This document describes the PostgreSQL database schema for APH, defined via
versioned SQL migrations under `database/migrations/` and mirrored by
SQLAlchemy models under `backend/app/models/`.

No real drug, patient, manufacturer, or supplier data is seeded. Only
reference data (18 body systems, Yemen country) is included.

## Migration Execution Order

| # | File | Purpose |
|---|------|---------|
| 001 | `001_extensions_and_helpers.sql` | pgcrypto, pg_trgm extensions; `set_updated_at()` trigger helper; `aph_current_user_role()` helper |
| 002 | `002_geography_and_classification.sql` | countries, body_systems, therapeutic_classes, pharmacological_classes, drug_classes |
| 003 | `003_drug_catalog.sql` | active_ingredients, drugs, drug_ingredients, drug_class_links, drug_indications, drug_contraindications, drug_adverse_effects, drug_interactions, drug_dosage_information, drug_special_populations, drug_images |
| 004 | `004_companies_and_market.sql` | manufacturers, marketing_authorization_holders, suppliers, distributors, brand_products, product_presentations, product_markets, product_registration_records |
| 005 | `005_scientific_evidence_and_reviews.sql` | scientific_sources, drug_evidence, content_reviews |
| 006 | `006_users_and_permissions.sql` | user_profiles (linked to Supabase auth.users) |
| 007 | `007_messaging_and_notifications.sql` | conversations, conversation_participants, messages, message_attachments, message_read_receipts, notifications |
| 008 | `008_imports_and_audit.sql` | import_batches, import_batch_items, import_errors, audit_logs, sync_records |
| 009 | `009_indexes_and_search.sql` | Full-text search vectors, trigram indexes, composite indexes |
| 010 | `010_rls_and_storage_policies.sql` | RLS enablement, ownership columns, role-based policies |
| 011 | `011_seed_reference_data.sql` | Yemen country, 18 body systems (idempotent) |

Migrations are safe to apply in the documented order and use `IF NOT EXISTS`
/`ON CONFLICT DO NOTHING` where appropriate for idempotency.

## Table Reference

### Reference & Classification

| Table | Purpose | Bilingual |
|-------|---------|-----------|
| `countries` | ISO 3166-1 alpha-2 country list; Yemen flagged | name_en, name_ar |
| `body_systems` | 18 top-level body systems (seeded) | name_en, name_ar, description_en, description_ar |
| `therapeutic_classes` | Therapeutic classes within a body system | name_en, name_ar, description_en, description_ar |
| `pharmacological_classes` | Pharmacological classes within a therapeutic class | name_en, name_ar, description_en, description_ar |
| `drug_classes` | Drug classes within a pharmacological class | name_en, name_ar, description_en, description_ar |

### Drug Catalog

| Table | Purpose | Bilingual |
|-------|---------|-----------|
| `active_ingredients` | Generic active ingredients (INN) | name_en, name_ar, description_en, description_ar |
| `drugs` | Generic drug records (NOT brand products) | name_en, name_ar, generic_name_en, generic_name_ar, description_en, description_ar |
| `drug_ingredients` | Many-to-many: drug ↔ active ingredient (with strength) | — |
| `drug_class_links` | Many-to-many: drug ↔ drug class | — |
| `drug_indications` | Indications for a drug | indication_en, indication_ar |
| `drug_contraindications` | Contraindications for a drug | contraindication_en, contraindication_ar |
| `drug_adverse_effects` | Adverse effects for a drug | effect_en, effect_ar |
| `drug_interactions` | Pairwise drug interactions (de-duplicated) | interaction_en, interaction_ar |
| `drug_dosage_information` | Dosage info per population | dosage_en, dosage_ar |
| `drug_special_populations` | Guidance for special populations (pregnancy, renal, etc.) | guidance_en, guidance_ar |
| `drug_images` | Image references for drugs | alt_text_en, alt_text_ar |

### Companies & Market

| Table | Purpose | Bilingual |
|-------|---------|-----------|
| `manufacturers` | Drug manufacturers | name_en, name_ar, address_en, address_ar |
| `marketing_authorization_holders` | Marketing authorization holders | name_en, name_ar, address_en, address_ar |
| `suppliers` | Suppliers | name_en, name_ar, address_en, address_ar |
| `distributors` | Distributors | name_en, name_ar, address_en, address_ar |
| `brand_products` | Branded/marketed products (NOT generic drugs) | brand_name_en, brand_name_ar, description_en, description_ar |
| `product_presentations` | Strength, form, route, package, barcode | dosage_form_en/ar, route_en/ar, package_unit_en/ar |
| `product_markets` | Country-level market availability | notes_en, notes_ar |
| `product_registration_records` | Registration records per country | market_notes_en, market_notes_ar |

### Scientific Evidence & Review

| Table | Purpose | Bilingual |
|-------|---------|-----------|
| `scientific_sources` | Scientific references (journals, regulatory docs) | title, citation_text |
| `drug_evidence` | Evidence claims linked to drug/product + source | claim_text_en, claim_text_ar |
| `content_reviews` | Review workflow records | review_notes |

### Users & Access

| Table | Purpose |
|-------|---------|
| `user_profiles` | Linked to Supabase `auth.users`; role-based access |

### Messaging & Notifications

| Table | Purpose |
|-------|---------|
| `conversations` | User-to-administration conversations |
| `conversation_participants` | Authorized participants |
| `messages` | Messages within conversations |
| `message_attachments` | Attachment metadata + storage path |
| `message_read_receipts` | Read status per user per message |
| `notifications` | User notifications with delivery/read status |

### Import & Audit

| Table | Purpose |
|-------|---------|
| `import_batches` | Import batch tracking (CSV, XLSX, JSON, ZIP) |
| `import_batch_items` | Per-row import items |
| `import_errors` | Import error details |
| `audit_logs` | Immutable audit trail (no secrets stored) |
| `sync_records` | Foundation for future offline sync |

## Primary Keys

All tables use UUID primary keys (`String(36)`), generated with
`gen_random_uuid()` from the `pgcrypto` extension.

## Timestamps

All tables include `created_at` (`timestamptz`, default `now()`).
Most tables include `updated_at` (`timestamptz`, auto-updated via
`set_updated_at()` trigger). `audit_logs` uses `timestamp`; `message_read_receipts`
uses `created_at` and `read_at`.

## Constraints

- **Unique:** `code` on reference tables; composite uniques on link tables
  (e.g. `drug_ingredients(drug_id, active_ingredient_id)`).
- **Check:** Controlled status values (registration status, availability,
  review status, user role, message type, notification type, import format,
  sync operation/status, etc.).
- **Foreign keys:** All relationships use `ON DELETE CASCADE` or
  `ON DELETE RESTRICT`/`SET NULL` as appropriate.

## Indexes

- B-tree indexes on foreign keys and status columns.
- GIN trigram indexes on `*_en` and `*_ar` name columns for fuzzy search.
- GIN full-text search (`tsvector`) on `drugs`, `active_ingredients`,
  `brand_products` (simple config; Arabic stemming is limited — see
  docs/DATABASE_SETUP.md).

## Seed Data

- **18 body systems** with stable codes and English names (Arabic names where
  reliable translations are available).
- **Yemen** as a country (code `YE`).
- Seed is idempotent (`ON CONFLICT (code) DO NOTHING`).
- No fake drug, manufacturer, supplier, or scientific reference data.

## Backend Integration

SQLAlchemy models under `backend/app/models/` mirror the migration tables.
The `Base` declarative class uses `AsyncAttrs` for async PostgreSQL access.
Database configuration is via `DATABASE_URL` environment variable
(see `.env.example`).

## Known Limitations

- Arabic full-text search stemming is not natively optimal in PostgreSQL
  without external dictionaries.
- `pg_trgm` fuzzy search provides approximate matching but is not a
  complete Arabic search solution.
- No real PostgreSQL database was available in the Phase 02 environment;
  migrations were validated statically (SQL parsing + SQLAlchemy model
  consistency), not executed against a live database.
