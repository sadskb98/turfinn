CREATE TABLE IF NOT EXISTS teams (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(150) NOT NULL,
    captain_id  UUID         NOT NULL REFERENCES users(id),
    size        INT          NOT NULL DEFAULT 5,
    status      VARCHAR(20)  NOT NULL DEFAULT 'open',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_teams_captain_id ON teams(captain_id);
CREATE INDEX IF NOT EXISTS idx_teams_status ON teams(status);
