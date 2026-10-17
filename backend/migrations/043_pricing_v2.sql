-- Pricing v2: dual-tier business model with volume tiers, 60-day trial,
-- premium ERP gating, and the financial-rails tables (settlement, wallet,
-- credit lines, sponsor placements, add-ons).
--
-- Builds on 042_pitch_plan.sql which added pitches.plan + the default
-- marketplace_fee_bps / walkin_fee_bps columns. Those columns become
-- deprecated for runtime use (the resolver reads tier config + the new
-- override columns); we leave them in place to avoid a destructive
-- rename and so historical rows still validate.

-- ── Pitch override + trial + premium fields ───────────────────────────
ALTER TABLE pitches
    ADD COLUMN IF NOT EXISTS marketplace_fee_bps_override INT NULL,
    ADD COLUMN IF NOT EXISTS walkin_fee_bps_override INT NULL,
    ADD COLUMN IF NOT EXISTS trial_ends_at TIMESTAMPTZ NULL,
    ADD COLUMN IF NOT EXISTS premium_active_until TIMESTAMPTZ NULL,
    ADD COLUMN IF NOT EXISTS marketing_boost_active BOOLEAN NOT NULL DEFAULT FALSE;

-- Existing pitches get a 60-day trial from now so we don't suddenly start
-- charging anyone who's already on the platform without warning.
UPDATE pitches
   SET trial_ends_at = now() + interval '60 days'
 WHERE trial_ends_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_pitches_trial_ends_at
    ON pitches(trial_ends_at)
    WHERE trial_ends_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pitches_premium_active_until
    ON pitches(premium_active_until)
    WHERE premium_active_until IS NOT NULL;

-- ── Settlement accounts: per-owner running payable balance ────────────
-- Money lands in our SSL merchant account on every booking. The owner's
-- share gets credited here. Weekly settlement cron drains this back to
-- 0 and writes ledger payout rows. Until disbursement-API integration is
-- wired, the actual money movement to bKash/bank is manual export.
CREATE TABLE IF NOT EXISTS settlement_accounts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    balance_paisa   BIGINT NOT NULL DEFAULT 0,
    last_settled_at TIMESTAMPTZ NULL,
    bkash_number    VARCHAR(20) NULL,
    bank_account    VARCHAR(40) NULL,
    bank_name       VARCHAR(80) NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(owner_id)
);

CREATE INDEX IF NOT EXISTS idx_settlement_accounts_balance
    ON settlement_accounts(balance_paisa)
    WHERE balance_paisa > 0;

-- ── Player wallets: deposit + interest accrual ────────────────────────
CREATE TABLE IF NOT EXISTS player_wallets (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    balance_paisa            BIGINT NOT NULL DEFAULT 0,
    accrued_interest_paisa   BIGINT NOT NULL DEFAULT 0,
    last_interest_at         TIMESTAMPTZ NULL,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id)
);

-- ── Turf credit lines: rails first, lending later ─────────────────────
CREATE TABLE IF NOT EXISTS turf_credit_lines (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id                 UUID NOT NULL REFERENCES users(id),
    principal_paisa          BIGINT NOT NULL,
    outstanding_paisa        BIGINT NOT NULL,
    apr_bps                  INT NOT NULL,
    repayment_pct_of_booking INT NOT NULL,
    issued_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at                TIMESTAMPTZ NULL,
    status                   VARCHAR(20) NOT NULL DEFAULT 'active',
    notes                    TEXT,
    CONSTRAINT turf_credit_lines_status_check
        CHECK (status IN ('active', 'closed', 'defaulted'))
);

CREATE INDEX IF NOT EXISTS idx_turf_credit_lines_owner
    ON turf_credit_lines(owner_id, status);

-- ── Sponsor placements: empty for now, ready for layer 8 ──────────────
CREATE TABLE IF NOT EXISTS sponsor_placements (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pitch_id        UUID NOT NULL REFERENCES pitches(id) ON DELETE CASCADE,
    sponsor_name    VARCHAR(120) NOT NULL,
    placement_kind  VARCHAR(40) NOT NULL,
    starts_at       TIMESTAMPTZ NOT NULL,
    ends_at         TIMESTAMPTZ NULL,
    revenue_paisa   BIGINT NOT NULL DEFAULT 0,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT sponsor_placements_kind_check
        CHECK (placement_kind IN ('banner', 'jersey', 'post_match', 'court_logo'))
);

-- ── Add-on subscriptions: marketing boost, match guarantee insurance ─
-- Soft-deleted via disabled_at so we keep history. The unique index uses
-- COALESCE(disabled_at, '9999-12-31') so only one ACTIVE row per
-- (pitch, addon) pair can exist at a time.
CREATE TABLE IF NOT EXISTS addon_subscriptions (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pitch_id      UUID NOT NULL REFERENCES pitches(id) ON DELETE CASCADE,
    addon_kind    VARCHAR(40) NOT NULL,
    enabled_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    disabled_at   TIMESTAMPTZ NULL,
    monthly_paisa BIGINT NOT NULL,
    notes         TEXT,
    CONSTRAINT addon_subscriptions_kind_check
        CHECK (addon_kind IN ('marketing_boost', 'match_guarantee_insurance', 'bulk_sms'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_addon_active_per_pitch
    ON addon_subscriptions(pitch_id, addon_kind)
    WHERE disabled_at IS NULL;
