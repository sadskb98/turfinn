-- 017_tournaments.sql

CREATE TABLE IF NOT EXISTS tournaments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL REFERENCES users(id),
    name VARCHAR(100) NOT NULL,
    description TEXT DEFAULT '',
    format VARCHAR(20) NOT NULL,
    max_teams INTEGER NOT NULL DEFAULT 8,
    entry_fee INTEGER DEFAULT 0,
    prize_pool INTEGER DEFAULT 0,
    visibility VARCHAR(10) NOT NULL DEFAULT 'public',
    invite_code VARCHAR(10) UNIQUE,
    status VARCHAR(20) NOT NULL DEFAULT 'draft',
    starts_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_tournaments_status ON tournaments(status);
CREATE INDEX IF NOT EXISTS idx_tournaments_creator ON tournaments(creator_id);

CREATE TABLE IF NOT EXISTS tournament_teams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id UUID NOT NULL REFERENCES tournaments(id),
    team_id UUID NOT NULL REFERENCES teams(id),
    seed INTEGER,
    eliminated BOOLEAN DEFAULT false,
    registered_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(tournament_id, team_id)
);

CREATE TABLE IF NOT EXISTS tournament_matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id UUID NOT NULL REFERENCES tournaments(id),
    round INTEGER NOT NULL,
    match_order INTEGER NOT NULL,
    home_team_id UUID REFERENCES teams(id),
    away_team_id UUID REFERENCES teams(id),
    home_score INTEGER,
    away_score INTEGER,
    winner_id UUID REFERENCES teams(id),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    reported_by UUID REFERENCES users(id),
    confirmed_by UUID REFERENCES users(id),
    reported_at TIMESTAMPTZ,
    confirmed_at TIMESTAMPTZ,
    scheduled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_tourn_matches_tournament ON tournament_matches(tournament_id);

CREATE TABLE IF NOT EXISTS tournament_disputes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_match_id UUID NOT NULL REFERENCES tournament_matches(id),
    disputer_id UUID NOT NULL REFERENCES users(id),
    reason TEXT NOT NULL DEFAULT '',
    status VARCHAR(20) NOT NULL DEFAULT 'open',
    resolved_by UUID REFERENCES users(id),
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
