-- Abdulmajeedpharma (APH) — Phase 02 Database Foundation
-- Migration 006: Users and role-based access
--
-- Tables:
--   user_profiles (linked to Supabase auth.users)
--   content_reviews (review workflow; depends on user_profiles and drug_evidence)
--
-- Design notes:
--   * Supabase Auth is the identity provider; auth.users is managed by Supabase.
--   * user_profiles.user_id references auth.users.id (Supabase-compatible).
--   * Roles: user, editor, scientific_reviewer, administrator.
--   * No plaintext passwords are ever stored (Supabase Auth handles hashing).
--   * content_reviews is created here (not in migration 005) because it has a
--     foreign key to user_profiles, which is created in this migration.
-- Depends on: 001_extensions_and_helpers.sql, 002_geography_and_classification.sql,
--             003_drug_catalog.sql, 004_companies_and_market.sql,
--             005_scientific_evidence_and_reviews.sql.

-- ========================================================================
-- user_profiles
-- ========================================================================
CREATE TABLE public.user_profiles (
    user_id   UUID PRIMARY KEY
        REFERENCES auth.users (id)
        ON DELETE CASCADE,
    full_name  TEXT,
    email      TEXT NOT NULL,
    role       VARCHAR(30) NOT NULL DEFAULT 'user'
        CHECK (role IN ('user','editor','scientific_reviewer','administrator')),
    phone      VARCHAR(30),
    country_id  UUID REFERENCES public.countries (id)
        ON DELETE SET NULL,
    language   VARCHAR(10) DEFAULT 'ar',
    is_active  BOOLEAN NOT NULL DEFAULT TRUE,
    email_verified BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Ordinary users cannot self-assign privileged roles. This constraint
    -- is enforced at the application/API layer and by RLS; the DB column
    -- check only limits the allowed set of role values.
    CONSTRAINT chk_role_allowed_values
        CHECK (role IN ('user','editor','scientific_reviewer','administrator'))
);

CREATE INDEX idx_user_profiles_email ON public.user_profiles (email);
CREATE INDEX idx_user_profiles_role ON public.user_profiles (role);
CREATE INDEX idx_user_profiles_country_id ON public.user_profiles (country_id);

CREATE TRIGGER trg_user_profiles_updated_at
    BEFORE UPDATE ON public.user_profiles
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ========================================================================
-- content_reviews
-- ========================================================================
-- Created here (not in migration 005) because reviewer_id and approved_by
-- reference user_profiles.user_id, which is created in this migration.
-- The self-review trigger is created in migration 012 because it references
-- drug_evidence.created_by, which is added in migration 010.
CREATE TABLE public.content_reviews (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    drug_evidence_id   UUID NOT NULL
        REFERENCES public.drug_evidence (id)
        ON DELETE CASCADE,
    reviewer_id        UUID NOT NULL
        REFERENCES public.user_profiles (user_id)
        ON DELETE RESTRICT,
    review_status      VARCHAR(30) NOT NULL DEFAULT 'draft'
        CHECK (review_status IN (
            'draft', 'under_review', 'verified', 'needs_update',
            'rejected', 'unpublished'
        )),
    reviewed_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    review_notes       TEXT,
    content_version    INTEGER NOT NULL DEFAULT 1,
    approved_by        UUID
        REFERENCES public.user_profiles (user_id)
        ON DELETE SET NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- A verified review must have a reviewer and a review timestamp.
    CONSTRAINT chk_verified_requires_reviewer_and_timestamp
        CHECK (NOT (review_status = 'verified' AND reviewed_at IS NULL))
);

CREATE INDEX idx_content_reviews_evidence_id ON public.content_reviews (drug_evidence_id);
CREATE INDEX idx_content_reviews_reviewer_id ON public.content_reviews (reviewer_id);
CREATE INDEX idx_content_reviews_review_status ON public.content_reviews (review_status);

-- Trigger for updated_at.
CREATE TRIGGER trg_content_reviews_updated_at
    BEFORE UPDATE ON public.content_reviews
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE public.user_profiles IS 'Application user profiles linked to Supabase auth.users.';
COMMENT ON TABLE public.content_reviews IS 'Review workflow records for scientific evidence content. Self-review is prevented by trigger trg_content_reviews_no_self_review (created in migration 012).';