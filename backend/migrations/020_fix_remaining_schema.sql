-- Migration 020: Fix remaining schema issues found in E2E round 2
-- Fixes: BUG-2 (reviews.booking_id), BUG-3 (promo_codes.owner_id), BUG-5 (super_admin seed)

-- BUG-2: reviews.booking_id NOT NULL blocks reviews without a booking reference.
-- Migration 004 created reviews with booking_id NOT NULL, but the entity uses a nullable pointer
-- and users should be able to review pitches without tying it to a specific booking.
ALTER TABLE reviews ALTER COLUMN booking_id DROP NOT NULL;

-- BUG-3: promo_codes.owner_id column may not exist if migration 015 wasn't applied
-- (Docker init only runs migrations on first DB creation).
ALTER TABLE promo_codes ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id);
CREATE INDEX IF NOT EXISTS idx_promo_codes_owner ON promo_codes(owner_id);

-- pricing_rules: add owner_id and pitch_id for per-pitch/per-owner smart pricing rules
ALTER TABLE pricing_rules ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id);
ALTER TABLE pricing_rules ADD COLUMN IF NOT EXISTS pitch_id UUID REFERENCES pitches(id);

-- BUG-5: No seeded super_admin user — Super Admin panel returns 403 on all endpoints.
INSERT INTO users (id, phone, name, role, position, skill_level, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000002',
  '+8801000000001',
  'Turfinn Super Admin',
  'super_admin',
  'Flexible',
  'Pro',
  NOW(), NOW()
) ON CONFLICT (phone) DO NOTHING;
