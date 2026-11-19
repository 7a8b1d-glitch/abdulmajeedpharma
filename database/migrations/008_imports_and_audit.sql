-- Abdulmajeedpharma (APH) — Phase 02 Database Foundation
-- Migration 008: Import management, audit logs, synchronization
--
-- Tables:
--   import_batches, import_batch_items, import_errors,
--   audit_logs, sync_records
--
-- Design notes:
--   * Supports future CSV / XLSX / JSON / ZIP-with-images imports.
--   * Tracks uploader, timestamps, counts, status, errors, resumability.
--   * Audit logs capture actor, action, entity, timestamp, safe metadata.
--   * NO passwords, tokens, or secrets are stored in audit logs.
--   * sync_records prepare for future offline synchronization.
-- Depends on: 001_extensions_and_helpers.sql, 006_users_and_permissions.sql.

-- ========================================================================
-- import_batches
-- ========================================================================
CREATE TABLE public.import_batches (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    original_filename TEXT NOT NULL,
    import_format     VARCHAR(20) NOT NULL
        CHECK (import_format IN ('csv','xlsx','json','zip_with_images')),
    uploader_id       UUID NOT NULL                         -- auth.users.id
        REFERENCES public.user_profiles (user_id)
        ON DELETE RESTRICT,
    status            VARCHAR(30) NOT NULL DEFAULT 'pending'
        CHECK (status IN (
            'pending', 'running', 'completed', 'failed',
            'partially_completed', 'paused'
        )),
    total_records     INTEGER NOT NULL DEFAULT 0,
    successful_records INTEGER NOT NULL DEFAULT 0,
    failed_records    INTEGER NOT NULL DEFAULT 0,
    duplicate_records INTEGER NOT NULL DEFAULT 0,
    started_at        TIMESTAMPTZ,
    completed_at      TIMESTAMPTZ,
    error_summary     TEXT,
    resumability_metadata JSONB DEFAULT '{}',              -- for resuming interrupted imports
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- import_batch_items
-- ========================================================================
CREATE TABLE public.import_batch_items (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    import_batch_id  UUID NOT NULL
        REFERENCES public.import_batches (id)
        ON DELETE CASCADE,
    row_number       INTEGER NOT NULL,
    source_payload   JSONB NOT NULL,                        -- raw row data
    status           VARCHAR(30) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','imported','failed','duplicate')),
    error_message    TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (import_batch_id, row_number)
);

-- ========================================================================
-- import_errors
-- ========================================================================
CREATE TABLE public.import_errors (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    import_batch_id   UUID NOT NULL
        REFERENCES public.import_batches (id)
        ON DELETE CASCADE,
    import_item_id    UUID
        REFERENCES public.import_batch_items (id)
        ON DELETE SET NULL,
    error_code        VARCHAR(50) NOT NULL,
    error_message     TEXT NOT NULL,
    row_number        INTEGER,
    field_name        VARCHAR(100),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- audit_logs
-- ========================================================================
CREATE TABLE public.audit_logs (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id       UUID,                                     -- auth.users.id (nullable: system actions)
    actor_role     VARCHAR(30),                             -- snapshot of role at time of action
    action         VARCHAR(50) NOT NULL,                    -- e.g. 'create_drug', 'approve_review'
    entity_type    VARCHAR(50) NOT NULL,                    -- e.g. 'drugs', 'content_reviews'
    entity_id      UUID,                                    -- ID of affected row (nullable: bulk ops)
    timestamp      TIMESTAMPTZ NOT NULL DEFAULT now(),
    change_metadata JSONB DEFAULT '{}',                     -- safe change metadata only
    ip_address     INET,
    user_agent     TEXT,

    -- Security: audit_logs must NEVER store passwords, tokens, or secrets.
    CONSTRAINT chk_audit_no_secrets
        CHECK (change_metadata ? 'password' IS NOT TRUE
                 AND change_metadata ? 'access_token' IS NOT TRUE
                 AND change_metadata ? 'service_key' IS NOT TRUE)
);

-- ========================================================================
-- sync_records (future offline synchronization foundation)
-- ========================================================================
CREATE TABLE public.sync_records (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id         VARCHAR(100) NOT NULL,                -- mobile/app client identifier
    table_name        VARCHAR(50) NOT NULL,
    record_id         UUID NOT NULL,
    record_version    INTEGER NOT NULL DEFAULT 1,
    operation         VARCHAR(20) NOT NULL
        CHECK (operation IN ('insert','update','delete')),
    server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    sync_status       VARCHAR(30) NOT NULL DEFAULT 'pending'
        CHECK (sync_status IN ('pending','synced','conflict','failed')),
    conflict_metadata JSONB DEFAULT '{}',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes.
CREATE INDEX idx_import_batches_uploader_id ON public.import_batches (uploader_id);
CREATE INDEX idx_import_batches_status ON public.import_batches (status);
CREATE INDEX idx_import_batches_created_at ON public.import_batches (created_at);

CREATE INDEX idx_import_batch_items_batch_id ON public.import_batch_items (import_batch_id);
CREATE INDEX idx_import_batch_items_status ON public.import_batch_items (status);

CREATE INDEX idx_import_errors_batch_id ON public.import_errors (import_batch_id);

CREATE INDEX idx_audit_logs_actor_id ON public.audit_logs (actor_id);
CREATE INDEX idx_audit_logs_action ON public.audit_logs (action);
CREATE INDEX idx_audit_logs_entity_type_id ON public.audit_logs (entity_type, entity_id);
CREATE INDEX idx_audit_logs_timestamp ON public.audit_logs (timestamp);

CREATE INDEX idx_sync_records_client_id ON public.sync_records (client_id);
CREATE INDEX idx_sync_records_table_record ON public.sync_records (table_name, record_id);
CREATE INDEX idx_sync_records_sync_status ON public.sync_records (sync_status);

CREATE TRIGGER trg_import_batches_updated_at
    BEFORE UPDATE ON public.import_batches
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE public.import_batches IS 'Import batch tracking (CSV, XLSX, JSON, ZIP).';
COMMENT ON TABLE public.import_batch_items IS 'Per-row import items within a batch.';
COMMENT ON TABLE public.import_errors IS 'Import error details per batch/item.';
COMMENT ON TABLE public.audit_logs IS 'Immutable audit trail. No secrets stored.';
COMMENT ON TABLE public.sync_records IS 'Foundation for future offline synchronization.';
