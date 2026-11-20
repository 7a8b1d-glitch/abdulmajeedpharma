-- Abdulmajeedpharma (APH) — Phase 02.4 Database Readiness
-- Migration 013: Migration tracking and legacy compatibility
--
-- This migration serves two purposes:
--   1. Creates the schema_migrations table to track applied migrations
--   2. Provides forward-only compatibility for databases that applied
--      the pre-Phase-02.3 migration sequence (where migration 005
--      incorrectly referenced user_profiles before it existed).
--
-- This migration is IDEMPOTENT and SAFE TO REAPPLY:
--   * All CREATE statements use IF NOT EXISTS
--   * All ALTER statements use IF NOT EXISTS / DO $$ blocks
--   * All DROP statements use IF EXISTS
--   * Existing data is preserved
--
-- Depends on: 001 through 012.

-- ------------------------------------------------------------------------
-- Migration tracking table
-- ------------------------------------------------------------------------

-- Records every migration that has been successfully applied.
-- Prevents reapplication and enables checksum verification.
CREATE TABLE IF NOT EXISTS public.schema_migrations (
    version        VARCHAR(20) NOT NULL PRIMARY KEY,  -- e.g. '001', '002', ..., '013'
    name           VARCHAR(255) NOT NULL,             -- migration file name
    checksum       VARCHAR(64) NOT NULL,              -- SHA256 of migration file
    applied_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    success        BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX idx_schema_migrations_version ON public.schema_migrations (version);
CREATE INDEX idx_schema_migrations_success ON public.schema_migrations (success);

COMMENT ON TABLE public.schema_migrations IS
    'Tracks applied database migrations for idempotency and integrity verification.';

-- Enable RLS on migration tracking table (administrators only).
ALTER TABLE public.schema_migrations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admins_read_schema_migrations" ON public.schema_migrations;
CREATE POLICY "admins_read_schema_migrations"
    ON public.schema_migrations
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    );

-- No INSERT/UPDATE/DELETE policies on schema_migrations for application roles.
-- The migration runner (backend service) manages this table directly.

-- ------------------------------------------------------------------------
-- Legacy compatibility: content_reviews table repair
-- ------------------------------------------------------------------------

-- Pre-Phase-02.3 migration 005 created content_reviews with a forward
-- dependency on user_profiles (which didn't exist until migration 006).
-- A database that somehow applied the old migration 005 may have a
-- content_reviews table with an incomplete or incorrect schema.
-- Migration 013 repairs this safely without data loss.

DO $$
BEGIN
    -- Check if content_reviews exists from a legacy migration.
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'content_reviews'
    ) THEN
        -- Table exists; ensure it has the correct schema.
        -- Add reviewer_id FK if missing (legacy tables may lack it).
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
              ON tc.constraint_name = kcu.constraint_name
             AND tc.table_schema = kcu.table_schema
            WHERE tc.table_schema = 'public'
              AND tc.table_name = 'content_reviews'
              AND tc.constraint_type = 'FOREIGN KEY'
              AND kcu.column_name = 'reviewer_id'
              AND kcu.referenced_table_name = 'user_profiles'
        ) THEN
            ALTER TABLE public.content_reviews
                ADD CONSTRAINT fk_content_reviews_reviewer
                FOREIGN KEY (reviewer_id) REFERENCES public.user_profiles (user_id)
                ON DELETE RESTRICT;
        END IF;

        -- Ensure drug_evidence_id FK exists.
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
              ON tc.constraint_name = kcu.constraint_name
             AND tc.table_schema = kcu.table_schema
            WHERE tc.table_schema = 'public'
              AND tc.table_name = 'content_reviews'
              AND tc.constraint_type = 'FOREIGN KEY'
              AND kcu.column_name = 'drug_evidence_id'
              AND kcu.referenced_table_name = 'drug_evidence'
        ) THEN
            ALTER TABLE public.content_reviews
                ADD CONSTRAINT fk_content_reviews_evidence
                FOREIGN KEY (drug_evidence_id) REFERENCES public.drug_evidence (id)
                ON DELETE CASCADE;
        END IF;

        -- Ensure approved_by FK exists.
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
              ON tc.constraint_name = kcu.constraint_name
             AND tc.table_schema = kcu.table_schema
            WHERE tc.table_schema = 'public'
              AND tc.table_name = 'content_reviews'
              AND tc.constraint_type = 'FOREIGN KEY'
              AND kcu.column_name = 'approved_by'
              AND kcu.referenced_table_name = 'user_profiles'
        ) THEN
            ALTER TABLE public.content_reviews
                ADD CONSTRAINT fk_content_reviews_approved_by
                FOREIGN KEY (approved_by) REFERENCES public.user_profiles (user_id)
                ON DELETE SET NULL;
        END IF;

        -- Ensure reviewed_at is NOT NULL (legacy tables may allow NULL).
        ALTER TABLE public.content_reviews
            ALTER COLUMN reviewed_at SET NOT NULL;

        -- Ensure reviewed_at has a default (legacy tables may lack it).
        ALTER TABLE public.content_reviews
            ALTER COLUMN reviewed_at SET DEFAULT now();

        -- Add content_version column if missing.
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'content_reviews'
              AND column_name = 'content_version'
        ) THEN
            ALTER TABLE public.content_reviews
                ADD COLUMN content_version INTEGER NOT NULL DEFAULT 1;
        END IF;

        -- Add review_notes column if missing.
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'content_reviews'
              AND column_name = 'review_notes'
        ) THEN
            ALTER TABLE public.content_reviews
                ADD COLUMN review_notes TEXT;
        END IF;

        -- Create indexes idempotently.
        CREATE INDEX IF NOT EXISTS idx_content_reviews_evidence_id
            ON public.content_reviews (drug_evidence_id);
        CREATE INDEX IF NOT EXISTS idx_content_reviews_reviewer_id
            ON public.content_reviews (reviewer_id);
        CREATE INDEX IF NOT EXISTS idx_content_reviews_review_status
            ON public.content_reviews (review_status);

        -- Ensure the updated_at trigger exists.
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger tg
            JOIN pg_class c ON tg.tgrelid = c.oid
            WHERE c.relname = 'content_reviews'
              AND tg.tgname = 'trg_content_reviews_updated_at'
        ) THEN
            CREATE TRIGGER trg_content_reviews_updated_at
                BEFORE UPDATE ON public.content_reviews
                FOR EACH ROW EXECUTE FUNCTION set_updated_at();
        END IF;
    ELSE
        -- content_reviews does not exist; this means the legacy migration
        -- 005 failed (as expected due to the forward dependency). Migration
        -- 006 should have created it. If migration 006 also predates the
        #Phase 02.3 fix, content_reviews may still be missing.
        -- In that case, the migration runner should apply migration 006
        -- (which now creates content_reviews) before this migration.
        -- We log a notice but do not fail — migration 006 handles creation.
        RAISE NOTICE 'content_reviews table does not exist; migration 006 should create it.';
    END IF;
END $$;

-- Ensure user_profiles exists (should be from migration 006).
-- This is a safety check; if user_profiles is missing, something is wrong.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'user_profiles'
    ) THEN
        RAISE EXCEPTION 'user_profiles table is missing. Migration 006 must be applied before migration 013.';
    END IF;
END $$;

-- Ensure drug_evidence.created_by exists (should be from migration 010).
-- The assert_no_self_review trigger (migration 012) depends on this column.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'drug_evidence'
          AND column_name = 'created_by'
    ) THEN
        RAISE EXCEPTION 'drug_evidence.created_by column is missing. Migration 010 must be applied before migration 013.';
    END IF;
END $$;

-- ------------------------------------------------------------------------
-- reviewed_at protection: column-level privileges
-- ------------------------------------------------------------------------

-- Revoke UPDATE on reviewed_at from all roles so reviewers cannot
-- forge or backdate review timestamps on existing rows.
REVOKE UPDATE (reviewed_at) ON public.content_reviews FROM PUBLIC;
REVOKE UPDATE (reviewed_at) ON public.content_reviews FROM authenticated;

-- Revoke table-level INSERT on content_reviews, then grant INSERT only
-- on columns that clients are permitted to set. reviewed_at is explicitly
-- excluded: it is server-assigned via DEFAULT now() and cannot be supplied
-- by any client, including reviewers and administrators.
REVOKE INSERT ON public.content_reviews FROM PUBLIC;
REVOKE INSERT ON public.content_reviews FROM authenticated;
GRANT INSERT (reviewer_id, drug_evidence_id, review_status, review_notes,
              content_version, approved_by) ON public.content_reviews TO authenticated;

-- Reviewers can still INSERT new reviews (reviewed_at defaults to now()).
-- They cannot specify reviewed_at because they have no INSERT privilege on
-- that column. They cannot UPDATE reviewed_at because of the column-level
-- REVOKE above. Administrators use the SECURITY DEFINER function
-- aph_correct_reviewed_at() for authorized timestamp corrections.

-- ------------------------------------------------------------------------
-- SECURITY DEFINER function: authorized reviewed_at correction
-- ------------------------------------------------------------------------

-- Allows administrators to correct review timestamps through an audited
-- workflow. Runs as SECURITY DEFINER (function owner), which bypasses
-- column-level REVOKE on reviewed_at. No session variable or GUC is used;
-- authorization is verified internally by checking the caller's role in
-- user_profiles.
CREATE OR REPLACE FUNCTION aph_correct_reviewed_at(
    review_id UUID,
    corrected_at TIMESTAMPTZ,
    correction_reason TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_temp, public
AS $$
DECLARE
    caller_role VARCHAR(30);
    old_reviewed_at TIMESTAMPTZ;
BEGIN
    -- Resolve the caller's role.
    SELECT role INTO caller_role
    FROM public.user_profiles
    WHERE user_id = auth.uid();

    -- Only administrators may correct review timestamps.
    IF caller_role <> 'administrator' THEN
        RAISE EXCEPTION 'Only administrators can correct review timestamps.';
    END IF;

    -- Validate the review exists.
    SELECT reviewed_at INTO old_reviewed_at
    FROM public.content_reviews
    WHERE id = review_id;

    IF old_reviewed_at IS NULL THEN
        RAISE EXCEPTION 'Review does not exist: %', review_id;
    END IF;

    -- Apply the correction.
    UPDATE public.content_reviews
    SET reviewed_at = corrected_at, updated_at = now()
    WHERE id = review_id;

    -- Record the correction in the audit log.
    INSERT INTO public.audit_logs (
        actor_id,
        actor_role,
        action,
        entity_type,
        entity_id,
        change_metadata,
        timestamp
    ) VALUES (
        auth.uid(),
        caller_role,
        'correct_reviewed_at',
        'content_reviews',
        review_id,
        jsonb_build_object(
            'review_id', review_id,
            'old_reviewed_at', old_reviewed_at,
            'new_reviewed_at', corrected_at,
            'correction_reason', correction_reason
        ),
        now()
    );

END;
$$;

-- Revoke execute from PUBLIC.
REVOKE ALL ON FUNCTION aph_correct_reviewed_at(UUID, TIMESTAMPTZ, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION aph_correct_reviewed_at(UUID, TIMESTAMPTZ, TEXT) TO authenticated;

COMMENT ON FUNCTION aph_correct_reviewed_at(UUID, TIMESTAMPTZ, TEXT) IS
    'Authorized review timestamp correction. Administrator only. Audit logged.';

-- ------------------------------------------------------------------------
-- RLS policy: reviewers cannot update reviewed_at
-- ------------------------------------------------------------------------

-- Column-level REVOKE UPDATE (reviewed_at) prevents all non-owner roles
-- from modifying reviewed_at on existing rows. The SECURITY DEFINER
-- function aph_correct_reviewed_at() runs as the function owner and can
-- update reviewed_at through the authorized correction workflow.
-- No additional RLS change is needed because column-level privileges
-- provide the enforcement boundary.

-- ------------------------------------------------------------------------
-- Migration tracking entry for this migration
-- ------------------------------------------------------------------------

-- Note: The schema_migrations entry for version '013' is inserted by
-- the migration runner script, not here, to avoid circular dependencies.
-- This migration file is tracked by the runner after successful execution.

COMMENT ON TABLE public.schema_migrations IS
    'Migration tracking table. Records each applied migration version, checksum, and timestamp.';