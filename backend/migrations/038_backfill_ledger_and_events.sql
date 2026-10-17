-- Backfill ledger_entries + booking_events from existing data so the
-- super-admin Finance / BI views show real numbers immediately. Going
-- forward, all new bookings + payments emit these rows live via
-- LedgerService / BookingEventService, but anything created before this
-- migration ran is invisible to those queries — this script paints the
-- history in.
--
-- Idempotent: each insert checks for an existing row keyed on
-- transaction_ref / event_type so repeated runs are safe.

-- ── 1. Confirmed bookings → cash split into platform_revenue + pitch_owner
INSERT INTO ledger_entries (
    transaction_ref, entry_type, debit_account, credit_account,
    amount_paisa, description, related_entity_type, related_entity_id, created_at
)
SELECT
    'BKG-' || b.id::text,
    'booking_payment',
    'cash',
    'platform_revenue',
    -- 15% commission, in paisa.
    ROUND(b.total_cost * 100 * 0.15)::bigint,
    'Backfill: booking commission',
    'booking',
    b.id,
    b.created_at
FROM bookings b
WHERE b.status IN ('confirmed','completed')
  AND b.total_cost > 0
  AND NOT EXISTS (
    SELECT 1 FROM ledger_entries le
    WHERE le.transaction_ref = 'BKG-' || b.id::text
      AND le.credit_account = 'platform_revenue'
);

INSERT INTO ledger_entries (
    transaction_ref, entry_type, debit_account, credit_account,
    amount_paisa, description, related_entity_type, related_entity_id, created_at
)
SELECT
    'BKG-' || b.id::text,
    'booking_payment',
    'cash',
    'pitch_owner',
    ROUND(b.total_cost * 100 * 0.85)::bigint,
    'Backfill: pitch owner share',
    'booking',
    b.id,
    b.created_at
FROM bookings b
WHERE b.status IN ('confirmed','completed')
  AND b.total_cost > 0
  AND NOT EXISTS (
    SELECT 1 FROM ledger_entries le
    WHERE le.transaction_ref = 'BKG-' || b.id::text
      AND le.credit_account = 'pitch_owner'
);

-- ── 2. Cancelled bookings (with refund) → outflow ledger row
-- We approximate "had a refund" as cancelled_at >= 6h before starts_at,
-- mirroring BookingService.Cancel's policy.
INSERT INTO ledger_entries (
    transaction_ref, entry_type, debit_account, credit_account,
    amount_paisa, description, related_entity_type, related_entity_id, created_at
)
SELECT
    'BKG-' || b.id::text,
    'refund',
    'customer_refund',
    'cash',
    ROUND(b.total_cost * 100)::bigint,
    'Backfill: booking cancellation refund',
    'booking',
    b.id,
    b.updated_at
FROM bookings b
WHERE b.status = 'cancelled'
  AND b.total_cost > 0
  AND b.updated_at <= b.starts_at - interval '6 hours'
  AND NOT EXISTS (
    SELECT 1 FROM ledger_entries le
    WHERE le.transaction_ref = 'BKG-' || b.id::text
      AND le.entry_type = 'refund'
);

-- ── 3. Successful match-join payments → cash → match_pool
INSERT INTO ledger_entries (
    transaction_ref, entry_type, debit_account, credit_account,
    amount_paisa, description, related_entity_type, related_entity_id, created_at
)
SELECT
    'MJP-' || mp.id::text,
    'match_payment',
    'cash',
    'match_pool',
    mp.amount_paisa,
    'Backfill: match join payment',
    'match_join_payment',
    mp.id,
    mp.created_at
FROM match_join_payments mp
WHERE mp.status = 'success'
  AND NOT EXISTS (
    SELECT 1 FROM ledger_entries le
    WHERE le.transaction_ref = 'MJP-' || mp.id::text
      AND le.entry_type = 'match_payment'
);

-- ── 4. Refunded match-join payments → match_pool → customer_refund
INSERT INTO ledger_entries (
    transaction_ref, entry_type, debit_account, credit_account,
    amount_paisa, description, related_entity_type, related_entity_id, created_at
)
SELECT
    'MJP-' || mp.id::text,
    'refund',
    'match_pool',
    'customer_refund',
    mp.amount_paisa,
    'Backfill: match refund (' || COALESCE(mp.refund_reason, 'unknown') || ')',
    'match_join_payment',
    mp.id,
    COALESCE(mp.refund_completed_at, mp.refund_requested_at, mp.updated_at)
FROM match_join_payments mp
WHERE mp.refund_status = 'refunded'
  AND NOT EXISTS (
    SELECT 1 FROM ledger_entries le
    WHERE le.transaction_ref = 'MJP-' || mp.id::text
      AND le.entry_type = 'refund'
);

-- ── 5. booking_events backfill — funnel needs at least 'booking_confirmed'
-- and the match-side events to plot anything.
INSERT INTO booking_events (id, user_id, session_id, event_type, metadata, created_at)
SELECT
    gen_random_uuid(),
    b.user_id,
    'backfill',
    'booking_confirmed',
    jsonb_build_object('booking_id', b.id::text, 'pitch_id', b.pitch_id::text),
    b.created_at
FROM bookings b
WHERE b.status IN ('confirmed','completed')
  AND NOT EXISTS (
    SELECT 1 FROM booking_events be
    WHERE be.event_type = 'booking_confirmed'
      AND be.metadata->>'booking_id' = b.id::text
);

INSERT INTO booking_events (id, user_id, session_id, event_type, metadata, created_at)
SELECT
    gen_random_uuid(),
    b.user_id,
    'backfill',
    'booking_cancelled',
    jsonb_build_object('booking_id', b.id::text),
    b.updated_at
FROM bookings b
WHERE b.status = 'cancelled'
  AND NOT EXISTS (
    SELECT 1 FROM booking_events be
    WHERE be.event_type = 'booking_cancelled'
      AND be.metadata->>'booking_id' = b.id::text
);

INSERT INTO booking_events (id, user_id, session_id, event_type, metadata, created_at)
SELECT
    gen_random_uuid(),
    mp.user_id,
    'backfill',
    'match_paid',
    jsonb_build_object('match_post_id', mp.match_post_id::text,
                      'amount_paisa', mp.amount_paisa),
    mp.created_at
FROM match_join_payments mp
WHERE mp.status = 'success'
  AND NOT EXISTS (
    SELECT 1 FROM booking_events be
    WHERE be.event_type = 'match_paid'
      AND be.metadata->>'match_post_id' = mp.match_post_id::text
      AND be.user_id = mp.user_id
);

INSERT INTO booking_events (id, user_id, session_id, event_type, metadata, created_at)
SELECT
    gen_random_uuid(),
    m.author_id,
    'backfill',
    'match_host_cancelled',
    jsonb_build_object('match_post_id', m.id::text,
                      'reason', COALESCE(m.cancellation_reason, '')),
    COALESCE(m.cancelled_at, m.updated_at)
FROM match_posts m
WHERE m.status = 'cancelled'
  AND NOT EXISTS (
    SELECT 1 FROM booking_events be
    WHERE be.event_type = 'match_host_cancelled'
      AND be.metadata->>'match_post_id' = m.id::text
);
