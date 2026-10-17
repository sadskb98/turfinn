# Split-Payment Ledger & Financial System Design

**Date:** 2026-04-17
**Status:** Approved
**Scope:** SSLCommerz payment integration, split-payment ledger, manager wallets, platform wallet, per-partner fee config, payout system, government tax records

---

## Overview

When a player pays for a booking via SSLCommerz, the payment is split three ways:

- **Player** pays `booking_amount + player_fixed_fee`
- **Turf owner** receives `booking_amount − owner_commission − owner_fixed_fee − WHT`
- **Turfinn** earns `player_fixed_fee + owner_commission + owner_fixed_fee − gateway_fee`

Fee parameters have a global default overridable per turf owner. All amounts stored in **paisa** (100 paisa = 1 BDT). Percentages stored as **basis points** (1% = 100 bps) to avoid float rounding.

---

## Architecture

```
Player pays via SSLCommerz
        │
        ▼
POST /api/v1/payment/success  (redirect)
POST /api/v1/payment/ipn      (server fallback)
        │
  ┌─────┴──────────────────────────────────┐
  │ OUTSIDE TRANSACTION                    │
  │ 1. Pre-check: order already paid?      │
  │ 2. Verify HMAC (verify_sign)           │
  │ 3. Call SSLCommerz validation API      │
  │ 4. Assert amount + status = VALID      │
  └─────┬──────────────────────────────────┘
        │
  ┌─────┴──────────────────────────────────┐
  │ SINGLE DB TRANSACTION                  │
  │ 1. SELECT payment_order FOR UPDATE     │
  │ 2. Idempotency guard (status=pending)  │
  │ 3. INSERT booking_settlement           │
  │ 4. INSERT booking_tax_lines            │
  │ 5. Deposit → manager_wallet (pending)  │
  │ 6. Deposit → platform_wallet           │
  │ 7. UPDATE payment_order → paid         │
  │ 8. UPDATE booking → confirmed          │
  └────────────────────────────────────────┘
```

---

## Data Model — 15 Tables

### Group 1: Wallets (4 tables)

#### `manager_wallets`
One row per turf owner. Two balance columns: credits land in `pending_balance_paisa`, graduate to `available_balance_paisa` after the hold window.

```sql
CREATE TABLE manager_wallets (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    manager_id              UUID NOT NULL UNIQUE REFERENCES users(id),
    available_balance_paisa BIGINT NOT NULL DEFAULT 0,
    pending_balance_paisa   BIGINT NOT NULL DEFAULT 0,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

#### `manager_wallet_transactions`
Append-only. `balance_after_paisa` is a snapshot — any row is self-auditable without summing history.

```sql
CREATE TABLE manager_wallet_transactions (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    manager_wallet_id     UUID NOT NULL REFERENCES manager_wallets(id),
    amount_paisa          BIGINT NOT NULL,  -- positive=credit, negative=debit
    type                  VARCHAR(30) NOT NULL CHECK (type IN (
                            'booking_credit','hold_graduation',
                            'payout_hold','payout_hold_release',
                            'refund_debit','wht_deduction','adjustment')),
    reference_type        VARCHAR(30),
    reference_id          UUID,
    description           TEXT,
    balance_after_paisa   BIGINT NOT NULL,  -- snapshot of available_balance after this tx
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_mwt_wallet_created ON manager_wallet_transactions(manager_wallet_id, created_at DESC);
CREATE INDEX idx_mwt_ref ON manager_wallet_transactions(reference_id) WHERE reference_id IS NOT NULL;
```

#### `platform_wallets`
Singleton row. Same SELECT FOR UPDATE semantics as manager_wallets.

```sql
CREATE TABLE platform_wallets (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name          VARCHAR(50) NOT NULL DEFAULT 'turfinn_main',
    balance_paisa BIGINT NOT NULL DEFAULT 0,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO platform_wallets (name) VALUES ('turfinn_main');
```

#### `platform_wallet_transactions`

```sql
CREATE TABLE platform_wallet_transactions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    platform_wallet_id  UUID NOT NULL REFERENCES platform_wallets(id),
    amount_paisa        BIGINT NOT NULL,
    type                VARCHAR(40) NOT NULL CHECK (type IN (
                          'booking_fee_credit','gateway_fee_debit',
                          'payout_funded','wht_collected','wht_remitted',
                          'gateway_fee_adjustment','refund_debit','adjustment')),
    reference_type      VARCHAR(30),
    reference_id        UUID,
    description         TEXT,
    balance_after_paisa BIGINT NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_pwt_created ON platform_wallet_transactions(created_at DESC);
```

---

### Group 2: Fee Configuration (2 tables)

#### `partner_fee_configs`
`manager_id IS NULL` = global default. Per-manager row overrides specific fields. Service always queries manager row first, falls back to global.

```sql
CREATE TABLE partner_fee_configs (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    manager_id                  UUID UNIQUE REFERENCES users(id),  -- NULL = global default
    player_fixed_fee_paisa      BIGINT NOT NULL,        -- e.g. 2000 = ৳20
    owner_fee_bps               INTEGER NOT NULL        -- e.g. 1000 = 10%
                                CHECK (owner_fee_bps BETWEEN 0 AND 10000),
    owner_fixed_fee_paisa       BIGINT NOT NULL,        -- e.g. 1000 = ৳10
    payout_min_threshold_paisa  BIGINT NOT NULL DEFAULT 50000,   -- ৳500
    payout_hold_days            INTEGER NOT NULL DEFAULT 3,
    auto_approve_payout         BOOLEAN NOT NULL DEFAULT false,
    created_by                  UUID REFERENCES users(id),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Seed global default
INSERT INTO partner_fee_configs
    (manager_id, player_fixed_fee_paisa, owner_fee_bps, owner_fixed_fee_paisa)
VALUES (NULL, 2000, 1000, 1000);
```

#### `gateway_fee_rates`
Per card type, versioned. Looked up by `card_type` at settlement time, rate snapshotted into `booking_settlements`.

```sql
CREATE TABLE gateway_fee_rates (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_type   VARCHAR(50) NOT NULL,   -- 'VISA','MASTERCARD','BKASH','ROCKET','DEFAULT'
    fee_bps     INTEGER NOT NULL CHECK (fee_bps BETWEEN 0 AND 10000),
    valid_from  TIMESTAMPTZ NOT NULL,
    valid_to    TIMESTAMPTZ,            -- NULL = currently active
    created_by  UUID REFERENCES users(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_gfr_card_type ON gateway_fee_rates(card_type, valid_from DESC);
-- Seed defaults
INSERT INTO gateway_fee_rates (card_type, fee_bps, valid_from) VALUES
    ('VISA',       250, NOW()),
    ('MASTERCARD', 230, NOW()),
    ('BKASH',      180, NOW()),
    ('ROCKET',     180, NOW()),
    ('DEFAULT',    200, NOW());
```

---

### Group 3: Payments (2 tables)

#### `payment_orders`
SSLCommerz session anchor. Created before redirect; updated on callback.

```sql
CREATE TABLE payment_orders (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tran_id               VARCHAR(50) NOT NULL UNIQUE,   -- sent to SSLCommerz
    user_id               UUID NOT NULL REFERENCES users(id),
    booking_id            UUID REFERENCES bookings(id),  -- NULL for wallet top-ups
    order_type            VARCHAR(20) NOT NULL CHECK (order_type IN ('booking_payment','wallet_topup')),
    amount_paisa          BIGINT NOT NULL,               -- total player pays
    booking_amount_paisa  BIGINT NOT NULL DEFAULT 0,
    player_fee_paisa      BIGINT NOT NULL DEFAULT 0,
    gateway_fee_paisa     BIGINT NOT NULL DEFAULT 0,     -- estimated at initiation
    status                VARCHAR(20) NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending','paid','failed','cancelled','refunded')),
    sslcz_val_id          VARCHAR(100),
    sslcz_bank_tran_id    VARCHAR(100),
    card_type             VARCHAR(50),
    paid_at               TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX idx_payment_orders_val_id
    ON payment_orders(sslcz_val_id) WHERE sslcz_val_id IS NOT NULL;
CREATE INDEX idx_payment_orders_user ON payment_orders(user_id, created_at DESC);
CREATE INDEX idx_payment_orders_booking ON payment_orders(booking_id);
```

#### `booking_settlements`
Immutable after creation. All rates snapshotted — fee config changes never affect past settlements.

```sql
CREATE TABLE booking_settlements (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id                  UUID NOT NULL UNIQUE REFERENCES bookings(id),
    payment_order_id            UUID NOT NULL REFERENCES payment_orders(id),
    manager_id                  UUID NOT NULL REFERENCES users(id),
    gateway_fee_rate_id         UUID NOT NULL REFERENCES gateway_fee_rates(id),

    -- amounts
    total_paid_paisa            BIGINT NOT NULL,
    booking_amount_paisa        BIGINT NOT NULL,
    player_fee_paisa            BIGINT NOT NULL,

    -- owner deductions (snapshotted bps)
    owner_fee_bps               INTEGER NOT NULL,
    owner_fee_bps_amount_paisa  BIGINT NOT NULL,
    owner_fixed_fee_paisa       BIGINT NOT NULL,
    total_owner_deduction_paisa BIGINT NOT NULL,

    -- gateway
    gateway_fee_bps             INTEGER NOT NULL,
    gateway_fee_paisa           BIGINT NOT NULL,

    -- outcomes
    owner_payout_amount_paisa   BIGINT NOT NULL CHECK (owner_payout_amount_paisa >= 0),
    turfinn_revenue_paisa       BIGINT NOT NULL CHECK (turfinn_revenue_paisa >= 0),

    -- hold graduation
    graduated                   BOOLEAN NOT NULL DEFAULT false,

    status                      VARCHAR(20) NOT NULL DEFAULT 'settled'
                                CHECK (status IN ('settled','refunded')),
    settled_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_settlements_manager ON booking_settlements(manager_id, created_at DESC);
CREATE INDEX idx_settlements_period  ON booking_settlements(manager_id, settled_at);
CREATE INDEX idx_settlements_graduated ON booking_settlements(graduated, settled_at)
    WHERE graduated = false;
```

---

### Group 4: Refunds (2 tables)

#### `refunds`

```sql
CREATE TABLE refunds (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_order_id  UUID NOT NULL REFERENCES payment_orders(id),
    booking_id        UUID NOT NULL REFERENCES bookings(id),
    amount_paisa      BIGINT NOT NULL CHECK (amount_paisa > 0),
    refund_type       VARCHAR(10) NOT NULL CHECK (refund_type IN ('full','partial')),
    reason            TEXT,
    initiated_by      UUID NOT NULL REFERENCES users(id),
    gateway_refund_id VARCHAR(100),
    status            VARCHAR(20) NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','processing','completed','failed')),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_refunds_booking ON refunds(booking_id);
```

#### `manager_receivables`
When a refund is owed after the manager has already been paid out.

```sql
CREATE TABLE manager_receivables (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    manager_id     UUID NOT NULL REFERENCES users(id),
    refund_id      UUID NOT NULL REFERENCES refunds(id),
    amount_paisa   BIGINT NOT NULL,
    status         VARCHAR(20) NOT NULL DEFAULT 'outstanding'
                   CHECK (status IN ('outstanding','offset','written_off')),
    offset_against UUID REFERENCES payout_requests(id),  -- payout that cleared this debt
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at    TIMESTAMPTZ
);
CREATE INDEX idx_receivables_manager ON manager_receivables(manager_id, status);
```

---

### Group 5: Payouts (2 tables)

#### `payout_methods`

```sql
CREATE TABLE payout_methods (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    manager_id     UUID NOT NULL REFERENCES users(id),
    method_type    VARCHAR(10) NOT NULL CHECK (method_type IN ('bkash','bank')),
    bkash_number   VARCHAR(20),
    bank_name      VARCHAR(100),
    account_name   VARCHAR(255),
    account_number VARCHAR(50),
    branch_name    VARCHAR(100),
    routing_number VARCHAR(30),
    is_default     BOOLEAN NOT NULL DEFAULT false,
    is_verified    BOOLEAN NOT NULL DEFAULT false,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_payout_methods_manager ON payout_methods(manager_id);
```

#### `payout_requests`

```sql
CREATE TABLE payout_requests (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    manager_id          UUID NOT NULL REFERENCES users(id),
    manager_wallet_id   UUID NOT NULL REFERENCES manager_wallets(id),
    payout_method_id    UUID NOT NULL REFERENCES payout_methods(id),
    amount_paisa        BIGINT NOT NULL CHECK (amount_paisa > 0),
    status              VARCHAR(20) NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','approved','processing','completed','rejected')),
    requested_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    approved_by         UUID REFERENCES users(id),
    approved_at         TIMESTAMPTZ,
    processed_at        TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    transfer_reference  VARCHAR(100) UNIQUE,   -- bKash/bank ref, unique when set
    rejection_reason    TEXT,
    admin_notes         TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_payout_requests_manager ON payout_requests(manager_id, status);
CREATE INDEX idx_payout_requests_status  ON payout_requests(status, requested_at);
```

---

### Group 6: Gateway Reconciliation (1 table)

#### `gateway_fee_reconciliations`

```sql
CREATE TABLE gateway_fee_reconciliations (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    month            DATE NOT NULL UNIQUE,
    estimated_paisa  BIGINT NOT NULL,
    actual_paisa     BIGINT NOT NULL,
    variance_paisa   BIGINT GENERATED ALWAYS AS (actual_paisa - estimated_paisa) STORED,
    adjustment_tx_id UUID REFERENCES platform_wallet_transactions(id),
    reconciled_by    UUID REFERENCES users(id),
    reconciled_at    TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

### Group 7: Tax Records (2 tables)

#### `tax_rates`
Versioned. Never deleted — old records give historical reference. `valid_to = NULL` = currently active.

```sql
CREATE TABLE tax_rates (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tax_type     VARCHAR(20) NOT NULL CHECK (tax_type IN ('vat','withholding_tax')),
    rate_bps     INTEGER NOT NULL CHECK (rate_bps BETWEEN 0 AND 10000),
    valid_from   TIMESTAMPTZ NOT NULL,
    valid_to     TIMESTAMPTZ,
    jurisdiction VARCHAR(10) NOT NULL DEFAULT 'BD',
    description  TEXT,
    created_by   UUID REFERENCES users(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_tax_rates_type ON tax_rates(tax_type, valid_from DESC);
-- Seed
INSERT INTO tax_rates (tax_type, rate_bps, valid_from, description) VALUES
    ('vat',              1500, NOW(), 'Bangladesh VAT 15%'),
    ('withholding_tax',  1000, NOW(), 'Bangladesh AIT/TDS 10% on service payments');
```

#### `booking_tax_lines`
Computed at settlement. Immutable. Accountant runs CSV export per month for NBR filing.

```sql
CREATE TABLE booking_tax_lines (
    id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_settlement_id     UUID NOT NULL UNIQUE REFERENCES booking_settlements(id),
    booking_id                UUID NOT NULL REFERENCES bookings(id),
    manager_id                UUID NOT NULL REFERENCES users(id),
    tax_period                DATE NOT NULL,          -- first day of month

    -- VAT (on platform fees, remitted by Turfinn to NBR)
    vat_taxable_amount_paisa  BIGINT NOT NULL,        -- player_fixed_fee + owner_fee_deductions
    vat_rate_bps              INTEGER NOT NULL,
    vat_amount_paisa          BIGINT NOT NULL,

    -- Withholding Tax (deducted from owner payout, remitted to NBR on owner's behalf)
    wht_taxable_amount_paisa  BIGINT NOT NULL,        -- owner_payout before WHT
    wht_rate_bps              INTEGER NOT NULL,
    wht_amount_paisa          BIGINT NOT NULL,
    owner_net_payout_paisa    BIGINT NOT NULL,        -- what owner actually receives

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_tax_lines_period   ON booking_tax_lines(tax_period);
CREATE INDEX idx_tax_lines_manager  ON booking_tax_lines(manager_id, tax_period);
```

---

## Split Formula

All integer arithmetic. Applied inside the settlement DB transaction.

```go
// Fee lookup
cfg  := feeService.GetConfig(ctx, managerID)   // manager row or global fallback
gfr  := feeService.GetGatewayRate(ctx, cardType) // by card_type, active rate
vat  := taxService.GetRate(ctx, "vat")
wht  := taxService.GetRate(ctx, "withholding_tax")

// Split
ownerCommissionPaisa  := (bookingAmountPaisa * int64(cfg.OwnerFeeBps) + 5000) / 10000
totalOwnerDeduction   := ownerCommissionPaisa + cfg.OwnerFixedFeePaisa
ownerPayoutPaisa      := bookingAmountPaisa - totalOwnerDeduction
gatewayFeePaisa       := (totalPaidPaisa * int64(gfr.FeeBps) + 5000) / 10000
turfinnRevenuePaisa   := cfg.PlayerFixedFeePaisa + totalOwnerDeduction - gatewayFeePaisa

// Tax
vatTaxable  := cfg.PlayerFixedFeePaisa + totalOwnerDeduction
vatAmount   := (vatTaxable * int64(vat.RateBps) + 5000) / 10000
whtAmount   := (ownerPayoutPaisa * int64(wht.RateBps) + 5000) / 10000
ownerNet    := ownerPayoutPaisa - whtAmount

// Invariant — assert before commit, rollback if fails
assert: ownerPayoutPaisa + turfinnRevenuePaisa + gatewayFeePaisa == totalPaidPaisa
```

---

## Payment Flow

### Initiation

```
POST /api/v1/bookings/:id/pay

OUTSIDE TRANSACTION:
→ GET partner_fee_configs for manager (fallback to global)
→ calculate total_to_pay = booking_amount + player_fixed_fee
→ INSERT payment_order (status: pending, tran_id: "TF_{booking_id}_{ts}")
→ POST to SSLCommerz initiate API  ← 3rd party, never inside transaction
→ return { redirectGatewayURL }
```

### Settlement (success + IPN — identical logic)

```
POST /api/v1/payment/success
POST /api/v1/payment/ipn

STEP 1 — pre-check (no lock):
→ SELECT status FROM payment_orders WHERE tran_id = ?
→ if status = 'paid' → log, return 200  (already settled)

STEP 2 — HMAC verification (outside transaction):
→ sort fields in verify_key alphabetically
→ compute MD5(sorted_kvs + MD5(store_passwd))
→ assert == verify_sign
→ if mismatch → log security alert, return 200

STEP 3 — SSLCommerz validation API (outside transaction):
→ GET /validationserverAPI.php?val_id=...  ← 3rd party
→ assert response.status == "VALID"
→ assert response.amount == payment_order.amount_paisa / 100

STEP 4 — SINGLE DB TRANSACTION:
→ SELECT payment_order FOR UPDATE → assert status = pending
→ compute split + tax (pure calculation, no I/O)
→ INSERT booking_settlement
→ INSERT booking_tax_lines
→ Deposit(tx, manager_wallet.pending_balance, owner_net_payout, 'booking_credit')
→ Deposit(tx, platform_wallet, turfinn_revenue + wht_amount, 'booking_fee_credit')
→ UPDATE payment_order → status=paid, sslcz_val_id, card_type
→ UPDATE booking → status=confirmed
COMMIT

POST /api/v1/payment/fail | /cancel
→ single UPDATE payment_order.status (no wallet writes, no transaction needed)
```

---

## Concurrency Model

```go
func Deposit(tx *gorm.DB, walletID uuid.UUID, amount int64, balanceField string, ...) error {
    var w ManagerWallet
    tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&w, walletID)
    // balanceField = "pending_balance_paisa" or "available_balance_paisa"
    newBalance := w.field(balanceField) + amount
    tx.Model(&w).Update(balanceField, newBalance)
    return tx.Create(&ManagerWalletTransaction{
        ManagerWalletID:   w.ID,
        AmountPaisa:       amount,
        BalanceAfterPaisa: newBalance,
        // ... type, reference, description
    }).Error
}

func Withdraw(tx *gorm.DB, walletID uuid.UUID, amount int64, ...) error {
    var w ManagerWallet
    tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&w, walletID)
    if w.AvailableBalancePaisa < amount {
        return ErrInsufficientBalance
    }
    newBalance := w.AvailableBalancePaisa - amount
    tx.Model(&w).Update("available_balance_paisa", newBalance)
    return tx.Create(&ManagerWalletTransaction{
        AmountPaisa:       -amount,
        BalanceAfterPaisa: newBalance,
        // ...
    }).Error
}
```

Rule: every wallet mutation = `SELECT FOR UPDATE` + `UPDATE wallet` + `INSERT transaction` — always inside caller's transaction, never standalone.

---

## Refund Flow

```
OUTSIDE TRANSACTION:
→ POST to SSLCommerz refund API  ← 3rd party

SINGLE DB TRANSACTION:
→ SELECT booking_settlement FOR UPDATE → assert status = settled
→ if settled_at > NOW() - hold_days:
    Withdraw(tx, manager_wallet.pending_balance, owner_net_payout)
  else if manager has sufficient available_balance:
    Withdraw(tx, manager_wallet.available_balance, owner_net_payout)
  else:
    INSERT manager_receivables (offset future credits)
→ Withdraw(tx, platform_wallet, turfinn_revenue)
→ Credit player wallet (existing Deposit)
→ UPDATE booking_settlement.status = refunded
→ INSERT refunds row (status=completed)
COMMIT
```

---

## Payout Flow

```
POST /api/v1/manager/payouts
Pre-checks (before transaction):
→ manager KYC status = approved
→ payout_method.is_verified = true
→ amount >= payout_min_threshold
→ amount <= available_balance
→ no pending/approved/processing payout exists

SINGLE DB TRANSACTION:
→ Withdraw(tx, manager_wallet.available, amount, 'payout_hold')
→ INSERT payout_request (status: pending)

Admin approve → UPDATE status=approved
Admin process → UPDATE status=processing
Admin complete:
  SINGLE DB TRANSACTION:
  → Withdraw(tx, platform_wallet, amount, 'payout_funded')
  → UPDATE payout_request status=completed, transfer_reference

Admin reject:
  SINGLE DB TRANSACTION:
  → Deposit(tx, manager_wallet.available, amount, 'payout_hold_release')
  → UPDATE payout_request status=rejected
```

---

## Hold Graduation (nightly job, 02:00)

```sql
-- One transaction per manager, not per booking row.
-- COALESCE picks the per-manager config if it exists, falls back to the global default (manager_id IS NULL).
UPDATE manager_wallets mw
SET
    available_balance_paisa = available_balance_paisa + sub.total,
    pending_balance_paisa   = pending_balance_paisa   - sub.total
FROM (
    SELECT bs.manager_id, SUM(btl.owner_net_payout_paisa) AS total
    FROM booking_settlements bs
    JOIN booking_tax_lines btl ON btl.booking_settlement_id = bs.id
    JOIN partner_fee_configs pfc ON pfc.manager_id = bs.manager_id
                                 OR (pfc.manager_id IS NULL AND NOT EXISTS (
                                       SELECT 1 FROM partner_fee_configs
                                       WHERE manager_id = bs.manager_id))
    WHERE bs.graduated = false
      AND bs.status = 'settled'
      AND bs.settled_at <= NOW() - (pfc.payout_hold_days || ' days')::INTERVAL
    GROUP BY bs.manager_id
) sub
WHERE mw.manager_id = sub.manager_id;

-- Bulk mark graduated (same hold logic, repeated for the UPDATE)
UPDATE booking_settlements bs SET graduated = true
FROM (
    SELECT bs2.id
    FROM booking_settlements bs2
    JOIN partner_fee_configs pfc ON pfc.manager_id = bs2.manager_id
                                 OR (pfc.manager_id IS NULL AND NOT EXISTS (
                                       SELECT 1 FROM partner_fee_configs
                                       WHERE manager_id = bs2.manager_id))
    WHERE bs2.graduated = false
      AND bs2.status = 'settled'
      AND bs2.settled_at <= NOW() - (pfc.payout_hold_days || ' days')::INTERVAL
) eligible
WHERE bs.id = eligible.id;
```

---

## API Endpoints

### Player
```
POST /api/v1/bookings/:id/pay          → initiate SSLCommerz payment
POST /api/v1/payment/success           → settlement callback
POST /api/v1/payment/ipn               → IPN fallback
POST /api/v1/payment/fail              → failed callback
POST /api/v1/payment/cancel            → cancelled callback
```

### Manager
```
GET  /api/v1/manager/wallet                           → balance summary
GET  /api/v1/manager/wallet/transactions              → paginated tx history
GET  /api/v1/manager/financials/settlements           → per-booking split breakdown
GET  /api/v1/manager/financials/fee-config            → their specific fee rates
GET  /api/v1/manager/financials/analytics             → revenue chart data
POST /api/v1/manager/payout-methods                   → add bkash/bank
GET  /api/v1/manager/payout-methods                   → list methods
DELETE /api/v1/manager/payout-methods/:id             → remove method
POST /api/v1/manager/payouts                          → request payout
GET  /api/v1/manager/payouts                          → payout history
GET  /api/v1/manager/tax/wht-certificates             → WHT certs per month
GET  /api/v1/manager/tax/summary                      → annual tax summary
```

### Admin
```
GET  /api/v1/admin/payouts                            → all payout requests
PUT  /api/v1/admin/payouts/:id/approve
PUT  /api/v1/admin/payouts/:id/process
PUT  /api/v1/admin/payouts/:id/complete               → body: { transfer_reference }
PUT  /api/v1/admin/payouts/:id/reject                 → body: { rejection_reason }
GET  /api/v1/admin/fee-configs                        → global + per-partner configs
POST /api/v1/admin/fee-configs                        → create override
PUT  /api/v1/admin/fee-configs/:id                    → update
GET  /api/v1/admin/gateway-fee-rates                  → card type rates
PUT  /api/v1/admin/gateway-fee-rates/:card_type       → update rate
POST /api/v1/admin/gateway-fee-reconciliations        → month-end reconciliation
```

### Super Admin
```
GET  /api/v1/super-admin/finance/platform-wallet      → balance + recent txs
GET  /api/v1/super-admin/finance/revenue-summary      → GMV, fee breakdown, net revenue
GET  /api/v1/super-admin/finance/manager-balances     → all manager wallet states
GET  /api/v1/super-admin/finance/receivables          → outstanding manager debts
GET  /api/v1/super-admin/tax/export                   → CSV export (VAT or TDS) by period
```

---

## What is NOT in scope

- SSLCommerz refund API integration (call structure is defined; SDK wiring is deferred)
- bKash/bank transfer automation (manual transfer + reference recording)
- NBR e-filing integration (accountant uses CSV export)
- Nagad/Rocket payout methods (structure supports it, not seeded)
- AML threshold auto-reporting (manual for now)
