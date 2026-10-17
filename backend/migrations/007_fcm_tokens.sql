ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token_updated_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_users_fcm_token ON users(fcm_token) WHERE fcm_token IS NOT NULL;
