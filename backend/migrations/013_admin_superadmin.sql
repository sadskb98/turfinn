-- Migration 004: Admin panel modules + Super-admin modules
-- All new tables for platform config, marketing, turf onboarding, disputes,
-- business intelligence, finance/audit, system control, zones & partners.

-- ══════════════════════════════════════════════════════════════════════════════
-- 1. PLATFORM CONFIGURATION
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS platform_settings (
    key         VARCHAR(100) PRIMARY KEY,
    value       TEXT         NOT NULL,
    description TEXT,
    updated_by  UUID         REFERENCES users(id),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

INSERT INTO platform_settings (key, value, description) VALUES
    ('platform_fee_percent', '10', 'Platform fee percentage on each booking'),
    ('booking_cancellation_window_hours', '24', 'Hours before booking start when cancellation is free'),
    ('max_advance_booking_days', '30', 'Maximum days in advance a booking can be made'),
    ('min_booking_duration_minutes', '60', 'Minimum booking duration in minutes'),
    ('auto_confirm_bookings', 'false', 'Auto-confirm bookings without manager approval'),
    ('refund_auto_approve_hours', '24', 'Hours after which refund is auto-approved'),
    ('player_app_maintenance_mode', 'false', 'Player app maintenance mode'),
    ('manager_app_maintenance_mode', 'false', 'Manager app maintenance mode')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS platform_settings_audit (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    setting_key VARCHAR(100) NOT NULL,
    old_value   TEXT,
    new_value   TEXT         NOT NULL,
    changed_by  UUID         NOT NULL REFERENCES users(id),
    changed_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_settings_audit_key ON platform_settings_audit(setting_key);
CREATE INDEX IF NOT EXISTS idx_settings_audit_changed_at ON platform_settings_audit(changed_at);

CREATE TABLE IF NOT EXISTS pricing_rules (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_type       VARCHAR(50) NOT NULL, -- peak_hour_multiplier, weekend_multiplier, holiday_surcharge
    name            VARCHAR(150) NOT NULL,
    multiplier      NUMERIC(5,2) DEFAULT 1.0,
    fixed_amount    NUMERIC(12,2) DEFAULT 0,
    applies_to_days JSONB,        -- e.g. [5,6] for Fri/Sat
    time_from       TIME,
    time_to         TIME,
    is_active       BOOLEAN      NOT NULL DEFAULT true,
    created_by      UUID         REFERENCES users(id),
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pricing_rules_active ON pricing_rules(is_active);
CREATE INDEX IF NOT EXISTS idx_pricing_rules_type ON pricing_rules(rule_type);

CREATE TABLE IF NOT EXISTS feature_flags (
    key         VARCHAR(100) PRIMARY KEY,
    enabled     BOOLEAN      NOT NULL DEFAULT false,
    description TEXT,
    updated_by  UUID         REFERENCES users(id),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

INSERT INTO feature_flags (key, enabled, description) VALUES
    ('enable_social_feed', true, 'Enable the social feed feature'),
    ('enable_tournaments', false, 'Enable tournament brackets'),
    ('enable_in_app_chat', false, 'Enable in-app chat'),
    ('enable_wallet', false, 'Enable wallet and credits'),
    ('enable_referrals', false, 'Enable referral program'),
    ('enable_ratings', true, 'Enable pitch ratings and reviews')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS notification_templates (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    type        VARCHAR(50)  NOT NULL, -- booking_confirmed, booking_cancelled, otp_message, etc.
    channel     VARCHAR(20)  NOT NULL, -- sms, push, email
    subject     VARCHAR(255),
    body        TEXT         NOT NULL,
    variables   JSONB        NOT NULL DEFAULT '[]',
    is_active   BOOLEAN      NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notification_templates_type ON notification_templates(type);

-- ══════════════════════════════════════════════════════════════════════════════
-- 2. MARKETING & GROWTH
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS promo_codes (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    code               VARCHAR(50)  NOT NULL UNIQUE,
    discount_type      VARCHAR(20)  NOT NULL, -- percent, fixed
    discount_value     NUMERIC(12,2) NOT NULL,
    min_booking_amount NUMERIC(12,2) DEFAULT 0,
    max_uses           INT          DEFAULT 0, -- 0 = unlimited
    used_count         INT          NOT NULL DEFAULT 0,
    per_user_limit     INT          DEFAULT 1,
    pitch_ids          JSONB,       -- null = all pitches
    valid_from         TIMESTAMPTZ  NOT NULL,
    valid_to           TIMESTAMPTZ  NOT NULL,
    created_by         UUID         REFERENCES users(id),
    is_active          BOOLEAN      NOT NULL DEFAULT true,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_promo_codes_code ON promo_codes(code);
CREATE INDEX IF NOT EXISTS idx_promo_codes_active ON promo_codes(is_active, valid_from, valid_to);

CREATE TABLE IF NOT EXISTS promo_code_uses (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    promo_code_id    UUID         NOT NULL REFERENCES promo_codes(id),
    user_id          UUID         NOT NULL REFERENCES users(id),
    booking_id       UUID         REFERENCES bookings(id),
    discount_applied NUMERIC(12,2) NOT NULL,
    used_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_promo_uses_code ON promo_code_uses(promo_code_id);
CREATE INDEX IF NOT EXISTS idx_promo_uses_user ON promo_code_uses(user_id);

CREATE TABLE IF NOT EXISTS notification_campaigns (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    title          VARCHAR(255) NOT NULL,
    body           TEXT         NOT NULL,
    segment_type   VARCHAR(50)  NOT NULL, -- all, inactive_30d, pitch_users, city, captains
    segment_params JSONB,
    scheduled_at   TIMESTAMPTZ,
    sent_at        TIMESTAMPTZ,
    sent_count     INT          NOT NULL DEFAULT 0,
    created_by     UUID         NOT NULL REFERENCES users(id),
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_campaigns_scheduled ON notification_campaigns(scheduled_at);

CREATE TABLE IF NOT EXISTS featured_pitches (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    pitch_id   UUID         NOT NULL REFERENCES pitches(id),
    position   INT          NOT NULL CHECK (position BETWEEN 1 AND 10),
    starts_at  TIMESTAMPTZ  NOT NULL,
    ends_at    TIMESTAMPTZ  NOT NULL,
    amount_paid NUMERIC(12,2) DEFAULT 0,
    created_by UUID         REFERENCES users(id),
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_featured_pitches_active ON featured_pitches(starts_at, ends_at);

-- Add wallet balance to users
ALTER TABLE users ADD COLUMN IF NOT EXISTS wallet_balance_paisa BIGINT NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS referral_code VARCHAR(20);

CREATE TABLE IF NOT EXISTS wallet_transactions (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID         NOT NULL REFERENCES users(id),
    amount_paisa BIGINT      NOT NULL,
    type        VARCHAR(30)  NOT NULL, -- credit, debit, referral_reward, refund, promo
    description TEXT,
    ref_id      UUID,        -- booking_id or referral_id
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallet_tx_user ON wallet_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_tx_created ON wallet_transactions(created_at);

CREATE TABLE IF NOT EXISTS referrals (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id     UUID         NOT NULL REFERENCES users(id),
    referred_user_id UUID        NOT NULL REFERENCES users(id),
    booking_id      UUID         REFERENCES bookings(id),
    reward_amount   BIGINT       NOT NULL DEFAULT 5000, -- 50 BDT in paisa
    status          VARCHAR(20)  NOT NULL DEFAULT 'pending', -- pending, rewarded, expired
    rewarded_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_referrals_referrer ON referrals(referrer_id);
CREATE INDEX IF NOT EXISTS idx_referrals_referred ON referrals(referred_user_id);

CREATE TABLE IF NOT EXISTS banners (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    image_url     TEXT         NOT NULL,
    title         VARCHAR(255),
    cta_url       TEXT,
    display_order INT          NOT NULL DEFAULT 0,
    starts_at     TIMESTAMPTZ,
    ends_at       TIMESTAMPTZ,
    is_active     BOOLEAN      NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_banners_active ON banners(is_active, starts_at, ends_at);

-- ══════════════════════════════════════════════════════════════════════════════
-- 3. TURF ONBOARDING & VERIFICATION
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS manager_kyc (
    id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           UUID         NOT NULL REFERENCES users(id) UNIQUE,
    nid_number        VARCHAR(50),
    nid_photo_front_url TEXT,
    nid_photo_back_url  TEXT,
    selfie_url        TEXT,
    business_name     VARCHAR(255),
    payout_account    TEXT,         -- bKash number or bank account JSON
    status            VARCHAR(30)  NOT NULL DEFAULT 'draft', -- draft, submitted, under_review, approved, rejected
    reviewed_by       UUID         REFERENCES users(id),
    review_note       TEXT,
    submitted_at      TIMESTAMPTZ,
    reviewed_at       TIMESTAMPTZ,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_kyc_user ON manager_kyc(user_id);
CREATE INDEX IF NOT EXISTS idx_kyc_status ON manager_kyc(status);

-- Add verification columns to pitches
ALTER TABLE pitches ADD COLUMN IF NOT EXISTS verification_status VARCHAR(30) DEFAULT 'approved'; -- pending, approved, rejected, more_info_requested
ALTER TABLE pitches ADD COLUMN IF NOT EXISTS verification_checklist JSONB;
ALTER TABLE pitches ADD COLUMN IF NOT EXISTS quality_score INT DEFAULT 0;

CREATE TABLE IF NOT EXISTS reviews (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id    UUID         NOT NULL REFERENCES bookings(id),
    pitch_id      UUID         NOT NULL REFERENCES pitches(id),
    user_id       UUID         NOT NULL REFERENCES users(id),
    rating        INT          NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment       TEXT,
    status        VARCHAR(20)  NOT NULL DEFAULT 'active', -- active, flagged, removed
    flagged_reason TEXT,
    moderated_by  UUID         REFERENCES users(id),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_reviews_booking ON reviews(booking_id);
CREATE INDEX IF NOT EXISTS idx_reviews_pitch ON reviews(pitch_id);
CREATE INDEX IF NOT EXISTS idx_reviews_user ON reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_reviews_status ON reviews(status);

-- ══════════════════════════════════════════════════════════════════════════════
-- 4. DISPUTES & SUPPORT
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS disputes (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id       UUID         NOT NULL REFERENCES bookings(id),
    raised_by_user_id UUID        NOT NULL REFERENCES users(id),
    against_user_id  UUID         REFERENCES users(id),
    reason           VARCHAR(50)  NOT NULL, -- pitch_not_available, different_from_description, etc.
    description      TEXT,
    evidence_urls    JSONB,
    status           VARCHAR(30)  NOT NULL DEFAULT 'open', -- open, under_review, awaiting_evidence, resolved
    resolution       VARCHAR(50),  -- full_refund, partial_refund, no_refund, warning_issued, account_suspended
    resolved_by      UUID         REFERENCES users(id),
    internal_notes   TEXT,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    resolved_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_disputes_booking ON disputes(booking_id);
CREATE INDEX IF NOT EXISTS idx_disputes_status ON disputes(status);
CREATE INDEX IF NOT EXISTS idx_disputes_raised_by ON disputes(raised_by_user_id);

CREATE TABLE IF NOT EXISTS support_tickets (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID         NOT NULL REFERENCES users(id),
    category    VARCHAR(30)  NOT NULL, -- booking, payment, account, other
    subject     VARCHAR(255) NOT NULL,
    description TEXT,
    priority    VARCHAR(20)  NOT NULL DEFAULT 'medium', -- low, medium, high, urgent
    status      VARCHAR(20)  NOT NULL DEFAULT 'open', -- open, in_progress, waiting_reply, resolved, closed
    assigned_to UUID         REFERENCES users(id),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_tickets_user ON support_tickets(user_id);
CREATE INDEX IF NOT EXISTS idx_tickets_status ON support_tickets(status);
CREATE INDEX IF NOT EXISTS idx_tickets_priority ON support_tickets(priority);
CREATE INDEX IF NOT EXISTS idx_tickets_assigned ON support_tickets(assigned_to);

CREATE TABLE IF NOT EXISTS ticket_messages (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id  UUID         NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    sender_id  UUID         NOT NULL REFERENCES users(id),
    body       TEXT         NOT NULL,
    is_internal BOOLEAN     NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ticket_msgs_ticket ON ticket_messages(ticket_id);

CREATE TABLE IF NOT EXISTS user_actions (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID         NOT NULL REFERENCES users(id),
    action_type VARCHAR(30)  NOT NULL, -- warning, suspend, ban, unban
    reason      TEXT,
    issued_by   UUID         NOT NULL REFERENCES users(id),
    expires_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_actions_user ON user_actions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_actions_type ON user_actions(action_type);

-- ══════════════════════════════════════════════════════════════════════════════
-- 5. SUPER ADMIN — FINANCE & AUDIT
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS audit_log (
    id          BIGSERIAL    PRIMARY KEY,
    actor_id    UUID         REFERENCES users(id),
    actor_role  VARCHAR(30),
    action      VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50)  NOT NULL,
    entity_id   VARCHAR(100),
    old_value   JSONB,
    new_value   JSONB,
    ip_address  VARCHAR(45),
    user_agent  TEXT,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_actor ON audit_log(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_log(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_log(action);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log(created_at);

CREATE TABLE IF NOT EXISTS ledger_entries (
    id                  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_ref     VARCHAR(100) NOT NULL,
    entry_type          VARCHAR(50)  NOT NULL, -- booking_payment, refund, payout, promo_expense, platform_fee
    debit_account       VARCHAR(50)  NOT NULL, -- player_wallet, manager_wallet, platform_revenue, refund_pool, promo_expense
    credit_account      VARCHAR(50)  NOT NULL,
    amount_paisa        BIGINT       NOT NULL,
    description         TEXT,
    related_entity_type VARCHAR(50),
    related_entity_id   UUID,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ledger_ref ON ledger_entries(transaction_ref);
CREATE INDEX IF NOT EXISTS idx_ledger_type ON ledger_entries(entry_type);
CREATE INDEX IF NOT EXISTS idx_ledger_debit ON ledger_entries(debit_account);
CREATE INDEX IF NOT EXISTS idx_ledger_credit ON ledger_entries(credit_account);
CREATE INDEX IF NOT EXISTS idx_ledger_created ON ledger_entries(created_at);

CREATE TABLE IF NOT EXISTS fraud_flags (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type VARCHAR(50)  NOT NULL, -- user, booking, promo_code
    entity_id   UUID         NOT NULL,
    flag_type   VARCHAR(50)  NOT NULL, -- repeat_cancel, high_cancel_rate, promo_abuse, payout_change
    details     JSONB,
    status      VARCHAR(20)  NOT NULL DEFAULT 'active', -- active, dismissed, escalated
    reviewed_by UUID         REFERENCES users(id),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fraud_status ON fraud_flags(status);
CREATE INDEX IF NOT EXISTS idx_fraud_entity ON fraud_flags(entity_type, entity_id);

-- ══════════════════════════════════════════════════════════════════════════════
-- 6. SUPER ADMIN — SYSTEM CONTROL
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS rate_limit_config (
    endpoint_group      VARCHAR(50) PRIMARY KEY,
    requests_per_minute INT         NOT NULL DEFAULT 60,
    burst               INT         NOT NULL DEFAULT 10,
    is_enabled          BOOLEAN     NOT NULL DEFAULT true,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO rate_limit_config (endpoint_group, requests_per_minute, burst) VALUES
    ('auth', 10, 5),
    ('booking', 30, 10),
    ('search', 60, 20),
    ('events', 120, 50),
    ('admin', 60, 20)
ON CONFLICT (endpoint_group) DO NOTHING;

CREATE TABLE IF NOT EXISTS api_keys (
    id                  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name                VARCHAR(150) NOT NULL,
    key_hash            VARCHAR(255) NOT NULL,
    owner_org           VARCHAR(255),
    scopes              JSONB        NOT NULL DEFAULT '["read_pitches"]',
    rate_limit_override INT,
    last_used_at        TIMESTAMPTZ,
    expires_at          TIMESTAMPTZ,
    is_active           BOOLEAN      NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_api_keys_hash ON api_keys(key_hash);
CREATE INDEX IF NOT EXISTS idx_api_keys_active ON api_keys(is_active);

-- ══════════════════════════════════════════════════════════════════════════════
-- 7. SUPER ADMIN — BUSINESS INTELLIGENCE
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS booking_events (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID         REFERENCES users(id),
    session_id VARCHAR(100),
    event_type VARCHAR(50)  NOT NULL, -- app_open, pitch_search, pitch_view, slot_selected, checkout_started, payment_initiated, booking_confirmed
    metadata   JSONB,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_booking_events_type ON booking_events(event_type);
CREATE INDEX IF NOT EXISTS idx_booking_events_user ON booking_events(user_id);
CREATE INDEX IF NOT EXISTS idx_booking_events_session ON booking_events(session_id);
CREATE INDEX IF NOT EXISTS idx_booking_events_created ON booking_events(created_at);

CREATE TABLE IF NOT EXISTS marketing_spend (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    month      DATE         NOT NULL UNIQUE, -- first day of month
    amount     NUMERIC(14,2) NOT NULL,
    notes      TEXT,
    entered_by UUID         REFERENCES users(id),
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ══════════════════════════════════════════════════════════════════════════════
-- 8. SUPER ADMIN — ZONES & PARTNERS
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS zones (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(100) NOT NULL,
    slug            VARCHAR(100) NOT NULL UNIQUE,
    city            VARCHAR(100) NOT NULL,
    lat             NUMERIC(10,7),
    lng             NUMERIC(10,7),
    radius_km       NUMERIC(6,2) DEFAULT 10,
    is_active       BOOLEAN      NOT NULL DEFAULT true,
    zone_manager_id UUID         REFERENCES users(id),
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_zones_slug ON zones(slug);
CREATE INDEX IF NOT EXISTS idx_zones_active ON zones(is_active);

-- Link pitches to zones
ALTER TABLE pitches ADD COLUMN IF NOT EXISTS zone_id UUID REFERENCES zones(id);
CREATE INDEX IF NOT EXISTS idx_pitches_zone ON pitches(zone_id);

CREATE TABLE IF NOT EXISTS organizations (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name               VARCHAR(255) NOT NULL,
    contact_name       VARCHAR(255),
    contact_email      VARCHAR(255),
    phone              VARCHAR(20),
    billing_address    TEXT,
    credit_limit_paisa BIGINT       NOT NULL DEFAULT 0,
    wallet_balance_paisa BIGINT     NOT NULL DEFAULT 0,
    is_active          BOOLEAN      NOT NULL DEFAULT true,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS org_members (
    org_id   UUID        NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id  UUID        NOT NULL REFERENCES users(id),
    role     VARCHAR(20) NOT NULL DEFAULT 'member', -- owner, member
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (org_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_org_members_user ON org_members(user_id);

CREATE TABLE IF NOT EXISTS resellers (
    id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID          NOT NULL REFERENCES users(id) UNIQUE,
    name                VARCHAR(255)  NOT NULL,
    commission_percent  NUMERIC(5,2)  NOT NULL DEFAULT 5.0,
    total_earned_paisa  BIGINT        NOT NULL DEFAULT 0,
    total_paid_paisa    BIGINT        NOT NULL DEFAULT 0,
    active_pitches_count INT          NOT NULL DEFAULT 0,
    is_active           BOOLEAN       NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_resellers_user ON resellers(user_id);

-- Link pitches to resellers
ALTER TABLE pitches ADD COLUMN IF NOT EXISTS reseller_id UUID REFERENCES resellers(id);

-- ══════════════════════════════════════════════════════════════════════════════
-- 9. UPDATE USER ROLES — add super_admin and zone_manager
-- ══════════════════════════════════════════════════════════════════════════════

-- The role column is VARCHAR, so no enum alteration needed. Just update the
-- application-level validation to accept: player, manager, admin, super_admin, zone_manager
