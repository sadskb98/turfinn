CREATE TABLE IF NOT EXISTS match_chat_messages (
    id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id  UUID        NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    sender_id UUID        NOT NULL REFERENCES users(id),
    content   TEXT        NOT NULL,
    sent_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_match_chat_match_time
    ON match_chat_messages(match_id, sent_at DESC);
