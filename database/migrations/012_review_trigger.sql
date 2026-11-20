-- Abdulmajeedpharma (APH) — Phase 02.3 Remediation
-- Migration 012: Review integrity trigger
--
-- Creates the assert_no_self_review() trigger function and attaches it to
-- content_reviews. This migration runs after migration 010 because the trigger
-- function references drug_evidence.created_by, which is added by migration 010.
--
-- This migration is safe to apply on:
--   * A clean database (migrations 001-011 applied first)
--   * An already-migrated database (idempotent: DROP TRIGGER IF EXISTS,
--     CREATE OR REPLACE FUNCTION)
--
-- Depends on: 001 through 011 (specifically 006 for content_reviews and user_profiles,
--             and 010 for drug_evidence.created_by).

-- ------------------------------------------------------------------------
-- Trigger function: prevent a reviewer from reviewing their own evidence claim.
-- ------------------------------------------------------------------------

-- Function: assert the reviewer is not the creator of the evidence being reviewed.
-- Uses SET search_path = pg_temp, public to prevent search-path injection.
-- All table references are fully qualified (public.drug_evidence).
CREATE OR REPLACE FUNCTION assert_no_self_review()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_temp, public
AS $$
DECLARE
    evidence_creator UUID;
BEGIN
    -- Only enforce on INSERT or UPDATE of reviewer_id/drug_evidence_id.
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        SELECT created_by INTO evidence_creator
        FROM public.drug_evidence
        WHERE id = NEW.drug_evidence_id;

        IF evidence_creator IS NOT NULL AND NEW.reviewer_id = evidence_creator THEN
            RAISE EXCEPTION 'A reviewer cannot review their own evidence claim (user %, evidence %).', NEW.reviewer_id, NEW.drug_evidence_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- Revoke execute from PUBLIC (trigger functions are executed by the system,
-- not called directly by users).
REVOKE ALL ON FUNCTION assert_no_self_review() FROM PUBLIC;

-- Attach the trigger to content_reviews.
-- DROP TRIGGER IF EXISTS ensures idempotency on re-application.
DROP TRIGGER IF EXISTS trg_content_reviews_no_self_review ON public.content_reviews;

CREATE TRIGGER trg_content_reviews_no_self_review
    BEFORE INSERT OR UPDATE ON public.content_reviews
    FOR EACH ROW EXECUTE FUNCTION assert_no_self_review();

COMMENT ON FUNCTION assert_no_self_review() IS
    'Trigger function: prevents a reviewer from reviewing their own evidence claim. Referenced by trg_content_reviews_no_self_review on content_reviews.';