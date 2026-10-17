ALTER TABLE match_posts
    ADD COLUMN IF NOT EXISTS post_type  VARCHAR(20) NOT NULL DEFAULT 'open_match'
        CHECK (post_type IN ('open_match','need_teammates')),
    ADD COLUMN IF NOT EXISTS latitude   DOUBLE PRECISION NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS longitude  DOUBLE PRECISION NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_match_posts_location
    ON match_posts(latitude, longitude) WHERE status = 'open';
CREATE INDEX IF NOT EXISTS idx_match_posts_type
    ON match_posts(post_type, status);
