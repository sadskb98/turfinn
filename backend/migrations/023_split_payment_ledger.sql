-- 023_split_payment_ledger.sql
-- Split-payment ledger: payment orders, settlements, manager wallets,
-- platform wallet, fee configs, payout infrastructure.

-- ══════════════════════════════════════════════════════════════════════════════
-- 1. PAYMENT ORDERS
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS payment_orders (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id       UUID         NOT NULL REFERENCES bookings(id),
    user_id          UUID         NOT NULL REFERENCES users(id),
    amount_paisa     BIGINT       NOT NULL,
    currency         VARCHAR(3)   NOT NULL DEFAULT 'BDT',
    status           VARCHAR(20)  NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending','success','failed','cancelled')),
    tran_id          VARCHAR(100) UNIQUE,
    val_id           VARCHAR(100),
    gateway_response JSONB,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_orders_booking  ON payment_orders(booking_id);
CREATE INDEX IF NOT EXISTS idx_payment_orders_user     ON payment_orders(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_orders_status   ON payment_orders(status);

-- ══════════════════════════════════════════════════════════════════════════════
-- 2. BOOKING SETTLEMENTS
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS booking_settlements (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_order_id     UUID        NOT NULL UNIQUE REFERENCES payment_orders(id),
    booking_id           UUID        NOT NULL REFERENCES bookings(id),
    total_paid_paisa     BIGINT      NOT NULL,
    owner_payout_paisa   BIGINT      NOT NULL,
    turfinn_revenue_paisa BIGINT     NOT NULL,
    gateway_fee_paisa    BIGINT      NOT NULL,
    hold_days            INT         NOT NULL DEFAULT 3,
    settled_at           TIMESTAMPTZ,
    graduated            BOOLEAN     NOT NULL DEFAULT false,
    graduated_at         TIMESTAMPTZ,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_booking_settlements_booking ON booking_settlements(booking_id);

-- ══════════════════════════════════════════════════════════════════════════════
-- 3. BOOKING TAX LINES
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS booking_tax_lines (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    settlement_id UUID        NOT NULL REFERENCES booking_settlements(id),
    tax_type      VARCHAR(20) NOT NULL,
    rate_bps      INT         NOT NULL,
    amount_paisa  BIGINT      NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_booking_tax_lines_settlement ON booking_tax_lines(settlement_id);

-- ══════════════════════════════════════════════════════════════════════════════
-- 4. MANAGER WALLETS
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS manager_wallets (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    manager_id              UUID        NOT NULL UNIQUE REFERENCES users(id),
    available_balance_paisa BIGINT      NOT NULL DEFAULT 0,
    pending_balance_paisa   BIGINT      NOT NULL DEFAULT 0,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ══════════════════════════════════════════════════════════════════════════════
-- 5. MANAGER WALLET TRANSACTIONS
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS manager_wallet_transactions (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id      UUID        NOT NULL REFERENCES manager_wallets(id),
    amount_paisa   BIGINT      NOT NULL,
    tx_type        VARCHAR(30),
    reference_type VARCHAR(30),
    reference_id   UUID,
    description    TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mgr_wallet_tx_wallet ON manager_wallet_transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_mgr_wallet_tx_created ON manager_wallet_transactions(created_at);

-- ══════════════════════════════════════════════════════════════════════════════
-- 6. PLATFORM WALLET (SINGLETON)
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS platform_wallet (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name          VARCHAR(50) NOT NULL UNIQUE DEFAULT 'turfinn_main',
    balance_paisa BIGINT      NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ══════════════════════════════════════════════════════════════════════════════
-- 7. PLATFORM WALLET TRANSACTIONS
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS platform_wallet_transactions (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id      UUID        NOT NULL REFERENCES platform_wallet(id),
    amount_paisa   BIGINT      NOT NULL,
    tx_type        VARCHAR(30),
    reference_type VARCHAR(30),
    reference_id   UUID,
    description    TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_platform_wallet_tx_created ON platform_wallet_transactions(created_at);

-- ══════════════════════════════════════════════════════════════════════════════
-- 8. PARTNER FEE CONFIGS
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS partner_fee_configs (
    id                        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    manager_id                UUID        UNIQUE REFERENCES users(id),
    commission_bps            INT         NOT NULL DEFAULT 1500,
    payout_min_threshold_paisa BIGINT     NOT NULL DEFAULT 50000,
    hold_days                 INT         NOT NULL DEFAULT 3,
    valid_from                DATE,
    valid_to                  DATE,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_partner_fee_configs_global
    ON partner_fee_configs ((manager_id IS NULL))
    WHERE manager_id IS NULL;

-- ══════════════════════════════════════════════════════════════════════════════
-- 9. GATEWAY FEE RATES
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS gateway_fee_rates (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    card_type  VARCHAR(30) NOT NULL UNIQUE,
    fee_bps    INT         NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ══════════════════════════════════════════════════════════════════════════════
-- 10. TAX RATES
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS tax_rates (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tax_type   VARCHAR(20) NOT NULL,
    rate_bps   INT         NOT NULL,
    valid_from DATE,
    valid_to   DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tax_rates_type ON tax_rates(tax_type);
CREATE UNIQUE INDEX IF NOT EXISTS idx_tax_rates_type_date ON tax_rates (tax_type, valid_from);

-- ══════════════════════════════════════════════════════════════════════════════
-- 11. PAYOUT METHODS
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS payout_methods (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    manager_id     UUID         NOT NULL REFERENCES users(id),
    method_type    VARCHAR(20)  NOT NULL,
    account_number VARCHAR(100) NOT NULL,
    account_name   VARCHAR(200),
    bank_name      VARCHAR(100),
    routing_number VARCHAR(50),
    is_verified    BOOLEAN      NOT NULL DEFAULT false,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payout_methods_manager ON payout_methods(manager_id);

-- ══════════════════════════════════════════════════════════════════════════════
-- 12. PAYOUT REQUESTS
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS payout_requests (
    id                  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    manager_id          UUID         NOT NULL REFERENCES users(id),
    payout_method_id    UUID         NOT NULL REFERENCES payout_methods(id),
    amount_paisa        BIGINT       NOT NULL,
    status              VARCHAR(20)  NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending','approved','processing','completed','rejected')),
    transfer_reference  VARCHAR(200),
    rejection_reason    TEXT,
    processed_at        TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payout_requests_manager ON payout_requests(manager_id);
CREATE INDEX IF NOT EXISTS idx_payout_requests_status  ON payout_requests(status);

-- Enforce at most one active (pending/approved/processing) payout per manager at the DB level.
CREATE UNIQUE INDEX IF NOT EXISTS uq_payout_requests_manager_active
    ON payout_requests(manager_id)
    WHERE status IN ('pending', 'approved', 'processing');

-- ══════════════════════════════════════════════════════════════════════════════
-- 13. REFUNDS
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS refunds (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id       UUID        NOT NULL REFERENCES bookings(id),
    payment_order_id UUID        NOT NULL REFERENCES payment_orders(id),
    amount_paisa     BIGINT      NOT NULL,
    reason           TEXT,
    status           VARCHAR(20) NOT NULL DEFAULT 'pending',
    processed_at     TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_refunds_booking ON refunds(booking_id);

-- ══════════════════════════════════════════════════════════════════════════════
-- 14. MANAGER RECEIVABLES
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS manager_receivables (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    manager_id           UUID        NOT NULL REFERENCES users(id),
    settlement_id        UUID        NOT NULL UNIQUE REFERENCES booking_settlements(id),
    amount_paisa         BIGINT      NOT NULL,
    status               VARCHAR(20) NOT NULL DEFAULT 'outstanding',
    paid_via_payout_id   UUID        REFERENCES payout_requests(id),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_manager_receivables_manager ON manager_receivables(manager_id);
CREATE INDEX IF NOT EXISTS idx_manager_receivables_status  ON manager_receivables(status);

-- ══════════════════════════════════════════════════════════════════════════════
-- 15. GATEWAY FEE RECONCILIATIONS
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS gateway_fee_reconciliations (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    settlement_id UUID        NOT NULL UNIQUE REFERENCES booking_settlements(id),
    charged_paisa BIGINT      NOT NULL,
    actual_paisa  BIGINT      NOT NULL,
    diff_paisa    BIGINT      GENERATED ALWAYS AS (actual_paisa - charged_paisa) STORED,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ══════════════════════════════════════════════════════════════════════════════
-- SEED DATA
-- ══════════════════════════════════════════════════════════════════════════════

-- Default global fee config (manager_id NULL = global)
INSERT INTO partner_fee_configs (manager_id, commission_bps, payout_min_threshold_paisa, hold_days, valid_from)
VALUES (NULL, 1500, 50000, 3, CURRENT_DATE)
ON CONFLICT ((manager_id IS NULL)) WHERE manager_id IS NULL DO NOTHING;

-- Gateway fee rates (SSLCommerz Bangladesh standard)
INSERT INTO gateway_fee_rates (card_type, fee_bps) VALUES
    ('visa',       175),
    ('mastercard', 175),
    ('amex',       250),
    ('bkash',      180),
    ('nagad',      150),
    ('rocket',     150),
    ('other',      200)
ON CONFLICT (card_type) DO NOTHING;

-- Tax rates
INSERT INTO tax_rates (tax_type, rate_bps, valid_from) VALUES
    ('vat', 1500, CURRENT_DATE),
    ('wht',  350, CURRENT_DATE)
ON CONFLICT (tax_type, valid_from) DO NOTHING;

-- Platform wallet singleton
INSERT INTO platform_wallet (name, balance_paisa) VALUES ('turfinn_main', 0)
ON CONFLICT (name) DO NOTHING;
