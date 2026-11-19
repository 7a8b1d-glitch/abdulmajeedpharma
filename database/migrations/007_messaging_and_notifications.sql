-- Abdulmajeedpharma (APH) — Phase 02 Database Foundation
-- Migration 007: Messaging and notifications
--
-- Tables:
--   conversations, conversation_participants, messages,
--   message_attachments, message_read_receipts, notifications
--
-- Design notes:
--   * Supports user-to-administration conversations.
--   * Sender and recipient identity tracked.
--   * Attachment metadata + storage path (paths not exposed to unrelated users).
--   * Read status and read timestamp.
--   * Conversation status.
--   * Notification type and delivery/read status.
-- Depends on: 001_extensions_and_helpers.sql, 006_users_and_permissions.sql.

-- ========================================================================
-- conversations
-- ========================================================================
CREATE TABLE public.conversations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subject_en      TEXT,
    subject_ar       TEXT,
    status          VARCHAR(30) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','archived','closed')),
    created_by      UUID NOT NULL,                          -- auth.users.id
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- conversation_participants
-- ========================================================================
CREATE TABLE public.conversation_participants (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id   UUID NOT NULL
        REFERENCES public.conversations (id)
        ON DELETE CASCADE,
    user_id           UUID NOT NULL                         -- auth.users.id
        REFERENCES public.user_profiles (user_id)
        ON DELETE CASCADE,
    joined_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    left_at           TIMESTAMPTZ,                          -- NULL = still participant
    UNIQUE (conversation_id, user_id)
);

-- ========================================================================
-- messages
-- ========================================================================
CREATE TABLE public.messages (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id  UUID NOT NULL
        REFERENCES public.conversations (id)
        ON DELETE CASCADE,
    sender_id        UUID NOT NULL                         -- auth.users.id
        REFERENCES public.user_profiles (user_id)
        ON DELETE RESTRICT,
    body_en           TEXT NOT NULL,
    body_ar            TEXT,
    message_type     VARCHAR(30) NOT NULL DEFAULT 'text'
        CHECK (message_type IN ('text','system','attachment')),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- message_attachments
-- ========================================================================
CREATE TABLE public.message_attachments (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id       UUID NOT NULL
        REFERENCES public.messages (id)
        ON DELETE CASCADE,
    storage_path     TEXT NOT NULL,                        -- Supabase Storage path
    file_name        TEXT NOT NULL,
    mime_type        VARCHAR(100),
    size_bytes       BIGINT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========================================================================
-- message_read_receipts
-- ========================================================================
CREATE TABLE public.message_read_receipts (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id  UUID NOT NULL
        REFERENCES public.messages (id)
        ON DELETE CASCADE,
    user_id     UUID NOT NULL                         -- auth.users.id
        REFERENCES public.user_profiles (user_id)
        ON DELETE CASCADE,
    read_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (message_id, user_id)
);

-- ========================================================================
-- notifications
-- ========================================================================
CREATE TABLE public.notifications (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           UUID NOT NULL                         -- auth.users.id
        REFERENCES public.user_profiles (user_id)
        ON DELETE CASCADE,
    type              VARCHAR(40) NOT NULL                  -- e.g. 'message', 'review_request', 'import_complete'
        CHECK (type IN (
            'message', 'review_request', 'review_decision',
            'import_complete', 'import_error', 'system',
            'registration_update', 'security'
        )),
    title_en           TEXT NOT NULL,
    title_ar            TEXT,
    body_en             TEXT,
    body_ar              TEXT,
    data                JSONB DEFAULT '{}',                 -- extensible metadata
    is_read             BOOLEAN NOT NULL DEFAULT FALSE,
    read_at             TIMESTAMPTZ,
    delivered_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes.
CREATE INDEX idx_conversations_created_by ON public.conversations (created_by);
CREATE INDEX idx_conversations_status ON public.conversations (status);

CREATE INDEX idx_conversation_participants_conversation_id ON public.conversation_participants (conversation_id);
CREATE INDEX idx_conversation_participants_user_id ON public.conversation_participants (user_id);

CREATE INDEX idx_messages_conversation_id ON public.messages (conversation_id);
CREATE INDEX idx_messages_sender_id ON public.messages (sender_id);
CREATE INDEX idx_messages_created_at ON public.messages (created_at);

CREATE INDEX idx_message_attachments_message_id ON public.message_attachments (message_id);

CREATE INDEX idx_message_read_receipts_message_id ON public.message_read_receipts (message_id);
CREATE INDEX idx_message_read_receipts_user_id ON public.message_read_receipts (user_id);

CREATE INDEX idx_notifications_user_id ON public.notifications (user_id);
CREATE INDEX idx_notifications_type ON public.notifications (type);
CREATE INDEX idx_notifications_is_read ON public.notifications (is_read);
CREATE INDEX idx_notifications_created_at ON public.notifications (created_at);

-- Triggers for updated_at.
CREATE TRIGGER trg_conversations_updated_at
    BEFORE UPDATE ON public.conversations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE public.conversations IS 'Conversations between users and administration.';
COMMENT ON TABLE public.conversation_participants IS 'Authorized participants of a conversation.';
COMMENT ON TABLE public.messages IS 'Messages within a conversation.';
COMMENT ON TABLE public.message_attachments IS 'Attachment metadata for messages.';
COMMENT ON TABLE public.message_read_receipts IS 'Read receipts for messages.';
COMMENT ON TABLE public.notifications IS 'User notifications with delivery/read status.';
