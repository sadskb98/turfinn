-- 018_tournament_min_coins.sql
ALTER TABLE tournaments ADD COLUMN IF NOT EXISTS min_coins INTEGER DEFAULT 0;
