-- Abdulmajeedpharma (APH) — Test-only auth.uid() compatibility shim
--
-- This file is for TEST DATABASES ONLY. It must NEVER be applied to
-- production or staging databases.
--
-- Provides a Supabase-compatible auth.uid() function for testing RLS
-- policies against plain PostgreSQL. The function reads the authenticated
-- user identity from a trusted session-level setting:
--
--   current_setting('request.jwt.claim.sub', true)
--
-- This setting must be set by the test harness before each test
-- transaction. It is NOT settable by application clients in production.
--
-- WARNING: This shim trusts current_setting('request.jwt.claim.sub', true).
-- In production, Supabase Auth sets this from a verified JWT. In tests,
-- the test harness sets it directly. Do not use this shim outside test
-- databases.

DROP FUNCTION IF EXISTS auth.uid();

CREATE FUNCTION auth.uid()
RETURNS UUID
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    sub TEXT;
BEGIN
    sub := current_setting('request.jwt.claim.sub', true);
    IF sub IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN sub::UUID;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;

-- Revoke execute from PUBLIC to prevent unauthorized use.
REVOKE ALL ON FUNCTION auth.uid() FROM PUBLIC;

-- Grant execute to authenticated (test roles).
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;

COMMENT ON FUNCTION auth.uid() IS
    'TEST ONLY: Supabase-compatible auth.uid() shim. Reads request.jwt.claim.sub session setting. NOT for production use.';
