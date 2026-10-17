-- Refund tracking on match_join_payments. Set when a host cancels, the
-- match auto-cancels, or an admin issues a refund. The cron retries
-- failed refunds every few minutes until SSL accepts them.

ALTER TABLE match_join_payments
    ADD COLUMN IF NOT EXISTS bank_tran_id      VARCHAR(120),
    ADD COLUMN IF NOT EXISTS refund_ref_id     VARCHAR(120),
    ADD COLUMN IF NOT EXISTS refund_status     VARCHAR(20),
        -- NULL | requested | refunded | refund_failed
    ADD COLUMN IF NOT EXISTS refund_reason     VARCHAR(60),
    ADD COLUMN IF NOT EXISTS refund_requested_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS refund_completed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS refund_attempts   INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS last_refund_error TEXT;

CREATE INDEX IF NOT EXISTS idx_mjp_refund_pending
    ON match_join_payments (refund_status, refund_requested_at)
    WHERE refund_status IN ('requested', 'refund_failed');

-- match_posts gets a "cancelled by host" flag and reason so we can show
-- joiners why their match disappeared.
ALTER TABLE match_posts
    ADD COLUMN IF NOT EXISTS cancelled_at      TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS cancellation_reason VARCHAR(60);
