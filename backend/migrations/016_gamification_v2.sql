-- 016_gamification_v2.sql
-- Gamification V2: XP, streaks, check-ins, challenges, leaderboards, referrals

-- XP columns on users
ALTER TABLE users ADD COLUMN IF NOT EXISTS xp INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS level INTEGER DEFAULT 1;

-- XP event log
CREATE TABLE IF NOT EXISTS xp_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    source VARCHAR(50) NOT NULL,
    source_id UUID,
    amount INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_xp_events_user ON xp_events(user_id);
CREATE INDEX IF NOT EXISTS idx_xp_events_created ON xp_events(created_at);

-- User streaks
CREATE TABLE IF NOT EXISTS user_streaks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) UNIQUE,
    current_streak INTEGER DEFAULT 0,
    longest_streak INTEGER DEFAULT 0,
    last_booking_week INTEGER NOT NULL DEFAULT 0,
    last_booking_year INTEGER NOT NULL DEFAULT 0,
    streak_freezes_remaining INTEGER DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Daily check-ins
CREATE TABLE IF NOT EXISTS daily_checkins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    checked_in_at DATE NOT NULL DEFAULT CURRENT_DATE,
    day_in_cycle INTEGER NOT NULL,
    coins_earned INTEGER NOT NULL,
    UNIQUE(user_id, checked_in_at)
);

-- Challenge templates (seed pool)
CREATE TABLE IF NOT EXISTS challenge_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug VARCHAR(50) UNIQUE NOT NULL,
    title VARCHAR(100) NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    type VARCHAR(30) NOT NULL,
    target INTEGER NOT NULL,
    difficulty VARCHAR(10) NOT NULL,
    coin_reward INTEGER NOT NULL,
    xp_reward INTEGER NOT NULL,
    active BOOLEAN DEFAULT true
);

-- Weekly challenge rotation
CREATE TABLE IF NOT EXISTS weekly_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    week_start DATE NOT NULL,
    challenge_template_id UUID NOT NULL REFERENCES challenge_templates(id),
    UNIQUE(week_start, challenge_template_id)
);

-- User progress per weekly challenge
CREATE TABLE IF NOT EXISTS user_challenge_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    weekly_challenge_id UUID NOT NULL REFERENCES weekly_challenges(id),
    progress INTEGER DEFAULT 0,
    completed BOOLEAN DEFAULT false,
    completed_at TIMESTAMPTZ,
    UNIQUE(user_id, weekly_challenge_id)
);

-- Leaderboard entries
CREATE TABLE IF NOT EXISTS leaderboard_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    week_start DATE NOT NULL,
    tier VARCHAR(10) NOT NULL,
    xp_earned INTEGER DEFAULT 0,
    rank INTEGER,
    reward_coins INTEGER DEFAULT 0,
    UNIQUE(user_id, week_start)
);
CREATE INDEX IF NOT EXISTS idx_leaderboard_week_tier ON leaderboard_entries(week_start, tier, xp_earned DESC);

-- Referral codes
CREATE TABLE IF NOT EXISTS referral_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) UNIQUE,
    code VARCHAR(10) UNIQUE NOT NULL,
    total_referrals INTEGER DEFAULT 0,
    total_coins_earned INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Referrals — table may already exist from migration 004 with different columns.
-- CREATE TABLE IF NOT EXISTS is a no-op if it exists, so also add missing columns.
CREATE TABLE IF NOT EXISTS referrals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id UUID NOT NULL REFERENCES users(id),
    referred_id UUID NOT NULL REFERENCES users(id) UNIQUE,
    status VARCHAR(20) DEFAULT 'pending',
    referrer_coins INTEGER DEFAULT 0,
    referred_coins INTEGER DEFAULT 0,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
-- Add columns that may be missing if referrals was created by migration 004
ALTER TABLE referrals ADD COLUMN IF NOT EXISTS referred_id UUID REFERENCES users(id);
ALTER TABLE referrals ADD COLUMN IF NOT EXISTS referrer_coins INTEGER DEFAULT 0;
ALTER TABLE referrals ADD COLUMN IF NOT EXISTS referred_coins INTEGER DEFAULT 0;
ALTER TABLE referrals ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

-- Add wallet_transactions type for new transaction types.
-- The inline CHECK constraint from migration 012 has a system-generated name,
-- so we must look it up dynamically before dropping it.
DO $$
DECLARE cname text;
BEGIN
  FOR cname IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'wallet_transactions'::regclass AND contype = 'c'
  LOOP
    EXECUTE 'ALTER TABLE wallet_transactions DROP CONSTRAINT ' || quote_ident(cname);
  END LOOP;
END$$;
ALTER TABLE wallet_transactions ADD CONSTRAINT wallet_transactions_type_check
    CHECK (type IN ('topup', 'booking_payment', 'reward', 'refund', 'checkin', 'challenge', 'leaderboard', 'referral', 'streak_freeze', 'level_up'));

-- Seed streak badges
INSERT INTO badges (key, name, description, coins_reward) VALUES
    ('streak_3', '3 Week Streak', 'Booked 3 weeks in a row', 100),
    ('streak_5', '5 Week Streak', 'Booked 5 weeks in a row', 200),
    ('streak_10', '10 Week Streak', 'Booked 10 weeks in a row', 500),
    ('streak_20', '20 Week Streak', 'Booked 20 weeks in a row', 1000)
ON CONFLICT (key) DO NOTHING;

-- Seed challenge templates
INSERT INTO challenge_templates (slug, title, description, type, target, difficulty, coin_reward, xp_reward) VALUES
    ('book_2', 'Book 2 Times', 'Complete 2 bookings this week', 'booking_count', 2, 'easy', 50, 75),
    ('book_4', 'Book 4 Times', 'Complete 4 bookings this week', 'booking_count', 4, 'hard', 150, 150),
    ('new_pitch', 'Try a New Pitch', 'Book a pitch you have not visited before', 'unique_pitches', 1, 'medium', 75, 100),
    ('two_pitches', 'Visit 2 Different Pitches', 'Book at 2 different pitches this week', 'unique_pitches', 2, 'medium', 100, 125),
    ('create_post', 'Create a Match Post', 'Create a match post in the feed', 'match_posts', 1, 'easy', 50, 75),
    ('join_2_posts', 'Join 2 Match Posts', 'Join 2 match posts this week', 'match_post_joins', 2, 'medium', 75, 100),
    ('write_review', 'Write a Review', 'Leave a review on a pitch', 'reviews', 1, 'easy', 50, 75),
    ('refer_1', 'Refer a Friend', 'Invite a friend who signs up', 'referrals', 1, 'medium', 100, 125)
ON CONFLICT (slug) DO NOTHING;
