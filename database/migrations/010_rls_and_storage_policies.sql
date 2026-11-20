-- Abdulmajeedpharma (APH) — Phase 02 Database Foundation
-- Migration 010: Row Level Security and storage policies
--
-- Enables RLS on all tables containing private or privileged data and
-- defines policies based on the role matrix (see docs/RLS_POLICY_MATRIX.md).
--
-- Roles: user, editor, scientific_reviewer, administrator.
--
-- Security principles:
--   * auth.uid() is used to identify the authenticated user.
--   * No table uses unrestricted USING (true) for private data.
--   * Ordinary users cannot assign themselves privileged roles.
--   * Editors cannot approve their own sensitive scientific content.
--   * Administrators have controlled access but remain auditable.
--   * SECURITY DEFINER functions use a restricted search_path.
--   * Policies are created idempotently via DROP POLICY IF EXISTS followed by
--     CREATE POLICY (PostgreSQL does not support IF NOT EXISTS on CREATE POLICY).
--   * Each CREATE POLICY specifies exactly ONE operation (SELECT, INSERT,
--     UPDATE, or DELETE) because PostgreSQL does not allow comma-separated
--     operations in the FOR clause.
-- Depends on: 001 through 009.

-- ------------------------------------------------------------------------
-- Add created_by columns to content tables for ownership tracking.
-- ------------------------------------------------------------------------
ALTER TABLE public.active_ingredients
    ADD COLUMN IF NOT EXISTS created_by UUID
        REFERENCES public.user_profiles (user_id)
        ON DELETE SET NULL;

ALTER TABLE public.drugs
    ADD COLUMN IF NOT EXISTS created_by UUID
        REFERENCES public.user_profiles (user_id)
        ON DELETE SET NULL;

ALTER TABLE public.brand_products
    ADD COLUMN IF NOT EXISTS created_by UUID
        REFERENCES public.user_profiles (user_id)
        ON DELETE SET NULL;

ALTER TABLE public.drug_evidence
    ADD COLUMN IF NOT EXISTS created_by UUID
        REFERENCES public.user_profiles (user_id)
        ON DELETE SET NULL;

CREATE INDEX idx_active_ingredients_created_by ON public.active_ingredients (created_by);
CREATE INDEX idx_drugs_created_by ON public.drugs (created_by);
CREATE INDEX idx_brand_products_created_by ON public.brand_products (created_by);
CREATE INDEX idx_drug_evidence_created_by ON public.drug_evidence (created_by);

-- ------------------------------------------------------------------------
-- Enable RLS on all tables
-- ------------------------------------------------------------------------

-- Public reference tables (read-only for authenticated, write for admin/editor)
ALTER TABLE public.countries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.body_systems ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.therapeutic_classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pharmacological_classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drug_classes ENABLE ROW LEVEL SECURITY;

-- Drug catalog
ALTER TABLE public.active_ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drugs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drug_ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drug_class_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drug_indications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drug_contraindications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drug_adverse_effects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drug_interactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drug_dosage_information ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drug_special_populations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drug_images ENABLE ROW LEVEL SECURITY;

-- Companies and market
ALTER TABLE public.manufacturers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_authorization_holders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.distributors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.brand_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_presentations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_markets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_registration_records ENABLE ROW LEVEL SECURITY;

-- Scientific evidence and reviews
ALTER TABLE public.scientific_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drug_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_reviews ENABLE ROW LEVEL SECURITY;

-- Users and messaging
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_read_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Import and audit
ALTER TABLE public.import_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.import_batch_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.import_errors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_records ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------------------
-- FORCE ROW LEVEL SECURITY on user-private tables
--
-- FORCE RLS ensures RLS applies even to the table owner. It is applied to
-- tables containing private user data that are accessed only through
-- authenticated application roles (not the Supabase service role).
--
-- NOT applied to: import tables, audit_logs, sync_records, drug_evidence,
-- content_reviews (service role writes these), or public reference tables
-- (no private data).
-- ------------------------------------------------------------------------
ALTER TABLE public.user_profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE public.conversations FORCE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_participants FORCE ROW LEVEL SECURITY;
ALTER TABLE public.messages FORCE ROW LEVEL SECURITY;
ALTER TABLE public.message_read_receipts FORCE ROW LEVEL SECURITY;
ALTER TABLE public.notifications FORCE ROW LEVEL SECURITY;

-- ------------------------------------------------------------------------
-- Helper: role-check expressions (inline subqueries to avoid function
-- privilege issues in RLS policy evaluation).
-- ------------------------------------------------------------------------

-- A policy condition is TRUE when the current user has the given role.
-- We use EXISTS on user_profiles rather than calling a function directly,
-- so that RLS evaluation works reliably regardless of function grants.

-- ------------------------------------------------------------------------
-- PUBLIC REFERENCE TABLES — authenticated read of active/public content only
-- ------------------------------------------------------------------------

DO $$
BEGIN
    FOR t IN (
        SELECT tablename FROM pg_tables WHERE schemaname = 'public'
        AND tablename IN (
            'countries','body_systems','therapeutic_classes',
            'pharmacological_classes','drug_classes',
            'active_ingredients','drugs','drug_ingredients','drug_class_links',
            'drug_indications','drug_contraindications','drug_adverse_effects',
            'drug_interactions','drug_dosage_information','drug_special_populations',
            'drug_images','manufacturers','marketing_authorization_holders',
            'suppliers','distributors','brand_products','product_presentations',
            'product_markets','product_registration_records','scientific_sources'
        )
    ) LOOP
        EXECUTE format(
            $f$
            DROP POLICY IF EXISTS "authenticated_read_active_%s" ON public.%I;
            CREATE POLICY "authenticated_read_active_%s"
                ON public.%I
                FOR SELECT TO authenticated
                USING (is_active = TRUE)
            $f$, t.tablename, t.tablename, t.tablename
        );
    END LOOP;
END $$;

-- drug_evidence: only verified evidence is publicly readable.
DROP POLICY IF EXISTS "authenticated_read_verified_evidence" ON public.drug_evidence;
CREATE POLICY "authenticated_read_verified_evidence"
    ON public.drug_evidence
    FOR SELECT TO authenticated
    USING (is_verified = TRUE);

-- ------------------------------------------------------------------------
-- user_profiles — users manage own profile; admins manage all
-- ------------------------------------------------------------------------

-- Users can read their own profile.
DROP POLICY IF EXISTS "users_read_own_profile" ON public.user_profiles;
CREATE POLICY "users_read_own_profile"
    ON public.user_profiles
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

-- Users can update their own profile but only non-privileged fields.
-- Privileged columns (role, is_active, email_verified) are protected by
-- column-level privileges (REVOKE/GRANT below), not by OLD/NEW references
-- (which are invalid in RLS policy expressions).
DROP POLICY IF EXISTS "users_update_own_profile" ON public.user_profiles;
CREATE POLICY "users_update_own_profile"
    ON public.user_profiles
    FOR UPDATE TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- Administrators can read/insert/update (not delete) all user profiles.
-- Role changes are permitted here because only administrators reach this policy.
-- Account deactivation uses is_active = FALSE rather than profile deletion.
DROP POLICY IF EXISTS "admins_manage_user_profiles_select" ON public.user_profiles;
CREATE POLICY "admins_manage_user_profiles_select"
    ON public.user_profiles
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    );

DROP POLICY IF EXISTS "admins_manage_user_profiles_insert" ON public.user_profiles;
CREATE POLICY "admins_manage_user_profiles_insert"
    ON public.user_profiles
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    );

DROP POLICY IF EXISTS "admins_manage_user_profiles_update" ON public.user_profiles;
CREATE POLICY "admins_manage_user_profiles_update"
    ON public.user_profiles
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    );

-- ------------------------------------------------------------------------
-- Column-level profile security
--
-- Ordinary authenticated users may UPDATE only explicitly permitted
-- non-privileged columns on their own profile. Privileged columns
-- (role, is_active, email_verified) are protected by column-level
-- REVOKE so they cannot be modified through direct SQL or the API.
--
-- Administrators perform privileged updates through the SECURITY DEFINER
-- function aph_manage_user_role() (defined below), which runs as the
-- function owner and bypasses column-level privilege checks for the caller.
-- ------------------------------------------------------------------------

-- Revoke all UPDATE privileges first, then grant only safe columns.
REVOKE UPDATE ON public.user_profiles FROM PUBLIC;
REVOKE UPDATE ON public.user_profiles FROM authenticated;

-- Ordinary users may update only these self-service fields on their own row.
GRANT UPDATE (full_name, phone, country_id, language) ON public.user_profiles TO authenticated;

-- Administrators and the service role retain full UPDATE through
-- SECURITY DEFINER functions (which run as the function owner).

-- ------------------------------------------------------------------------
-- Controlled admin role management — SECURITY DEFINER RPC
--
-- aph_manage_user_role allows an authorized administrator to change
-- another user's role through a controlled, audited workflow.
--
-- Security properties:
--   * SECURITY DEFINER: runs as the function owner (postgres/supabase admin),
--     so column-level privilege checks do not block the caller.
--   * SET search_path = pg_temp, public: prevents search-path injection.
--   * EXECUTE revoked from PUBLIC: only explicitly granted roles can call it.
--   * Caller must have administrator role in user_profiles.
--   * Target role is validated against allowed values.
--   * Self-promotion is prevented (administrator cannot change their own role
--     through this function; requires a second administrator).
--   * Operation is atomic: role update + audit log entry in one transaction.
--   * Full audit trail: actor, target, old_role, new_role, timestamp.
-- ------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION aph_manage_user_role(
    target_user_id UUID,
    new_role VARCHAR(30)
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_temp, public
AS $$
DECLARE
    caller_role VARCHAR(30);
    old_role VARCHAR(30);
BEGIN
    -- Resolve the caller's role from user_profiles using auth.uid().
    SELECT role INTO caller_role
    FROM public.user_profiles
    WHERE user_id = auth.uid();

    -- Only administrators may invoke this function.
    IF caller_role <> 'administrator' THEN
        RAISE EXCEPTION 'Only administrators can manage user roles.';
    END IF;

    -- Prevent self-role-change: an administrator cannot change their own role.
    -- Requires a second authorized administrator for sensitive self-role changes.
    IF auth.uid() = target_user_id THEN
        RAISE EXCEPTION 'Administrators cannot change their own role through this function. A second administrator is required.';
    END IF;

    -- Validate the target role value.
    IF new_role NOT IN ('user', 'editor', 'scientific_reviewer', 'administrator') THEN
        RAISE EXCEPTION 'Invalid role value: %', new_role;
    END IF;

    -- Fetch the current role of the target user.
    SELECT role INTO old_role
    FROM public.user_profiles
    WHERE user_id = target_user_id;

    IF old_role IS NULL THEN
        RAISE EXCEPTION 'Target user does not exist: %', target_user_id;
    END IF;

    -- No-op if the role is unchanged.
    IF old_role = new_role THEN
        RETURN;
    END IF;

    -- Update the target user's role atomically.
    UPDATE public.user_profiles
    SET role = new_role, updated_at = now()
    WHERE user_id = target_user_id;

    -- Record the role change in the audit log.
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
        'manage_user_role',
        'user_profiles',
        target_user_id,
        jsonb_build_object(
            'target_user_id', target_user_id,
            'old_role', old_role,
            'new_role', new_role
        ),
        now()
    );

END;
$$;

-- Revoke execute from PUBLIC; only administrators should be granted EXECUTE.
REVOKE ALL ON FUNCTION aph_manage_user_role(UUID, VARCHAR(30)) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION aph_manage_user_role(UUID, VARCHAR(30)) TO authenticated;

COMMENT ON FUNCTION aph_manage_user_role(UUID, VARCHAR(30)) IS
    'Controlled admin role management. Changes a target user role with full audit trail. Caller must be an administrator. Self-role-change is prevented.';

-- ------------------------------------------------------------------------
-- Controlled admin profile update — SECURITY DEFINER RPC
--
-- aph_manage_user_profile allows an administrator to update non-role
-- profile fields (e.g. is_active for deactivation) on behalf of another user.
-- Ordinary users update their own fields via column-level grants + RLS.
-- ------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION aph_manage_user_profile(
    target_user_id UUID,
    is_active_param BOOLEAN,
    full_name_param TEXT,
    phone_param VARCHAR(30),
    country_id_param UUID,
    language_param VARCHAR(10)
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_temp, public
AS $$
DECLARE
    caller_role VARCHAR(30);
BEGIN
    -- Resolve the caller's role from user_profiles using auth.uid().
    SELECT role INTO caller_role
    FROM public.user_profiles
    WHERE user_id = auth.uid();

    -- Only administrators may invoke this function.
    IF caller_role <> 'administrator' THEN
        RAISE EXCEPTION 'Only administrators can manage user profiles.';
    END IF;

    -- Update the target user's profile fields atomically.
    UPDATE public.user_profiles
    SET
        is_active = COALESCE(is_active_param, is_active),
        full_name = COALESCE(full_name_param, full_name),
        phone = COALESCE(phone_param, phone),
        country_id = COALESCE(country_id_param, country_id),
        language = COALESCE(language_param, language),
        updated_at = now()
    WHERE user_id = target_user_id;

    -- Record the profile update in the audit log.
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
        'manage_user_profile',
        'user_profiles',
        target_user_id,
        jsonb_build_object(
            'target_user_id', target_user_id,
            'is_active', is_active_param,
            'full_name', full_name_param,
            'phone', phone_param,
            'country_id', country_id_param,
            'language', language_param
        ),
        now()
    );

END;
$$;

-- Revoke execute from PUBLIC.
REVOKE ALL ON FUNCTION aph_manage_user_profile(UUID, BOOLEAN, TEXT, VARCHAR(30), UUID, VARCHAR(10)) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION aph_manage_user_profile(UUID, BOOLEAN, TEXT, VARCHAR(30), UUID, VARCHAR(10)) TO authenticated;

COMMENT ON FUNCTION aph_manage_user_profile(UUID, BOOLEAN, TEXT, VARCHAR(30), UUID, VARCHAR(10)) IS
    'Controlled admin profile management. Updates non-role profile fields with full audit trail. Caller must be an administrator.';

-- ------------------------------------------------------------------------
-- Catalog write policies — editors create/edit drafts; admins full control
-- ------------------------------------------------------------------------

DO $$
BEGIN
    FOR t IN (
        SELECT tablename FROM pg_tables WHERE schemaname = 'public'
        AND tablename IN (
            'active_ingredients','drugs','brand_products'
        )
    ) LOOP
        -- Editors insert their own drafts (unverified only).
        EXECUTE format(
            $f$
            DROP POLICY IF EXISTS "editors_insert_draft_%s" ON public.%I;
            CREATE POLICY "editors_insert_draft_%s"
                ON public.%I
                FOR INSERT TO authenticated
                WITH CHECK (
                    created_by = auth.uid()
                    AND is_active = FALSE
                    AND EXISTS (
                        SELECT 1 FROM public.user_profiles up
                        WHERE up.user_id = auth.uid()
                          AND up.role IN ('editor','administrator')
                    )
                )
            $f$, t.tablename, t.tablename, t.tablename
        );
        -- Editors update their own inactive (draft) rows.
        EXECUTE format(
            $f$
            DROP POLICY IF EXISTS "editors_update_own_draft_%s" ON public.%I;
            CREATE POLICY "editors_update_own_draft_%s"
                ON public.%I
                FOR UPDATE TO authenticated
                USING (
                    created_by = auth.uid()
                    AND is_active = FALSE
                    AND EXISTS (
                        SELECT 1 FROM public.user_profiles up
                        WHERE up.user_id = auth.uid()
                          AND up.role IN ('editor','administrator')
                    )
                )
                WITH CHECK (
                    created_by = auth.uid()
                    AND EXISTS (
                        SELECT 1 FROM public.user_profiles up
                        WHERE up.user_id = auth.uid()
                          AND up.role IN ('editor','administrator')
                    )
                )
            $f$, t.tablename, t.tablename, t.tablename
        );
    END LOOP;
END $$;

-- Administrators have read/insert/update access (no DELETE) to catalog tables.
-- Each operation has a separate policy because PostgreSQL does not allow
-- comma-separated operations in CREATE POLICY FOR clause.
DO $$
BEGIN
    FOR t IN (
        SELECT tablename FROM pg_tables WHERE schemaname = 'public'
        AND tablename IN (
            'active_ingredients','drugs','brand_products','product_presentations',
            'product_markets','product_registration_records','manufacturers',
            'marketing_authorization_holders','suppliers','distributors'
        )
    ) LOOP
        EXECUTE format(
            $f$
            DROP POLICY IF EXISTS "admins_manage_%s_select" ON public.%I;
            CREATE POLICY "admins_manage_%s_select"
                ON public.%I
                FOR SELECT TO authenticated
                USING (
                    EXISTS (
                        SELECT 1 FROM public.user_profiles up
                        WHERE up.user_id = auth.uid()
                          AND up.role = 'administrator'
                    )
                );
            DROP POLICY IF EXISTS "admins_manage_%s_insert" ON public.%I;
            CREATE POLICY "admins_manage_%s_insert"
                ON public.%I
                FOR INSERT TO authenticated
                WITH CHECK (
                    EXISTS (
                        SELECT 1 FROM public.user_profiles up
                        WHERE up.user_id = auth.uid()
                          AND up.role = 'administrator'
                    )
                );
            DROP POLICY IF EXISTS "admins_manage_%s_update" ON public.%I;
            CREATE POLICY "admins_manage_%s_update"
                ON public.%I
                FOR UPDATE TO authenticated
                USING (
                    EXISTS (
                        SELECT 1 FROM public.user_profiles up
                        WHERE up.user_id = auth.uid()
                          AND up.role = 'administrator'
                    )
                )
                WITH CHECK (
                    EXISTS (
                        SELECT 1 FROM public.user_profiles up
                        WHERE up.user_id = auth.uid()
                          AND up.role = 'administrator'
                    )
                );
            $f$, t.tablename, t.tablename, t.tablename, t.tablename, t.tablename, t.tablename
        );
    END LOOP;
END $$;

-- ------------------------------------------------------------------------
-- Scientific evidence and reviews
-- ------------------------------------------------------------------------

-- Editors and admins can insert evidence as unverified drafts only.
-- is_verified = TRUE is prohibited on INSERT by this policy.
DROP POLICY IF EXISTS "editors_insert_evidence" ON public.drug_evidence;
CREATE POLICY "editors_insert_evidence"
    ON public.drug_evidence
    FOR INSERT TO authenticated
    WITH CHECK (
        created_by = auth.uid()
        AND is_verified = FALSE
        AND EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid()
              AND up.role IN ('editor','administrator')
        )
    );

-- Editors can update their own unverified evidence, but cannot set is_verified = TRUE.
DROP POLICY IF EXISTS "editors_update_own_unverified_evidence" ON public.drug_evidence;
CREATE POLICY "editors_update_own_unverified_evidence"
    ON public.drug_evidence
    FOR UPDATE TO authenticated
    USING (
        created_by = auth.uid()
        AND is_verified = FALSE
        AND EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid()
              AND up.role IN ('editor','administrator')
        )
    )
    WITH CHECK (
        created_by = auth.uid()
        AND is_verified = FALSE
        AND EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid()
              AND up.role IN ('editor','administrator')
        )
    );

-- Scientific reviewers and admins can read all evidence for review.
DROP POLICY IF EXISTS "reviewers_read_evidence" ON public.drug_evidence;
CREATE POLICY "reviewers_read_evidence"
    ON public.drug_evidence
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid()
              AND up.role IN ('scientific_reviewer','administrator')
        )
    );

-- Reviewers/admins can create and update content reviews, but NOT delete.
-- Review history is append-only: corrections are made via superseding reviews.
DROP POLICY IF EXISTS "reviewers_manage_content_reviews_select" ON public.content_reviews;
CREATE POLICY "reviewers_manage_content_reviews_select"
    ON public.content_reviews
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid()
              AND up.role IN ('scientific_reviewer','administrator')
        )
    );

DROP POLICY IF EXISTS "reviewers_manage_content_reviews_insert" ON public.content_reviews;
CREATE POLICY "reviewers_manage_content_reviews_insert"
    ON public.content_reviews
    FOR INSERT TO authenticated
    WITH CHECK (
        -- Reviewer must be the authenticated caller (cannot forge reviewer_id).
        reviewer_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid()
              AND up.role IN ('scientific_reviewer','administrator')
        )
        -- reviewed_at is server-assigned via DEFAULT now(), column-level
        -- INSERT privilege excludes reviewed_at so clients cannot specify
        -- it. Defense in depth: reviewer cannot review their own evidence
        -- claim.
        AND NOT EXISTS (
            SELECT 1 FROM public.drug_evidence de
            WHERE de.id = content_reviews.drug_evidence_id
              AND de.created_by = auth.uid()
        )
    );

DROP POLICY IF EXISTS "reviewers_manage_content_reviews_update" ON public.content_reviews;
CREATE POLICY "reviewers_manage_content_reviews_update"
    ON public.content_reviews
    FOR UPDATE TO authenticated
    USING (
        -- Reviewer can only update their own reviews.
        reviewer_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid()
              AND up.role IN ('scientific_reviewer','administrator')
        )
        -- Defense in depth: reviewer cannot review their own evidence claim.
        AND NOT EXISTS (
            SELECT 1 FROM public.drug_evidence de
            WHERE de.id = content_reviews.drug_evidence_id
              AND de.created_by = auth.uid()
        )
    )
    WITH CHECK (
        -- Reviewer cannot forge reviewer_id through UPDATE.
        reviewer_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid()
              AND up.role IN ('scientific_reviewer','administrator')
        )
    );

-- Editors can read reviews on evidence they created.
DROP POLICY IF EXISTS "editors_read_own_evidence_reviews" ON public.content_reviews;
CREATE POLICY "editors_read_own_evidence_reviews"
    ON public.content_reviews
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.drug_evidence de
            WHERE de.id = content_reviews.drug_evidence_id
              AND de.created_by = auth.uid()
        )
    );

-- ------------------------------------------------------------------------
-- Messaging and notifications — participants only
-- ------------------------------------------------------------------------

-- Conversations: participants can read.
DROP POLICY IF EXISTS "participants_read_conversations" ON public.conversations;
CREATE POLICY "participants_read_conversations"
    ON public.conversations
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.conversation_participants cp
            WHERE cp.conversation_id = conversations.id
              AND cp.user_id = auth.uid()
              AND cp.left_at IS NULL
        )
    );

-- Only administrators can create conversations (user-to-admin initiated
-- through the API, which validates and inserts on behalf of the user).
DROP POLICY IF EXISTS "admins_create_conversations" ON public.conversations;
CREATE POLICY "admins_create_conversations"
    ON public.conversations
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    );

-- Conversation participants: manage own membership (no DELETE — leaving is
-- recorded via left_at timestamp instead of row removal).
DROP POLICY IF EXISTS "participants_manage_own_membership_select" ON public.conversation_participants;
CREATE POLICY "participants_manage_own_membership_select"
    ON public.conversation_participants
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "participants_manage_own_membership_insert" ON public.conversation_participants;
CREATE POLICY "participants_manage_own_membership_insert"
    ON public.conversation_participants
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "participants_manage_own_membership_update" ON public.conversation_participants;
CREATE POLICY "participants_manage_own_membership_update"
    ON public.conversation_participants
    FOR UPDATE TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- Messages: participants of the conversation can read; sender can insert.
DROP POLICY IF EXISTS "participants_read_messages" ON public.messages;
CREATE POLICY "participants_read_messages"
    ON public.messages
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.conversation_participants cp
            WHERE cp.conversation_id = messages.conversation_id
              AND cp.user_id = auth.uid()
              AND cp.left_at IS NULL
        )
    );

DROP POLICY IF EXISTS "senders_insert_messages" ON public.messages;
CREATE POLICY "senders_insert_messages"
    ON public.messages
    FOR INSERT TO authenticated
    WITH CHECK (sender_id = auth.uid());

-- Message attachments: participants of the parent conversation can read.
-- INSERT is handled by the trusted backend via Supabase Storage policies
-- (not via database RLS, since storage paths are managed separately).
DROP POLICY IF EXISTS "participants_read_attachments" ON public.message_attachments;
CREATE POLICY "participants_read_attachments"
    ON public.message_attachments
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.messages m
            JOIN public.conversation_participants cp
              ON cp.conversation_id = m.conversation_id
             AND cp.user_id = auth.uid()
             AND cp.left_at IS NULL
            WHERE m.id = message_attachments.message_id
        )
    );

-- Message read receipts: users manage their own receipts (no DELETE).
DROP POLICY IF EXISTS "users_manage_own_read_receipts_select" ON public.message_read_receipts;
CREATE POLICY "users_manage_own_read_receipts_select"
    ON public.message_read_receipts
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "users_manage_own_read_receipts_insert" ON public.message_read_receipts;
CREATE POLICY "users_manage_own_read_receipts_insert"
    ON public.message_read_receipts
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "users_manage_own_read_receipts_update" ON public.message_read_receipts;
CREATE POLICY "users_manage_own_read_receipts_update"
    ON public.message_read_receipts
    FOR UPDATE TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- Notifications: users read/update their own notifications.
-- INSERT is handled by the trusted backend/service role.
DROP POLICY IF EXISTS "users_read_own_notifications" ON public.notifications;
CREATE POLICY "users_read_own_notifications"
    ON public.notifications
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "users_update_own_notifications" ON public.notifications;
CREATE POLICY "users_update_own_notifications"
    ON public.notifications
    FOR UPDATE TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- ------------------------------------------------------------------------
-- Import management — uploaders read own batches; admins manage all
--
-- Import batch items and import_errors are written only by the trusted
-- backend using the Supabase service role (RLS bypass). No client-facing
-- INSERT/UPDATE/DELETE policies are granted for these tables.
-- ------------------------------------------------------------------------

DROP POLICY IF EXISTS "uploaders_read_own_import_batches" ON public.import_batches;
CREATE POLICY "uploaders_read_own_import_batches"
    ON public.import_batches
    FOR SELECT TO authenticated
    USING (uploader_id = auth.uid());

DROP POLICY IF EXISTS "uploaders_insert_own_import_batches" ON public.import_batches;
CREATE POLICY "uploaders_insert_own_import_batches"
    ON public.import_batches
    FOR INSERT TO authenticated
    WITH CHECK (uploader_id = auth.uid());

DROP POLICY IF EXISTS "admins_manage_imports_select" ON public.import_batches;
CREATE POLICY "admins_manage_imports_select"
    ON public.import_batches
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    );

DROP POLICY IF EXISTS "admins_manage_imports_insert" ON public.import_batches;
CREATE POLICY "admins_manage_imports_insert"
    ON public.import_batches
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    );

DROP POLICY IF EXISTS "admins_manage_imports_update" ON public.import_batches;
CREATE POLICY "admins_manage_imports_update"
    ON public.import_batches
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    );

DROP POLICY IF EXISTS "import_items_read_own_batch" ON public.import_batch_items;
CREATE POLICY "import_items_read_own_batch"
    ON public.import_batch_items
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.import_batches ib
            WHERE ib.id = import_batch_items.import_batch_id
              AND ib.uploader_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "import_errors_read_own_batch" ON public.import_errors;
CREATE POLICY "import_errors_read_own_batch"
    ON public.import_errors
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.import_batches ib
            WHERE ib.id = import_errors.import_batch_id
              AND ib.uploader_id = auth.uid()
        )
    );

-- ------------------------------------------------------------------------
-- Audit logs — administrators only (append-only, no self-service)
--
-- Application roles cannot INSERT/UPDATE/DELETE audit_logs directly.
-- Audit entries are written by the backend service using the service role
-- which bypasses RLS.
-- ------------------------------------------------------------------------

DROP POLICY IF EXISTS "admins_read_audit_logs" ON public.audit_logs;
CREATE POLICY "admins_read_audit_logs"
    ON public.audit_logs
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    );

-- ------------------------------------------------------------------------
-- Sync records — administrators manage; clients write via service role
--
-- Client sync records are written by the trusted backend using the service
-- role. No client-facing INSERT policy is granted.
-- ------------------------------------------------------------------------

DROP POLICY IF EXISTS "admins_manage_sync_records_select" ON public.sync_records;
CREATE POLICY "admins_manage_sync_records_select"
    ON public.sync_records
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    );

DROP POLICY IF EXISTS "admins_manage_sync_records_insert" ON public.sync_records;
CREATE POLICY "admins_manage_sync_records_insert"
    ON public.sync_records
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    );

DROP POLICY IF EXISTS "admins_manage_sync_records_update" ON public.sync_records;
CREATE POLICY "admins_manage_sync_records_update"
    ON public.sync_records
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    );

COMMENT ON TABLE public.audit_logs IS
    'Audit log. Application roles cannot INSERT/UPDATE/DELETE directly; the backend service writes entries using the service role (RLS bypass).';