-- Migration 002: booking_events for analytics

CREATE TABLE IF NOT EXISTS booking_events (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        REFERENCES users(id) ON DELETE SET NULL,
    session_id  VARCHAR(100) NOT NULL,
    event_type  VARCHAR(50)  NOT NULL,
    metadata    JSONB        NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_booking_events_user_id    ON booking_events(user_id);
CREATE INDEX idx_booking_events_event_type ON booking_events(event_type);
CREATE INDEX idx_booking_events_created_at ON booking_events(created_at DESC);
