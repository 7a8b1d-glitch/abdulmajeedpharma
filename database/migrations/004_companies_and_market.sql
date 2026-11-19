-- Abdulmajeedpharma (APH) — Phase 02 Database Foundation
-- Migration 004: Companies, brands, presentations, Yemen market
--
-- Tables:
--   manufacturers, marketing_authorization_holders, suppliers, distributors,
--   brand_products, product_presentations, product_markets,
--   product_registration_records
--
-- Design notes:
--   * A brand_product is NOT a generic drug; it is a marketed product tied to
--     one or more active ingredients and one manufacturer.
--   * product_presentations capture strength, form, route, package, barcode.
--   * product_markets tie a brand product to a country.
--   * product_registration_records capture registration status per country.
--   * Registration status values are controlled. Unknown status stays unknown.
-- Depends on: 001_extensions_and_helpers.sql, 002_geography_and_classification.sql, 003_drug_catalog.sql.

-- ========================================================================
-- manufacturers
-- ========================================================================
CREATE TABLE public.manufacturers (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code          VARCHAR(30) NOT NULL UNIQUE,
    name_en       TEXT NOT NULL,
    name_ar        TEXT,
    address_en     TEXT,
    address_ar      TEXT,
    country_id     UUID REFERENCES public.countries (id)
        ON DELETE SET NULL,
    contact_email  TEXT,
    contact_phone  TEXT,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- marketing_authorization_holders
-- ========================================================================
CREATE TABLE public.marketing_authorization_holders (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code          VARCHAR(30) NOT NULL UNIQUE,
    name_en       TEXT NOT NULL,
    name_ar        TEXT,
    address_en     TEXT,
    address_ar      TEXT,
    country_id     UUID REFERENCES public.countries (id)
        ON DELETE SET NULL,
    contact_email  TEXT,
    contact_phone  TEXT,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- suppliers
-- ========================================================================
CREATE TABLE public.suppliers (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code          VARCHAR(30) NOT NULL UNIQUE,
    name_en       TEXT NOT NULL,
    name_ar        TEXT,
    address_en     TEXT,
    address_ar      TEXT,
    country_id     UUID REFERENCES public.countries (id)
        ON DELETE SET NULL,
    contact_email  TEXT,
    contact_phone  TEXT,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- distributors
-- ========================================================================
CREATE TABLE public.distributors (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code          VARCHAR(30) NOT NULL UNIQUE,
    name_en       TEXT NOT NULL,
    name_ar        TEXT,
    address_en     TEXT,
    address_ar      TEXT,
    country_id     UUID REFERENCES public.countries (id)
        ON DELETE SET NULL,
    contact_email  TEXT,
    contact_phone  TEXT,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- brand_products
-- ========================================================================
CREATE TABLE public.brand_products (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code                     VARCHAR(30) NOT NULL UNIQUE,
    brand_name_en            TEXT NOT NULL,
    brand_name_ar             TEXT,
    manufacturer_id           UUID NOT NULL
        REFERENCES public.manufacturers (id)
        ON DELETE RESTRICT,
    marketing_authorization_holder_id UUID
        REFERENCES public.marketing_authorization_holders (id)
        ON DELETE SET NULL,
    description_en            TEXT,
    description_ar             TEXT,
    is_active                 BOOLEAN NOT NULL DEFAULT TRUE,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- product_presentations
-- ========================================================================
CREATE TABLE public.product_presentations (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    brand_product_id   UUID NOT NULL
        REFERENCES public.brand_products (id)
        ON DELETE CASCADE,
    presentation_code  VARCHAR(30) NOT NULL UNIQUE,
    strength_value     NUMERIC(10, 4),
    strength_unit      VARCHAR(30),
    dosage_form_en     VARCHAR(50),
    dosage_form_ar      VARCHAR(50),
    route_en           VARCHAR(50),
    route_ar            VARCHAR(50),
    package_size       NUMERIC(10, 4),
    package_unit_en    VARCHAR(30),
    package_unit_ar     VARCHAR(30),
    barcode            VARCHAR(50),
    country_of_origin_id UUID
        REFERENCES public.countries (id)
        ON DELETE SET NULL,
    image_reference_id UUID
        REFERENCES public.drug_images (id)
        ON DELETE SET NULL,
    is_active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- product_markets
-- ========================================================================
CREATE TABLE public.product_markets (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    brand_product_id  UUID NOT NULL
        REFERENCES public.brand_products (id)
        ON DELETE CASCADE,
    country_id        UUID NOT NULL
        REFERENCES public.countries (id)
        ON DELETE RESTRICT,
    distribution_allowed BOOLEAN NOT NULL DEFAULT FALSE,
    notes_en           TEXT,
    notes_ar            TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (brand_product_id, country_id)
);

-- ========================================================================
-- product_registration_records
-- ========================================================================
CREATE TABLE public.product_registration_records (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_market_id       UUID NOT NULL
        REFERENCES public.product_markets (id)
        ON DELETE CASCADE,
    registration_number     VARCHAR(100),
    registration_status     VARCHAR(30) NOT NULL DEFAULT 'unknown'
        CHECK (registration_status IN (
            'unknown', 'registered', 'pending', 'rejected',
            'expired', 'withdrawn', 'suspended'
        )),
    registration_authority  VARCHAR(100),                  -- e.g. "Yemen SFDA"
    registration_verification_date DATE,
    availability_status     VARCHAR(30) DEFAULT 'unknown'
        CHECK (availability_status IN (
            'unknown', 'available', 'out_of_stock', 'discontinued'
        )),
    market_notes_en          TEXT,
    market_notes_ar           TEXT,
    source_reference         TEXT,                          -- provenance / source doc
    last_verified_date       DATE,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes.
CREATE INDEX idx_manufacturers_code ON public.manufacturers (code);
CREATE INDEX idx_manufacturers_name_en ON public.manufacturers USING gin (name_en gin_trgm_ops);
CREATE INDEX idx_manufacturers_name_ar ON public.manufacturers USING gin (name_ar gin_trgm_ops);
CREATE INDEX idx_manufacturers_country_id ON public.manufacturers (country_id);

CREATE INDEX idx_mah_code ON public.marketing_authorization_holders (code);
CREATE INDEX idx_mah_name_en ON public.marketing_authorization_holders USING gin (name_en gin_trgm_ops);
CREATE INDEX idx_mah_name_ar ON public.marketing_authorization_holders USING gin (name_ar gin_trgm_ops);
CREATE INDEX idx_mah_country_id ON public.marketing_authorization_holders (country_id);

CREATE INDEX idx_suppliers_code ON public.suppliers (code);
CREATE INDEX idx_suppliers_name_en ON public.suppliers USING gin (name_en gin_trgm_ops);
CREATE INDEX idx_suppliers_name_ar ON public.suppliers USING gin (name_ar gin_trgm_ops);
CREATE INDEX idx_suppliers_country_id ON public.suppliers (country_id);

CREATE INDEX idx_distributors_code ON public.distributors (code);
CREATE INDEX idx_distributors_name_en ON public.distributors USING gin (name_en gin_trgm_ops);
CREATE INDEX idx_distributors_name_ar ON public.distributors USING gin (name_ar gin_trgm_ops);
CREATE INDEX idx_distributors_country_id ON public.distributors (country_id);

CREATE INDEX idx_brand_products_code ON public.brand_products (code);
CREATE INDEX idx_brand_products_name_en ON public.brand_products USING gin (brand_name_en gin_trgm_ops);
CREATE INDEX idx_brand_products_name_ar ON public.brand_products USING gin (brand_name_ar gin_trgm_ops);
CREATE INDEX idx_brand_products_manufacturer_id ON public.brand_products (manufacturer_id);
CREATE INDEX idx_brand_products_mah_id ON public.brand_products (marketing_authorization_holder_id);
CREATE INDEX idx_brand_products_is_active ON public.brand_products (is_active);

CREATE INDEX idx_product_presentations_brand_product_id ON public.product_presentations (brand_product_id);
CREATE INDEX idx_product_presentations_code ON public.product_presentations (presentation_code);
CREATE INDEX idx_product_presentations_barcode ON public.product_presentations (barcode);
CREATE INDEX idx_product_presentations_dosage_form ON public.product_presentations (dosage_form_en);
CREATE INDEX idx_product_presentations_route ON public.product_presentations (route_en);
CREATE INDEX idx_product_presentations_country_of_origin ON public.product_presentations (country_of_origin_id);
CREATE INDEX idx_product_presentations_is_active ON public.product_presentations (is_active);

CREATE INDEX idx_product_markets_brand_product_id ON public.product_markets (brand_product_id);
CREATE INDEX idx_product_markets_country_id ON public.product_markets (country_id);

CREATE INDEX idx_product_registration_records_product_market_id ON public.product_registration_records (product_market_id);
CREATE INDEX idx_product_registration_records_number ON public.product_registration_records (registration_number);
CREATE INDEX idx_product_registration_records_status ON public.product_registration_records (registration_status);

-- Triggers for updated_at.
CREATE TRIGGER trg_manufacturers_updated_at
    BEFORE UPDATE ON public.manufacturers
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_marketing_authorization_holders_updated_at
    BEFORE UPDATE ON public.marketing_authorization_holders
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_suppliers_updated_at
    BEFORE UPDATE ON public.suppliers
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_distributors_updated_at
    BEFORE UPDATE ON public.distributors
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_brand_products_updated_at
    BEFORE UPDATE ON public.brand_products
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_product_presentations_updated_at
    BEFORE UPDATE ON public.product_presentations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_product_markets_updated_at
    BEFORE UPDATE ON public.product_markets
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_product_registration_records_updated_at
    BEFORE UPDATE ON public.product_registration_records
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE public.manufacturers IS 'Drug manufacturers.';
COMMENT ON TABLE public.marketing_authorization_holders IS 'Marketing authorization holders (MAH).';
COMMENT ON TABLE public.suppliers IS 'Suppliers of pharmaceutical products.';
COMMENT ON TABLE public.distributors IS 'Distributors of pharmaceutical products.';
COMMENT ON TABLE public.brand_products IS 'Branded/marketed products (NOT generic drugs).';
COMMENT ON TABLE public.product_presentations IS 'Product presentations: strength, form, route, package, barcode.';
COMMENT ON TABLE public.product_markets IS 'Country-level market availability for a brand product.';
COMMENT ON TABLE public.product_registration_records IS 'Registration records per country/market. Unknown status stays unknown.';
