CREATE TABLE IF NOT EXISTS match_posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id UUID NOT NULL REFERENCES users(id),
    pitch_id UUID REFERENCES pitches(id),
    title VARCHAR(200) NOT NULL,
    description TEXT DEFAULT '',
    match_date TIMESTAMPTZ NOT NULL,
    spots_total INT NOT NULL DEFAULT 10,
    spots_filled INT NOT NULL DEFAULT 1,
    status VARCHAR(20) NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'full', 'cancelled', 'completed')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_match_posts_author ON match_posts(author_id);
CREATE INDEX IF NOT EXISTS idx_match_posts_status ON match_posts(status);
CREATE INDEX IF NOT EXISTS idx_match_posts_date ON match_posts(match_date);
