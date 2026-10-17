-- Add service radius for priority visibility sorting
ALTER TABLE pitches ADD COLUMN IF NOT EXISTS service_radius_km FLOAT;
