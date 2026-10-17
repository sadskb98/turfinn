CREATE TABLE IF NOT EXISTS wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES users(id),
    balance INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS wallet_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID NOT NULL REFERENCES wallets(id),
    amount INT NOT NULL,
    type VARCHAR(30) NOT NULL CHECK (type IN ('topup', 'booking_payment', 'reward', 'refund')),
    reference VARCHAR(100) DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- If wallet_transactions was already created by migration 004 with a different schema
-- (user_id/amount_paisa instead of wallet_id/amount), add the missing columns so
-- subsequent migrations and indexes work.
ALTER TABLE wallet_transactions ADD COLUMN IF NOT EXISTS wallet_id UUID REFERENCES wallets(id);
ALTER TABLE wallet_transactions ADD COLUMN IF NOT EXISTS amount INT DEFAULT 0;
-- Make amount_paisa nullable since GORM entity uses 'amount' not 'amount_paisa'
ALTER TABLE wallet_transactions ALTER COLUMN amount_paisa DROP NOT NULL;
ALTER TABLE wallet_transactions ADD COLUMN IF NOT EXISTS reference VARCHAR(100) DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_wallet_tx_wallet ON wallet_transactions(wallet_id);

CREATE TABLE IF NOT EXISTS badges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT DEFAULT '',
    icon_url TEXT DEFAULT '',
    coins_reward INT DEFAULT 0
);

CREATE TABLE IF NOT EXISTS user_badges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    badge_id UUID NOT NULL REFERENCES badges(id),
    earned_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, badge_id)
);
CREATE INDEX IF NOT EXISTS idx_user_badges_user ON user_badges(user_id);

-- Seed default badges
INSERT INTO badges (key, name, description, coins_reward) VALUES
    ('first_booking', 'First Booking', 'Completed your first booking', 10),
    ('early_bird', 'Early Bird', 'Booked a morning slot (before 10 AM)', 5),
    ('regular_player', 'Regular Player', 'Completed 10 bookings', 25),
    ('team_captain', 'Team Captain', 'Created a match post', 10),
    ('social_butterfly', 'Social Butterfly', 'Joined 5 match posts', 15)
ON CONFLICT (key) DO NOTHING;
