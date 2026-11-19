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
            CREATE POLICY IF NOT EXISTS "authenticated_read_active_%s"
                ON public.%I
                FOR SELECT TO authenticated
                USING (is_active = TRUE)
            $f$, t.tablename, t.tablename
        );
    END LOOP;
END $$;

-- drug_evidence: only verified evidence is publicly readable.
CREATE POLICY IF NOT EXISTS "authenticated_read_verified_evidence"
    ON public.drug_evidence
    FOR SELECT TO authenticated
    USING (is_verified = TRUE);

-- ------------------------------------------------------------------------
-- user_profiles — users manage own profile; admins manage all
-- ------------------------------------------------------------------------
CREATE POLICY IF NOT EXISTS "users_read_own_profile"
    ON public.user_profiles
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

CREATE POLICY IF NOT EXISTS "users_update_own_profile"
    ON public.user_profiles
    FOR UPDATE TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

CREATE POLICY IF NOT EXISTS "admins_manage_user_profiles"
    ON public.user_profiles
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    );

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
        -- Editors insert their own drafts.
        EXECUTE format(
            $f$
            CREATE POLICY IF NOT EXISTS "editors_insert_draft_%s"
                ON public.%I
                FOR INSERT TO authenticated
                WITH CHECK (
                    created_by = auth.uid()
                    AND EXISTS (
                        SELECT 1 FROM public.user_profiles up
                        WHERE up.user_id = auth.uid()
                          AND up.role IN ('editor','administrator')
                    )
                )
            $f$, t.tablename, t.tablename
        );
        -- Editors update their own inactive (draft) rows.
        EXECUTE format(
            $f$
            CREATE POLICY IF NOT EXISTS "editors_update_own_draft_%s"
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
            $f$, t.tablename, t.tablename
        );
    END LOOP;
END $$;

-- Administrators have full write access to catalog tables.
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
            CREATE POLICY IF NOT EXISTS "admins_manage_%s"
                ON public.%I
                FOR ALL TO authenticated
                USING (
                    EXISTS (
                        SELECT 1 FROM public.user_profiles up
                        WHERE up.user_id = auth.uid()
                          AND up.role = 'administrator'
                    )
                )
            $f$, t.tablename, t.tablename
        );
    END LOOP;
END $$;

-- ------------------------------------------------------------------------
-- Scientific evidence and reviews
-- ------------------------------------------------------------------------

-- Editors and admins can insert evidence (drafts).
CREATE POLICY IF NOT EXISTS "editors_insert_evidence"
    ON public.drug_evidence
    FOR INSERT TO authenticated
    WITH CHECK (
        created_by = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid()
              AND up.role IN ('editor','administrator')
        )
    );

-- Scientific reviewers and admins can read evidence for review.
CREATE POLICY IF NOT EXISTS "reviewers_read_evidence"
    ON public.drug_evidence
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid()
              AND up.role IN ('scientific_reviewer','administrator')
        )
    );

-- Only reviewers/admins can create or update content reviews.
CREATE POLICY IF NOT EXISTS "reviewers_manage_content_reviews"
    ON public.content_reviews
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid()
              AND up.role IN ('scientific_reviewer','administrator')
        )
    );

-- Editors can read reviews on evidence they created.
CREATE POLICY IF NOT EXISTS "editors_read_own_evidence_reviews"
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
CREATE POLICY IF NOT EXISTS "participants_read_conversations"
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
CREATE POLICY IF NOT EXISTS "admins_create_conversations"
    ON public.conversations
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    );

-- Conversation participants: manage own membership.
CREATE POLICY IF NOT EXISTS "participants_manage_own_membership"
    ON public.conversation_participants
    FOR ALL TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- Messages: participants of the conversation can read; sender can insert.
CREATE POLICY IF NOT EXISTS "participants_read_messages"
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

CREATE POLICY IF NOT EXISTS "senders_insert_messages"
    ON public.messages
    FOR INSERT TO authenticated
    WITH CHECK (sender_id = auth.uid());

-- Message attachments: participants of the parent conversation can read.
CREATE POLICY IF NOT EXISTS "participants_read_attachments"
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

-- Message read receipts: users manage their own receipts.
CREATE POLICY IF NOT EXISTS "users_manage_own_read_receipts"
    ON public.message_read_receipts
    FOR ALL TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- Notifications: users read their own notifications.
CREATE POLICY IF NOT EXISTS "users_read_own_notifications"
    ON public.notifications
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

CREATE POLICY IF NOT EXISTS "users_update_own_notifications"
    ON public.notifications
    FOR UPDATE TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- ------------------------------------------------------------------------
-- Import management — uploaders read own batches; admins manage all
-- ------------------------------------------------------------------------

CREATE POLICY IF NOT EXISTS "uploaders_read_own_import_batches"
    ON public.import_batches
    FOR SELECT TO authenticated
    USING (uploader_id = auth.uid());

CREATE POLICY IF NOT EXISTS "uploaders_insert_own_import_batches"
    ON public.import_batches
    FOR INSERT TO authenticated
    WITH CHECK (uploader_id = auth.uid());

CREATE POLICY IF NOT EXISTS "admins_manage_imports"
    ON public.import_batches
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    );

CREATE POLICY IF NOT EXISTS "import_items_read_own_batch"
    ON public.import_batch_items
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.import_batches ib
            WHERE ib.id = import_batch_items.import_batch_id
              AND ib.uploader_id = auth.uid()
        )
    );

CREATE POLICY IF NOT EXISTS "import_errors_read_own_batch"
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
-- ------------------------------------------------------------------------

CREATE POLICY IF NOT EXISTS "admins_read_audit_logs"
    ON public.audit_logs
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    );

-- No INSERT/UPDATE/DELETE policy for audit_logs on application roles:
-- audit entries are written by the backend service (service role) which
-- bypasses RLS. Application roles cannot write audit logs directly.

-- ------------------------------------------------------------------------
-- Sync records — administrators and own client
-- ------------------------------------------------------------------------

CREATE POLICY IF NOT EXISTS "admins_manage_sync_records"
    ON public.sync_records
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles up
            WHERE up.user_id = auth.uid() AND up.role = 'administrator'
        )
    );

COMMENT ON TABLE public.audit_logs IS
    'Audit log. Application roles cannot INSERT/UPDATE/DELETE directly; the backend service writes entries using the service role (RLS bypass).';
