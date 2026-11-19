-- Abdulmajeedpharma (APH) — Phase 02 Database Foundation
-- Migration 001: Extensions and helper functions
--
-- Enables PostgreSQL extensions required by later migrations and creates
-- shared helper functions (e.g. automatic updated_at triggers).
--
-- Safe to re-run: uses IF NOT EXISTS / CREATE OR REPLACE.

-- pgcrypto: gen_random_uuid() for UUID primary keys.
-- pg_trgm: trigram indexes for fuzzy search on names (English + Arabic).
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Helper function: automatically set updated_at = now() on UPDATE.
-- Used by trigger definitions in later migrations.
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Helper function (SECURITY DEFINER): resolve the current authenticated
-- user's application role from user_profiles.
--
-- Security notes:
--   * search_path is restricted to pg_temp, public to prevent search-path
--     injection attacks.
--   * Execution is restricted to the postgres/supabase admin role; ordinary
--     application roles should not be granted EXECUTE on this function.
--   * This function never returns passwords, tokens, or secrets.
CREATE OR REPLACE FUNCTION aph_current_user_role()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_temp, public
AS $$
DECLARE
    v_role text;
BEGIN
    SELECT role INTO v_role
    FROM public.user_profiles
    WHERE user_id = auth.uid();

    RETURN COALESCE(v_role, 'user');
EXCEPTION
    WHEN OTHERS THEN
        -- auth.uid() returns NULL outside an authenticated request context.
        RETURN 'anonymous';
END;
$$;

-- Revoke execute from PUBLIC; only trusted backend roles should use it.
REVOKE ALL ON FUNCTION aph_current_user_role() FROM PUBLIC;

COMMENT ON FUNCTION aph_current_user_role() IS
    'Returns the authenticated user''s APH application role from user_profiles.';
