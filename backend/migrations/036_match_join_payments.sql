-- Match-join payments (parallel to payment_orders, separate lifecycle).
-- A row is created when a player taps "Pay to join". Status moves
-- pending → success on IPN, or pending → expired by the cron after TTL.
CREATE TABLE IF NOT EXISTS match_join_payments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_post_id   UUID NOT NULL REFERENCES match_posts(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id),
    amount_paisa    BIGINT NOT NULL,
    currency        VARCHAR(3) NOT NULL DEFAULT 'BDT',
    tran_id         VARCHAR(80) UNIQUE,
    val_id          VARCHAR(120),
    status          VARCHAR(20) NOT NULL DEFAULT 'pending',
        -- pending | success | failed | cancelled | expired
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_match_join_payments_match
    ON match_join_payments (match_post_id, status);
CREATE INDEX IF NOT EXISTS idx_match_join_payments_user
    ON match_join_payments (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_match_join_payments_pending
    ON match_join_payments (status, created_at)
    WHERE status = 'pending';
