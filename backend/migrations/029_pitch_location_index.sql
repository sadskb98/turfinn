CREATE INDEX IF NOT EXISTS idx_pitches_location ON pitches(latitude, longitude) WHERE is_active = true;
