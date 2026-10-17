-- Sports content cache: news articles + match events fetched from external APIs.

CREATE TABLE IF NOT EXISTS news_items (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source        VARCHAR(20)  NOT NULL,
    source_id     VARCHAR(255) NOT NULL,
    category      VARCHAR(50),
    title         TEXT NOT NULL,
    summary       TEXT,
    url           TEXT NOT NULL,
    image_url     TEXT,
    source_name   VARCHAR(120),
    published_at  TIMESTAMPTZ NOT NULL,
    payload       JSONB,
    created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_news_source_id
    ON news_items (source, source_id);
CREATE INDEX IF NOT EXISTS idx_news_published_at
    ON news_items (published_at DESC);
CREATE INDEX IF NOT EXISTS idx_news_category
    ON news_items (category);

CREATE TABLE IF NOT EXISTS match_events (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source        VARCHAR(20)  NOT NULL,
    source_id     VARCHAR(50)  NOT NULL,
    league        VARCHAR(120),
    league_logo   TEXT,
    home_team     VARCHAR(120) NOT NULL,
    home_logo     TEXT,
    away_team     VARCHAR(120) NOT NULL,
    away_logo     TEXT,
    home_score    INT,
    away_score    INT,
    kickoff_at    TIMESTAMPTZ NOT NULL,
    status        VARCHAR(20)  NOT NULL,
    minute_played INT,
    payload       JSONB,
    created_at    TIMESTAMPTZ DEFAULT NOW(),
    updated_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_match_events_source_id
    ON match_events (source, source_id);
CREATE INDEX IF NOT EXISTS idx_match_events_status
    ON match_events (status);
CREATE INDEX IF NOT EXISTS idx_match_events_kickoff_at
    ON match_events (kickoff_at DESC);
