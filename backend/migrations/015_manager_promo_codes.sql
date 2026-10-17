-- Manager-scoped promo codes: allow managers to create promos for their own pitches
ALTER TABLE promo_codes
    ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id);

CREATE INDEX IF NOT EXISTS idx_promo_codes_owner ON promo_codes(owner_id);

COMMENT ON COLUMN promo_codes.owner_id IS 'NULL = platform promo (admin), non-NULL = manager-created promo';
