-- User activation flag. Replaces the previous "change-role" lever for
-- moderation: instead of demoting an offender to player, operators
-- deactivate them. Inactive users can't authenticate; the auth middleware
-- rejects their JWT on the next request.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_users_is_active
    ON users(is_active)
    WHERE is_active = FALSE;
