-- League-aware filtering for sports content + standings cache.

ALTER TABLE news_items
    ADD COLUMN IF NOT EXISTS league_id INT;
CREATE INDEX IF NOT EXISTS idx_news_league_id ON news_items (league_id);

ALTER TABLE match_events
    ADD COLUMN IF NOT EXISTS league_id INT;
CREATE INDEX IF NOT EXISTS idx_match_events_league_id ON match_events (league_id);

CREATE TABLE IF NOT EXISTS match_standings (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    league_id    INT  NOT NULL,
    season       INT  NOT NULL,
    league_name  VARCHAR(120),
    league_logo  TEXT,
    payload      JSONB NOT NULL,
    fetched_at   TIMESTAMPTZ DEFAULT NOW(),
    updated_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_standings_league_season
    ON match_standings (league_id, season);
