-- Abdulmajeedpharma (APH) — Phase 02 Database Foundation
-- Migration 002: Geography and classification
--
-- Creates reference tables:
--   countries, body_systems, therapeutic_classes, pharmacological_classes,
--   drug_classes
--
-- Bilingual fields use *_en / *_ar pairs. Missing translations are allowed
-- (NULL) — no field is assumed to be pre-translated.
--
-- Depends on: 001_extensions_and_helpers.sql (gen_random_uuid).

-- ========================================================================
-- countries
-- ========================================================================
CREATE TABLE public.countries (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code          CHAR(2) NOT NULL UNIQUE,               -- ISO 3166-1 alpha-2
    name_en       TEXT NOT NULL,
    name_ar        TEXT,                                  -- NULL allowed
    is_yemen       BOOLEAN NOT NULL DEFAULT FALSE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- body_systems (18 systems, seeded in 011)
-- ========================================================================
CREATE TABLE public.body_systems (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code           VARCHAR(20) NOT NULL UNIQUE,          -- e.g. "CARDIOVASCULAR"
    name_en        TEXT NOT NULL,
    name_ar         TEXT,                                  -- NULL allowed
    description_en  TEXT,
    description_ar   TEXT,
    sort_order      INTEGER NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- therapeutic_classes (belongs to a body_system)
-- ========================================================================
CREATE TABLE public.therapeutic_classes (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    body_system_id    UUID NOT NULL
        REFERENCES public.body_systems (id)
        ON DELETE RESTRICT,
    code              VARCHAR(20) NOT NULL UNIQUE,
    name_en           TEXT NOT NULL,
    name_ar            TEXT,
    description_en     TEXT,
    description_ar      TEXT,
    is_active         BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- pharmacological_classes (belongs to a therapeutic_class)
-- ========================================================================
CREATE TABLE public.pharmacological_classes (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    therapeutic_class_id UUID NOT NULL
        REFERENCES public.therapeutic_classes (id)
        ON DELETE RESTRICT,
    code                 VARCHAR(20) NOT NULL UNIQUE,
    name_en              TEXT NOT NULL,
    name_ar               TEXT,
    description_en        TEXT,
    description_ar         TEXT,
    is_active            BOOLEAN NOT NULL DEFAULT TRUE,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- drug_classes (belongs to a pharmacological_class)
-- ========================================================================
CREATE TABLE public.drug_classes (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pharmacological_class_id UUID NOT NULL
        REFERENCES public.pharmacological_classes (id)
        ON DELETE RESTRICT,
    code                   VARCHAR(20) NOT NULL UNIQUE,
    name_en                TEXT NOT NULL,
    name_ar                 TEXT,
    description_en          TEXT,
    description_ar           TEXT,
    is_active              BOOLEAN NOT NULL DEFAULT TRUE,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for frequent lookups.
CREATE INDEX idx_countries_code ON public.countries (code);
CREATE INDEX idx_countries_name_en ON public.countries USING gin (name_en gin_trgm_ops);
CREATE INDEX idx_countries_name_ar ON public.countries USING gin (name_ar gin_trgm_ops);

CREATE INDEX idx_body_systems_code ON public.body_systems (code);
CREATE INDEX idx_body_systems_name_en ON public.body_systems USING gin (name_en gin_trgm_ops);
CREATE INDEX idx_body_systems_name_ar ON public.body_systems USING gin (name_ar gin_trgm_ops);
CREATE INDEX idx_body_systems_is_active ON public.body_systems (is_active);

CREATE INDEX idx_therapeutic_classes_body_system_id ON public.therapeutic_classes (body_system_id);
CREATE INDEX idx_therapeutic_classes_code ON public.therapeutic_classes (code);
CREATE INDEX idx_therapeutic_classes_name_en ON public.therapeutic_classes USING gin (name_en gin_trgm_ops);
CREATE INDEX idx_therapeutic_classes_name_ar ON public.therapeutic_classes USING gin (name_ar gin_trgm_ops);

CREATE INDEX idx_pharmacological_classes_therapeutic_class_id ON public.pharmacological_classes (therapeutic_class_id);
CREATE INDEX idx_pharmacological_classes_code ON public.pharmacological_classes (code);
CREATE INDEX idx_pharmacological_classes_name_en ON public.pharmacological_classes USING gin (name_en gin_trgm_ops);
CREATE INDEX idx_pharmacological_classes_name_ar ON public.pharmacological_classes USING gin (name_ar gin_trgm_ops);

CREATE INDEX idx_drug_classes_pharmacological_class_id ON public.drug_classes (pharmacological_class_id);
CREATE INDEX idx_drug_classes_code ON public.drug_classes (code);
CREATE INDEX idx_drug_classes_name_en ON public.drug_classes USING gin (name_en gin_trgm_ops);
CREATE INDEX idx_drug_classes_name_ar ON public.drug_classes USING gin (name_ar gin_trgm_ops);

-- Automatic updated_at on all classification tables.
CREATE TRIGGER trg_countries_updated_at
    BEFORE UPDATE ON public.countries
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_body_systems_updated_at
    BEFORE UPDATE ON public.body_systems
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_therapeutic_classes_updated_at
    BEFORE UPDATE ON public.therapeutic_classes
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_pharmacological_classes_updated_at
    BEFORE UPDATE ON public.pharmacological_classes
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_drug_classes_updated_at
    BEFORE UPDATE ON public.drug_classes
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE public.countries IS 'Reference list of countries (ISO 3166-1 alpha-2). Yemen is flagged.';
COMMENT ON TABLE public.body_systems IS '18 top-level body systems for pharmaceutical classification.';
COMMENT ON TABLE public.therapeutic_classes IS 'Therapeutic classes within a body system.';
COMMENT ON TABLE public.pharmacological_classes IS 'Pharmacological classes within a therapeutic class.';
COMMENT ON TABLE public.drug_classes IS 'Drug classes within a pharmacological class.';
