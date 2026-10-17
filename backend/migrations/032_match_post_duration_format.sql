-- Adds duration and format fields to match_posts for richer "I want to play" posts.
ALTER TABLE match_posts
    ADD COLUMN IF NOT EXISTS duration_minutes INT NOT NULL DEFAULT 90,
    ADD COLUMN IF NOT EXISTS format VARCHAR(10);
