-- Abdulmajeedpharma (APH) — Phase 02 Database Foundation
-- Migration 009: Search foundation indexes
--
-- Additional indexes for frequent searches across Arabic and English names,
-- active ingredients, brand names, classification relationships, barcodes,
-- Yemen registration identifiers, and scientific sources.
--
-- PostgreSQL full-text search and pg_trgm are used where suitable.
--
-- Limitation: Arabic stemming and fuzzy search quality depends on
-- PostgreSQL configuration and is not claimed to be complete search
-- intelligence until implemented and tested.
-- Depends on: 001_extensions_and_helpers.sql through 008_imports_and_audit.sql.

-- Full-text search configuration for bilingual content.
-- We use the built-in 'simple' configuration plus pg_trgm for fuzzy matching.
-- Arabic stemming is not natively optimal in PostgreSQL without external
-- dictionaries; this is documented as a known limitation.

-- ========================================================================
-- Full-text search tsvector columns (populated via triggers)
-- ========================================================================

ALTER TABLE public.drugs ADD COLUMN IF NOT EXISTS search_vector tsvector
    GENERATED ALWAYS AS (
        setweight(to_tsvector('simple', coalesce(name_en, '')), 'A') ||
        setweight(to_tsvector('simple', coalesce(name_ar, '')), 'B') ||
        setweight(to_tsvector('simple', coalesce(generic_name_en, '')), 'C') ||
        setweight(to_tsvector('simple', coalesce(generic_name_ar, '')), 'C')
    ) STORED;

ALTER TABLE public.active_ingredients ADD COLUMN IF NOT EXISTS search_vector tsvector
    GENERATED ALWAYS AS (
        setweight(to_tsvector('simple', coalesce(name_en, '')), 'A') ||
        setweight(to_tsvector('simple', coalesce(name_ar, '')), 'B')
    ) STORED;

ALTER TABLE public.brand_products ADD COLUMN IF NOT EXISTS search_vector tsvector
    GENERATED ALWAYS AS (
        setweight(to_tsvector('simple', coalesce(brand_name_en, '')), 'A') ||
        setweight(to_tsvector('simple', coalesce(brand_name_ar, '')), 'B')
    ) STORED;

-- GIN indexes for full-text search.
CREATE INDEX idx_drugs_search_vector ON public.drugs USING gin (search_vector);
CREATE INDEX idx_active_ingredients_search_vector ON public.active_ingredients USING gin (search_vector);
CREATE INDEX idx_brand_products_search_vector ON public.brand_products USING gin (search_vector);

-- ========================================================================
-- Classification relationship indexes
-- ========================================================================
CREATE INDEX idx_drugs_body_system_lookup ON public.drugs USING gin (name_en gin_trgm_ops, name_ar gin_trgm_ops);

-- ========================================================================
-- Barcode indexes
-- ========================================================================
CREATE INDEX idx_product_presentations_barcode_trgm
    ON public.product_presentations USING gin (barcode gin_trgm_ops);

-- ========================================================================
-- Yemen registration identifier indexes
-- ========================================================================
CREATE INDEX idx_product_registration_records_number_trgm
    ON public.product_registration_records USING gin (registration_number gin_trgm_ops);

-- ========================================================================
-- Scientific source relationship indexes
-- ========================================================================
CREATE INDEX idx_scientific_sources_title_trgm
    ON public.scientific_sources USING gin (title gin_trgm_ops);
CREATE INDEX idx_scientific_sources_organization_trgm
    ON public.scientific_sources USING gin (organization gin_trgm_ops);

-- ========================================================================
-- Composite indexes for common query patterns
-- ========================================================================
CREATE INDEX idx_product_markets_country_status
    ON public.product_markets (country_id, distribution_allowed);

CREATE INDEX idx_product_registration_country_status
    ON public.product_registration_records (product_market_id, registration_status);

CREATE INDEX idx_drug_evidence_category_verified
    ON public.drug_evidence (claim_category, is_verified);

CREATE INDEX idx_content_reviews_status
    ON public.content_reviews (review_status);

-- ========================================================================
-- Documentation of search limitations
-- ========================================================================
COMMENT ON COLUMN public.drugs.search_vector IS
    'Generated full-text search vector (simple config). Arabic stemming is limited.';
COMMENT ON COLUMN public.active_ingredients.search_vector IS
    'Generated full-text search vector (simple config). Arabic stemming is limited.';
COMMENT ON COLUMN public.brand_products.search_vector IS
    'Generated full-text search vector (simple config). Arabic stemming is limited.';
