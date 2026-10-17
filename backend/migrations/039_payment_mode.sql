-- Payment mode: lets a booking be paid fully online or partially (Turfinn
-- commission online, owner share collected in cash at the venue). Default is
-- decided per-pitch (owners who don't trust online payment for the full
-- amount can default to partial); the player can still toggle if both modes
-- are allowed.

ALTER TABLE bookings
    ADD COLUMN IF NOT EXISTS payment_mode VARCHAR(20) NOT NULL DEFAULT 'full_online',
    ADD COLUMN IF NOT EXISTS cash_due_paisa BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS cash_collected_paisa BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS cash_collected_at TIMESTAMPTZ NULL;

CREATE INDEX IF NOT EXISTS idx_bookings_payment_mode
    ON bookings(payment_mode)
    WHERE payment_mode = 'partial_online';

ALTER TABLE pitches
    ADD COLUMN IF NOT EXISTS allows_partial_payment BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS allows_full_payment BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS default_payment_mode VARCHAR(20) NOT NULL DEFAULT 'partial_online';
