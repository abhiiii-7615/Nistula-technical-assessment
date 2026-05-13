
-- 1. GUESTS
-- One record per real-world guest, regardless of how many channels they use.
-- Core identity lives here. Channel-specific IDs live in channel_identities.

CREATE TABLE guests (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name           VARCHAR(255)        NOT NULL,
    email               VARCHAR(255)        UNIQUE,
    phone               VARCHAR(20)         UNIQUE,
    nationality         VARCHAR(100),
    preferred_language  VARCHAR(10)         NOT NULL DEFAULT 'en',
    notes               TEXT,                             -- internal staff notes
    created_at          TIMESTAMPTZ         NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ         NOT NULL DEFAULT NOW()
);

-- Index for fast lookup by email and phone during deduplication
CREATE INDEX idx_guests_email ON guests (email);
CREATE INDEX idx_guests_phone ON guests (phone);


-- 2. CHANNEL IDENTITIES
-- Maps one guest to many external channel IDs.
-- e.g. same guest may have a WhatsApp ID, an Airbnb ID, and a Booking.com ID.
-- This is what lets us unify "Rahul on WhatsApp" with "Rahul on Airbnb".


CREATE TYPE channel_source AS ENUM (
    'whatsapp',
    'airbnb',
    'booking_com',
    'instagram',
    'direct'
);

CREATE TABLE channel_identities (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guest_id            UUID            NOT NULL REFERENCES guests (id) ON DELETE CASCADE,
    source              channel_source  NOT NULL,
    external_id         VARCHAR(255)    NOT NULL,  -- platform-specific guest ID
    handle              VARCHAR(255),              -- username/display name on that platform
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    -- one guest can only have one identity per channel
    UNIQUE (source, external_id)
);

CREATE INDEX idx_channel_identities_guest ON channel_identities (guest_id);
CREATE INDEX idx_channel_identities_lookup ON channel_identities (source, external_id);


-- 3. PROPERTIES
-- Reference table for all managed properties.
-- Keeps messages and reservations linked to a real property record.


CREATE TABLE properties (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_code       VARCHAR(50)     NOT NULL UNIQUE,  
    name                VARCHAR(255)    NOT NULL,
    location            VARCHAR(255),
    max_guests          SMALLINT        NOT NULL,
    bedroom_count       SMALLINT        NOT NULL,
    base_rate_inr       NUMERIC(10, 2)  NOT NULL,
    extra_guest_rate    NUMERIC(10, 2)  NOT NULL DEFAULT 0,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);


-- 4. RESERVATIONS
-- One record per booking. Linked to a guest and a property.
-- A guest can have many reservations over time.


CREATE TYPE reservation_status AS ENUM (
    'enquiry',      -- no confirmed booking yet
    'confirmed',
    'checked_in',
    'checked_out',
    'cancelled'
);


CREATE TABLE reservations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_ref         VARCHAR(100)        NOT NULL UNIQUE,  -- e.g. "NIS-2024-0891"
    guest_id            UUID                NOT NULL REFERENCES guests (id),
    property_id         UUID                NOT NULL REFERENCES properties (id),
    status              reservation_status  NOT NULL DEFAULT 'enquiry',
    check_in_date       DATE,
    check_out_date      DATE,
    guest_count         SMALLINT,
    total_amount_inr    NUMERIC(12, 2),
    channel             channel_source,     -- which channel the booking came through
    created_at          TIMESTAMPTZ         NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ         NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_reservations_guest    ON reservations (guest_id);
CREATE INDEX idx_reservations_property ON reservations (property_id);
CREATE INDEX idx_reservations_ref      ON reservations (booking_ref);


-- 5. CONVERSATIONS
-- Groups messages into threads. One conversation per guest per stay context.
-- A guest pre-sales enquiry is one conversation.
-- Their post-booking support is a separate conversation.
-- Linked to a guest always; linked to a reservation once one exists.


CREATE TYPE conversation_status AS ENUM (
    'open',
    'pending_guest',    -- waiting for guest to reply
    'pending_agent',    -- waiting for agent action
    'resolved',
    'escalated'
);

CREATE TABLE conversations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guest_id            UUID                    NOT NULL REFERENCES guests (id),
    reservation_id      UUID                    REFERENCES reservations (id), -- null for pre-booking
    property_id         UUID                    REFERENCES properties (id),
    source              channel_source          NOT NULL,
    status              conversation_status     NOT NULL DEFAULT 'open',
    subject             VARCHAR(500),           -- auto-populated from first message
    created_at          TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
    resolved_at         TIMESTAMPTZ
);

CREATE INDEX idx_conversations_guest        ON conversations (guest_id);
CREATE INDEX idx_conversations_reservation  ON conversations (reservation_id);
CREATE INDEX idx_conversations_status       ON conversations (status);


-- 6. MESSAGES
-- Every message across every channel in one table.
-- Direction: 'inbound' = guest → us, 'outbound' = us → guest.
-- AI fields only populated for inbound messages.
-- Lifecycle fields only populated for outbound messages.


CREATE TYPE message_direction AS ENUM ('inbound', 'outbound');

CREATE TYPE query_type AS ENUM (
    'pre_sales_availability',
    'pre_sales_pricing',
    'post_sales_checkin',
    'special_request',
    'complaint',
    'general_enquiry'
);

CREATE TYPE outbound_status AS ENUM (
    'ai_drafted',       -- Claude produced a reply, not yet reviewed
    'agent_edited',     -- a human modified the AI draft before sending
    'auto_sent',        -- sent automatically (confidence >= 0.85)
    'agent_sent',       -- sent manually by an agent
    'discarded'         -- draft was discarded, different reply sent
);

CREATE TABLE messages (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id     UUID                NOT NULL REFERENCES conversations (id),
    guest_id            UUID                NOT NULL REFERENCES guests (id),
    direction           message_direction   NOT NULL,
    source              channel_source      NOT NULL,
    body                TEXT                NOT NULL,
    query_type          query_type,                     -- classified intent
    ai_confidence       NUMERIC(4, 3),                  -- 0.000 to 1.000
    classifier_source   VARCHAR(50),                    -- who decided the query type 'keywords classifier' or 'claude'

    -- -------------------------------------------------------------------------
    -- OUTBOUND-ONLY: lifecycle tracking fields
    -- Tracks the full journey of a reply from AI draft to delivery
    -- -------------------------------------------------------------------------
    outbound_status     outbound_status,                -- current state of this outbound msg
    inbound_message_id  UUID REFERENCES messages (id),  -- the message this is replying to
    ai_drafted_body     TEXT,                           -- original Claude draft (preserved even if edited)
    agent_id            UUID,                           -- which agent sent/edited (FK to staff table if built)
    sent_at             TIMESTAMPTZ,                    -- when actually delivered to guest

    -- -------------------------------------------------------------------------
    -- METADATA
    -- -------------------------------------------------------------------------
    external_message_id VARCHAR(255),                   -- ID from the source platform
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Enforce that AI fields are only set on inbound messages
    CONSTRAINT chk_ai_fields_inbound CHECK (
        direction = 'inbound' OR (
            query_type IS NULL AND
            ai_confidence IS NULL
        )
    ),
    -- Enforce confidence score range
    CONSTRAINT chk_confidence_range CHECK (
        ai_confidence IS NULL OR
        (ai_confidence >= 0 AND ai_confidence <= 1)
    )
);

CREATE INDEX idx_messages_conversation    ON messages (conversation_id);
CREATE INDEX idx_messages_guest           ON messages (guest_id);
CREATE INDEX idx_messages_direction       ON messages (direction);
CREATE INDEX idx_messages_query_type      ON messages (query_type);
CREATE INDEX idx_messages_outbound_status ON messages (outbound_status);
CREATE INDEX idx_messages_created_at      ON messages (created_at DESC);


-- =============================================================================
-- DESIGN DECISIONS
--
-- 1. GUEST DEDUPLICATION VIA channel_identities (not guests table directly)
--    The guests table holds one canonical record per real person. Channel-
--    specific IDs (WhatsApp number, Airbnb profile ID, Booking.com ID) live
--    in channel_identities with a UNIQUE(source, external_id) constraint.
--    When a new message arrives, we look up channel_identities first. If found,
--    we link to the existing guest. If not, we create a new guest + identity.
--    This avoids duplicating Rahul across 3 channels.
--
-- 2. MESSAGES: ONE TABLE, TWO DIRECTIONS
--    Inbound and outbound messages share one table. 
--    AI fields are inbound-only, lifecycle fields are outbound-only.
--    A CHECK constraint enforces this at the DB level.
--    The alternative (two tables) makes conversation threading harder and requires UNIONs for every timeline query.
--
-- 3. outbound_status TRACKS THE FULL AI LIFECYCLE
--    'ai_drafted' → 'agent_edited' → 'agent_sent' captures exactly what happened to every reply.
--    We also preserve ai_drafted_body separately so we always know what Claude originally wrote, even if an agent changed it.
--    This is critical for evaluating AI quality over time.
--
-- =============================================================================


-- HARDEST DESIGN DECISION

-- The hardest decision was how to handle guest identity across channels.
-- The temptation is to store whatsapp_id, airbnb_id, booking_com_id as columns directly on the guests table.
-- That works for 5 channels but breaks the moment a new channel is added — it requires a schema migration every time.
-- The channel_identities table solves this with a UNIQUE(source, external_id) index, making new channel support a data change, not a schema change.
-- The tradeoff is that every inbound message now requires a JOIN to resolve the guest, but that is a worthwhile cost for a system that expects to add channels over time.