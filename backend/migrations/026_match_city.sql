-- Add city to matches for geo-aware matchmaking with city → global fallback
ALTER TABLE matches ADD COLUMN IF NOT EXISTS city VARCHAR(100) NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS idx_matches_city_status ON matches(city, status);
