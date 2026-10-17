ALTER TABLE matches ADD COLUMN IF NOT EXISTS latitude  DOUBLE PRECISION NOT NULL DEFAULT 0;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION NOT NULL DEFAULT 0;

-- Index for rough bounding-box pre-filter before Haversine
CREATE INDEX IF NOT EXISTS idx_matches_location ON matches(latitude, longitude) WHERE status = 'searching';
