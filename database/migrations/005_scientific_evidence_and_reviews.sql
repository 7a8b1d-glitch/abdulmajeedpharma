-- Abdulmajeedpharma (APH) — Phase 02 Database Foundation
-- Migration 005: Scientific evidence and review workflow
--
-- Tables:
--   scientific_sources, drug_evidence
--
-- Design notes:
--   * Evidence claims are linked to a drug/product AND a scientific source.
--   * Evidence claim categories are controlled (mechanism, indications, etc.).
--   * Review status values are controlled (draft, under_review, verified, ...).
--   * Unsupported claims must not be represented as verified.
--   * Reviewer, review date, notes, and content version are recorded.
--   * The content_reviews table is created in migration 006 (after the
--     user profile table exists) to avoid a forward dependency.
--   * The self-review trigger is created in migration 012 (after the
--     evidence creator column exists from migration 010).
-- Depends on: 001_extensions_and_helpers.sql, 003_drug_catalog.sql, 004_companies_and_market.sql.

-- ========================================================================
-- scientific_sources
-- ========================================================================
CREATE TABLE public.scientific_sources (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title             TEXT NOT NULL,
    organization      TEXT NOT NULL,
    source_type       VARCHAR(50) NOT NULL
        CHECK (source_type IN (
            'journal_article', 'textbook', 'regulatory_document',
            'pharmacopoeia', 'clinical_trial_registry', 'database',
            'organization_website', 'other'
        )),
    url               TEXT,
    doi               VARCHAR(100),                        -- DOI or external identifier
    external_id        VARCHAR(100),
    publication_date  DATE,
    access_date       DATE,
    language          VARCHAR(10) DEFAULT 'en',
    reliability_level  VARCHAR(30) NOT NULL DEFAULT 'medium'
        CHECK (reliability_level IN ('low','medium','high','authoritative')),
    citation_text      TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- drug_evidence
-- ========================================================================
CREATE TABLE public.drug_evidence (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    drug_id           UUID
        REFERENCES public.drugs (id)
        ON DELETE CASCADE,
    brand_product_id  UUID
        REFERENCES public.brand_products (id)
        ON DELETE CASCADE,
    scientific_source_id UUID NOT NULL
        REFERENCES public.scientific_sources (id)
        ON DELETE RESTRICT,
    claim_category    VARCHAR(40) NOT NULL
        CHECK (claim_category IN (
            'mechanism_of_action', 'indications', 'contraindications',
            'adverse_effects', 'interactions', 'dosage', 'pharmacokinetics',
            'pregnancy_and_lactation', 'renal_and_hepatic', 'toxicity',
            'other'
        )),
    claim_text_en     TEXT NOT NULL,
    claim_text_ar      TEXT,
    is_verified       BOOLEAN NOT NULL DEFAULT FALSE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- At least one of drug_id or brand_product_id must be set.
    CONSTRAINT chk_evidence_target
        CHECK (drug_id IS NOT NULL OR brand_product_id IS NOT NULL),

    -- Not both (a piece of evidence targets one entity).
    CONSTRAINT chk_evidence_single_target
        CHECK (NOT (drug_id IS NOT NULL AND brand_product_id IS NOT NULL))
);

-- Indexes.
CREATE INDEX idx_scientific_sources_title ON public.scientific_sources USING gin (title gin_trgm_ops);
CREATE INDEX idx_scientific_sources_doi ON public.scientific_sources (doi);
CREATE INDEX idx_scientific_sources_organization ON public.scientific_sources USING gin (organization gin_trgm_ops);
CREATE INDEX idx_scientific_sources_reliability ON public.scientific_sources (reliability_level);

CREATE INDEX idx_drug_evidence_drug_id ON public.drug_evidence (drug_id);
CREATE INDEX idx_drug_evidence_brand_product_id ON public.drug_evidence (brand_product_id);
CREATE INDEX idx_drug_evidence_source_id ON public.drug_evidence (scientific_source_id);
CREATE INDEX idx_drug_evidence_claim_category ON public.drug_evidence (claim_category);
CREATE INDEX idx_drug_evidence_is_verified ON public.drug_evidence (is_verified);

-- Triggers for updated_at.
CREATE TRIGGER trg_scientific_sources_updated_at
    BEFORE UPDATE ON public.scientific_sources
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_drug_evidence_updated_at
    BEFORE UPDATE ON public.drug_evidence
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE public.scientific_sources IS 'Scientific references (journals, regulatory docs, etc.).';
COMMENT ON TABLE public.drug_evidence IS 'Evidence claims linked to a drug/product and a scientific source.';