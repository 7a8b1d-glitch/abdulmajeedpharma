-- Abdulmajeedpharma (APH) — Phase 02 Database Foundation
-- Migration 003: Drug catalog
--
-- Core pharmaceutical domain tables:
--   active_ingredients, drugs, drug_ingredients, drug_class_links,
--   drug_indications, drug_contraindications, drug_adverse_effects,
--   drug_interactions, drug_dosage_information, drug_special_populations,
--   drug_images
--
-- Design notes:
--   * A "drug" is the generic/active-ingredient-level record (NOT a brand).
--   * Brand products are modelled separately (see 004).
--   * Many-to-many links are used where a drug/ingredient maps to multiple
--     classifications or has multiple indications, etc.
--   * Bilingual fields (*_en / *_ar); NULL translation is allowed.
-- Depends on: 001_extensions_and_helpers.sql, 002_geography_and_classification.sql.

-- ========================================================================
-- active_ingredients
-- ========================================================================
CREATE TABLE public.active_ingredients (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code                VARCHAR(30) NOT NULL UNIQUE,     -- e.g. WHO INN code
    name_en             TEXT NOT NULL,
    name_ar              TEXT,
    cas_number          VARCHAR(30),                      -- NULL allowed
    description_en       TEXT,
    description_ar        TEXT,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- drugs (generic-level records)
-- ========================================================================
CREATE TABLE public.drugs (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code               VARCHAR(30) NOT NULL UNIQUE,      -- internal APH code
    name_en            TEXT NOT NULL,
    name_ar             TEXT,
    generic_name_en     TEXT,
    generic_name_ar      TEXT,
    description_en      TEXT,
    description_ar       TEXT,
    is_active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- drug_ingredients (many-to-many: drug <-> active_ingredient)
-- ========================================================================
CREATE TABLE public.drug_ingredients (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    drug_id              UUID NOT NULL
        REFERENCES public.drugs (id)
        ON DELETE CASCADE,
    active_ingredient_id UUID NOT NULL
        REFERENCES public.active_ingredients (id)
        ON DELETE RESTRICT,
    strength_value       NUMERIC(10, 4),                  -- NULL if not applicable
    strength_unit        VARCHAR(30),
    is_primary           BOOLEAN NOT NULL DEFAULT FALSE,  -- primary active ingredient?
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (drug_id, active_ingredient_id)
);

-- ========================================================================
-- drug_class_links (many-to-many: drug <-> drug_class)
-- ========================================================================
CREATE TABLE public.drug_class_links (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    drug_id     UUID NOT NULL
        REFERENCES public.drugs (id)
        ON DELETE CASCADE,
    drug_class_id UUID NOT NULL
        REFERENCES public.drug_classes (id)
        ON DELETE RESTRICT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (drug_id, drug_class_id)
);

-- ========================================================================
-- drug_indications
-- ========================================================================
CREATE TABLE public.drug_indications (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    drug_id      UUID NOT NULL
        REFERENCES public.drugs (id)
        ON DELETE CASCADE,
    indication_en TEXT NOT NULL,
    indication_ar  TEXT,
    source_ref    TEXT,                                  -- citation reference
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- drug_contraindications
-- ========================================================================
CREATE TABLE public.drug_contraindications (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    drug_id          UUID NOT NULL
        REFERENCES public.drugs (id)
        ON DELETE CASCADE,
    contraindication_en TEXT NOT NULL,
    contraindication_ar  TEXT,
    source_ref       TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- drug_adverse_effects
-- ========================================================================
CREATE TABLE public.drug_adverse_effects (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    drug_id           UUID NOT NULL
        REFERENCES public.drugs (id)
        ON DELETE CASCADE,
    effect_en         TEXT NOT NULL,
    effect_ar          TEXT,
    frequency         VARCHAR(50),                        -- e.g. "common", "rare"
    source_ref        TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- drug_interactions (many-to-many: drug <-> drug)
-- ========================================================================
CREATE TABLE public.drug_interactions (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    drug_id          UUID NOT NULL
        REFERENCES public.drugs (id)
        ON DELETE CASCADE,
    interacting_drug_id UUID NOT NULL
        REFERENCES public.drugs (id)
        ON DELETE RESTRICT,
    interaction_en   TEXT NOT NULL,
    interaction_ar    TEXT,
    severity         VARCHAR(30) CHECK (severity IN ('minor','moderate','major','contraindicated')),
    source_ref       TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- A drug should not interact with itself.
    CONSTRAINT chk_drug_not_self_interaction
        CHECK (drug_id <> interacting_drug_id)
);

-- Prevent duplicate interaction rows in either direction using an
-- expression-based unique index. PostgreSQL does not allow expressions
-- in table-level UNIQUE constraints, so a unique index is used instead.
CREATE UNIQUE INDEX idx_drug_interactions_unique_pair
    ON public.drug_interactions (
        LEAST(drug_id, interacting_drug_id),
        GREATEST(drug_id, interacting_drug_id)
    );

-- ========================================================================
-- drug_dosage_information
-- ========================================================================
CREATE TABLE public.drug_dosage_information (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    drug_id     UUID NOT NULL
        REFERENCES public.drugs (id)
        ON DELETE CASCADE,
    population  VARCHAR(100),                             -- e.g. "adult", "pediatric"
    dosage_en   TEXT NOT NULL,
    dosage_ar    TEXT,
    frequency_en TEXT,
    frequency_ar  TEXT,
    route_en    VARCHAR(50),
    route_ar     VARCHAR(50),
    source_ref  TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- drug_special_populations
-- ========================================================================
CREATE TABLE public.drug_special_populations (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    drug_id      UUID NOT NULL
        REFERENCES public.drugs (id)
        ON DELETE CASCADE,
    population   VARCHAR(100) NOT NULL,                   -- e.g. "pregnancy", "lactation", "renal impairment"
    guidance_en  TEXT NOT NULL,
    guidance_ar   TEXT,
    risk_level   VARCHAR(30) CHECK (risk_level IN ('safe','caution','contraindicated','unknown')),
    source_ref   TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- drug_images
-- ========================================================================
CREATE TABLE public.drug_images (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    drug_id     UUID NOT NULL
        REFERENCES public.drugs (id)
        ON DELETE CASCADE,
    storage_path TEXT NOT NULL,                            -- Supabase Storage path
    alt_text_en  TEXT,
    alt_text_ar   TEXT,
    is_primary   BOOLEAN NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes.
CREATE INDEX idx_active_ingredients_code ON public.active_ingredients (code);
CREATE INDEX idx_active_ingredients_name_en ON public.active_ingredients USING gin (name_en gin_trgm_ops);
CREATE INDEX idx_active_ingredients_name_ar ON public.active_ingredients USING gin (name_ar gin_trgm_ops);

CREATE INDEX idx_drugs_code ON public.drugs (code);
CREATE INDEX idx_drugs_name_en ON public.drugs USING gin (name_en gin_trgm_ops);
CREATE INDEX idx_drugs_name_ar ON public.drugs USING gin (name_ar gin_trgm_ops);
CREATE INDEX idx_drugs_is_active ON public.drugs (is_active);

CREATE INDEX idx_drug_ingredients_drug_id ON public.drug_ingredients (drug_id);
CREATE INDEX idx_drug_ingredients_active_ingredient_id ON public.drug_ingredients (active_ingredient_id);

CREATE INDEX idx_drug_class_links_drug_id ON public.drug_class_links (drug_id);
CREATE INDEX idx_drug_class_links_drug_class_id ON public.drug_class_links (drug_class_id);

CREATE INDEX idx_drug_indications_drug_id ON public.drug_indications (drug_id);
CREATE INDEX idx_drug_contraindications_drug_id ON public.drug_contraindications (drug_id);
CREATE INDEX idx_drug_adverse_effects_drug_id ON public.drug_adverse_effects (drug_id);

CREATE INDEX idx_drug_interactions_drug_id ON public.drug_interactions (drug_id);
CREATE INDEX idx_drug_interactions_interacting_drug_id ON public.drug_interactions (interacting_drug_id);

CREATE INDEX idx_drug_dosage_information_drug_id ON public.drug_dosage_information (drug_id);
CREATE INDEX idx_drug_special_populations_drug_id ON public.drug_special_populations (drug_id);

CREATE INDEX idx_drug_images_drug_id ON public.drug_images (drug_id);

-- Triggers for updated_at.
CREATE TRIGGER trg_active_ingredients_updated_at
    BEFORE UPDATE ON public.active_ingredients
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_drugs_updated_at
    BEFORE UPDATE ON public.drugs
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_drug_ingredients_updated_at
    BEFORE UPDATE ON public.drug_ingredients
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_drug_indications_updated_at
    BEFORE UPDATE ON public.drug_indications
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_drug_contraindications_updated_at
    BEFORE UPDATE ON public.drug_contraindications
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_drug_adverse_effects_updated_at
    BEFORE UPDATE ON public.drug_adverse_effects
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_drug_interactions_updated_at
    BEFORE UPDATE ON public.drug_interactions
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_drug_dosage_information_updated_at
    BEFORE UPDATE ON public.drug_dosage_information
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_drug_special_populations_updated_at
    BEFORE UPDATE ON public.drug_special_populations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE public.active_ingredients IS 'Generic active ingredients (INN). A drug may contain multiple ingredients.';
COMMENT ON TABLE public.drugs IS 'Generic drug records (active-ingredient level), NOT brand products.';
COMMENT ON TABLE public.drug_ingredients IS 'Links drugs to their active ingredients (many-to-many).';
COMMENT ON TABLE public.drug_class_links IS 'Links drugs to drug classes (many-to-many).';
COMMENT ON TABLE public.drug_interactions IS 'Pairwise drug interactions (directed de-duplicated pair).';
