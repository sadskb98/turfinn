-- Quorum-first matchmaking: when a match crosses the quorum (e.g. 50%
-- spots filled), the system auto-creates a real Booking on the pitch so
-- the slot is reserved against solo bookings. We link it back to the
-- match_post via this column so we can:
--   - skip duplicate booking creation (idempotency)
--   - cascade the cancel if the match later collapses
--   - show "match-confirmed" badges on the pitch calendar UI

ALTER TABLE bookings
    ADD COLUMN IF NOT EXISTS source_match_post_id UUID NULL REFERENCES match_posts(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_bookings_source_match_post_unique
    ON bookings(source_match_post_id)
    WHERE source_match_post_id IS NOT NULL AND status != 'cancelled';

ALTER TABLE match_posts
    ADD COLUMN IF NOT EXISTS booking_id UUID NULL REFERENCES bookings(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS quorum_min_pct INT NOT NULL DEFAULT 50;
