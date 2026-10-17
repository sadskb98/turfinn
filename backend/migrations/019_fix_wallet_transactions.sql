-- Fix wallet_transactions schema mismatch.
-- Migration 004 created the table with (user_id, amount_paisa, description, ref_id).
-- The GORM entity and all service code expect (wallet_id, amount, type, reference).
-- Migration 012's CREATE TABLE IF NOT EXISTS was a no-op since 004 ran first.

-- Add the columns the entity expects (if missing)
ALTER TABLE wallet_transactions ADD COLUMN IF NOT EXISTS wallet_id UUID REFERENCES wallets(id);
ALTER TABLE wallet_transactions ADD COLUMN IF NOT EXISTS amount INT NOT NULL DEFAULT 0;
ALTER TABLE wallet_transactions ADD COLUMN IF NOT EXISTS reference VARCHAR(100) DEFAULT '';

-- Ensure type column exists (both schemas had it, but guard anyway)
ALTER TABLE wallet_transactions ADD COLUMN IF NOT EXISTS type VARCHAR(30) NOT NULL DEFAULT 'topup';

-- Create index on wallet_id
CREATE INDEX IF NOT EXISTS idx_wallet_tx_wallet ON wallet_transactions(wallet_id);

-- BUG-1 fix: user_id NOT NULL blocks all coin operations since GORM entity
-- uses wallet_id (not user_id) for the relationship. Allow NULL.
ALTER TABLE wallet_transactions ALTER COLUMN user_id DROP NOT NULL;
