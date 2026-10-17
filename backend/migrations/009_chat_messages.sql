CREATE TABLE IF NOT EXISTS chat_messages (
    id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id   UUID        NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    sender_id UUID        NOT NULL REFERENCES users(id),
    content   TEXT        NOT NULL,
    sent_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_team_time
    ON chat_messages(team_id, sent_at DESC);
