-- 044_split_pay.sql — group split pay for bookings.
--
-- The captain initiates a "split" booking: pays their own share immediately,
-- the slot is held in `pending_split` for 30 minutes, friends pay their
-- shares via a public magic-link page. When all shares are paid the booking
-- transitions to confirmed; if the deadline passes, paid shares are refunded
-- and the booking is cancelled.

ALTER TABLE bookings
    ADD COLUMN IF NOT EXISTS split_token        VARCHAR(64) NULL UNIQUE,
    ADD COLUMN IF NOT EXISTS split_deadline_at  TIMESTAMPTZ NULL,
    ADD COLUMN IF NOT EXISTS split_share_count  INT         NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS split_paid_count   INT         NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_bookings_split_token         ON bookings(split_token);
CREATE INDEX IF NOT EXISTS idx_bookings_split_deadline_at   ON bookings(split_deadline_at) WHERE split_deadline_at IS NOT NULL;

-- One row per share. share_no is 1..split_share_count for stable ordering;
-- payer_phone is captured on the public page (BD canonical identity), and
-- payer_user_id is back-filled if the phone matches an existing user or
-- after the guest signs up.
CREATE TABLE IF NOT EXISTS booking_shares (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id        UUID        NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    share_no          INT         NOT NULL,
    amount_paisa      BIGINT      NOT NULL,
    payer_phone       VARCHAR(20) NULL,
    payer_user_id     UUID        NULL REFERENCES users(id),
    is_captain_cover  BOOLEAN     NOT NULL DEFAULT FALSE,
    status            VARCHAR(20) NOT NULL DEFAULT 'pending',  -- pending, paid, refunded, expired
    paid_at           TIMESTAMPTZ NULL,
    refunded_at       TIMESTAMPTZ NULL,
    ssl_tx_id         VARCHAR(80) NULL,  -- SSL Commerz tran_id when paid
    ssl_val_id        VARCHAR(80) NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (booking_id, share_no)
);

CREATE INDEX IF NOT EXISTS idx_booking_shares_booking_id  ON booking_shares(booking_id);
CREATE INDEX IF NOT EXISTS idx_booking_shares_phone       ON booking_shares(payer_phone) WHERE payer_phone IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_booking_shares_status      ON booking_shares(status);
