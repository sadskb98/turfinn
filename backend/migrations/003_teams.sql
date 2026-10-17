-- Migration 003: teams, team_members, matches

CREATE TABLE IF NOT EXISTS teams (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name         VARCHAR(150)  NOT NULL,
    code         VARCHAR(20)   NOT NULL UNIQUE,
    format       VARCHAR(20)   NOT NULL,
    formation    VARCHAR(20)   NOT NULL DEFAULT '2-3-1',
    captain_id   UUID          NOT NULL REFERENCES users(id),
    max_players  INT           NOT NULL,
    status       VARCHAR(20)   NOT NULL DEFAULT 'forming',
    created_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    deleted_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_teams_captain_id ON teams(captain_id);
CREATE INDEX IF NOT EXISTS idx_teams_code       ON teams(code);
CREATE INDEX IF NOT EXISTS idx_teams_status     ON teams(status);
CREATE INDEX IF NOT EXISTS idx_teams_deleted_at ON teams(deleted_at);

CREATE TABLE IF NOT EXISTS team_members (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id    UUID          NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    user_id    UUID          NOT NULL REFERENCES users(id),
    role       VARCHAR(20)   NOT NULL DEFAULT 'player',
    position   VARCHAR(50),
    number     INT           NOT NULL DEFAULT 0,
    joined_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    UNIQUE (team_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_team_members_team_id ON team_members(team_id);
CREATE INDEX IF NOT EXISTS idx_team_members_user_id ON team_members(user_id);

CREATE TABLE IF NOT EXISTS matches (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    home_team_id  UUID          NOT NULL REFERENCES teams(id),
    away_team_id  UUID                   REFERENCES teams(id),
    pitch_id      UUID                   REFERENCES pitches(id),
    format        VARCHAR(20)   NOT NULL,
    status        VARCHAR(20)   NOT NULL DEFAULT 'searching',
    scheduled_at  TIMESTAMPTZ,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_matches_home_team_id ON matches(home_team_id);
CREATE INDEX IF NOT EXISTS idx_matches_away_team_id ON matches(away_team_id);
CREATE INDEX IF NOT EXISTS idx_matches_status       ON matches(status);
