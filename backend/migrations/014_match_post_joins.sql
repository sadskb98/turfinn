CREATE TABLE IF NOT EXISTS match_post_joins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES match_posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id),
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(post_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_match_post_joins_user ON match_post_joins(user_id);
