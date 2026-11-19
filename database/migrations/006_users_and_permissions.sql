-- Abdulmajeedpharma (APH) — Phase 02 Database Foundation
-- Migration 006: Users and role-based access
--
-- Tables:
--   user_profiles (linked to Supabase auth.users)
--
-- Design notes:
--   * Supabase Auth is the identity provider; auth.users is managed by Supabase.
--   * user_profiles.user_id references auth.users.id (Supabase-compatible).
--   * Roles: user, editor, scientific_reviewer, administrator.
--   * No plaintext passwords are ever stored (Supabase Auth handles hashing).
-- Depends on: 001_extensions_and_helpers.sql.

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

COMMENT ON TABLE public.user_profiles IS 'Application user profiles linked to Supabase auth.users.';
