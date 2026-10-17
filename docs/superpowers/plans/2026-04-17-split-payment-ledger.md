# Split-Payment Ledger & SSLCommerz Integration — Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans or superpowers:subagent-driven-development to implement phase by phase. Each phase is independently committable and testable.

**Goal:** Wire SSLCommerz into the booking flow and implement a full split-payment ledger — manager wallets, platform wallet, fee config, settlement, tax records, payouts, and hold graduation.

**Architecture:** Payment callback runs a single DB transaction that splits the amount three ways, writes immutable settlement + tax line records, and updates both wallets. Amounts in paisa (int64), percentages in basis points (int). Flutter manager financials UI is a separate plan.

**Tech Stack:** Go + GORM + Echo + Asynq + SSLCommerz HTTP API + PostgreSQL

**Flutter scope:** Out of scope for this plan. Manager financials UI is a follow-on plan.

---

## Phase 1 — Foundation (Migration + Entities)

**Files to create:**
- `backend/migrations/022_split_payment_ledger.sql`
- `backend/internal/domain/entity/payment.go` — `PaymentOrder`, `BookingSettlement`, `BookingTaxLine`
- `backend/internal/domain/entity/ledger_wallet.go` — `ManagerWallet`, `ManagerWalletTransaction`, `PlatformWallet`, `PlatformWalletTransaction`
- `backend/internal/domain/entity/fee_config.go` — `PartnerFeeConfig`, `GatewayFeeRate`, `TaxRate`
- `backend/internal/domain/entity/payout.go` — `PayoutMethod`, `PayoutRequest`, `Refund`, `ManagerReceivable`, `GatewayFeeReconciliation`

**Tasks:**
- [ ] Write `022_split_payment_ledger.sql` — all 15 tables from spec with `IF NOT EXISTS` guards and seed rows (global fee config, gateway rates, tax rates, platform wallet singleton)
- [ ] Write `payment.go` entities — GORM tags, status `CHECK` constraints as Go constants
- [ ] Write `ledger_wallet.go` entities — two balance columns on `ManagerWallet` (`available_balance_paisa`, `pending_balance_paisa`)
- [ ] Write `fee_config.go` entities — `PartnerFeeConfig` with `manager_id` nullable (NULL = global default)
- [ ] Write `payout.go` entities — `PayoutMethod`, `PayoutRequest`, `Refund`, `ManagerReceivable`
- [ ] Run `go build ./...` — no compile errors
- [ ] Commit: `feat: add split-payment ledger migration and domain entities`

---

## Phase 2 — Infrastructure: SSLCommerz Client

**Files to create:**
- `backend/internal/infrastructure/sslcommerz/client.go` — `Initiate(req InitiateRequest) (gatewayURL string, err error)` + `Validate(valID string) (ValidateResponse, error)`
- `backend/internal/infrastructure/sslcommerz/hmac.go` — `VerifySign(params map[string]string, storePasswd string) bool`
- `backend/internal/infrastructure/sslcommerz/hmac_test.go`

**Env vars required:** `SSLCZ_STORE_ID`, `SSLCZ_STORE_PASSWD`, `SSLCZ_BASE_URL` (sandbox: `https://sandbox.sslcommerz.com`), `APP_BASE_URL`

**Tasks:**
- [ ] Write `hmac.go` — sort `verify_key` fields alphabetically, concat values, append `MD5(store_passwd)`, compute `MD5` of result, compare with `verify_sign`
- [ ] Write `hmac_test.go` — table-driven tests with known input/output pairs
- [ ] Write `client.go` — `Initiate` posts to `/gwprocess/v4/api.php`, returns `GatewayPageURL`; `Validate` calls `/validator/api/validationserverAPI.php?val_id=...`
- [ ] Run `go test ./backend/internal/infrastructure/sslcommerz/...`
- [ ] Commit: `feat: add SSLCommerz client and HMAC verification`

---

## Phase 3 — Core Services (Fee, Tax, Ledger Wallets)

**Files to create:**
- `backend/internal/application/service/fee_service.go` — `GetConfig(ctx, managerID) (*PartnerFeeConfig, error)` (manager row or global fallback); `GetGatewayRate(ctx, cardType) (*GatewayFeeRate, error)`
- `backend/internal/application/service/tax_service.go` — `GetRate(ctx, taxType) (*TaxRate, error)` (active row: `valid_to IS NULL`)
- `backend/internal/application/service/ledger_wallet_service.go` — `DepositManager(tx, walletID, amount, txType, refType, refID, desc)`, `WithdrawManager(tx, walletID, amount, ...)`, `DepositPlatform(tx, amount, txType, ...)`, `WithdrawPlatform(tx, amount, ...)` — all take `*gorm.DB` so caller owns the transaction; each does `SELECT FOR UPDATE` → update balance → insert tx record

**Tasks:**
- [ ] Write `fee_service.go` — `NewFeeService(db)`, both lookup methods with caching-free DB reads (simple for now)
- [ ] Write `tax_service.go` — `NewTaxService(db)`, `GetRate` queries `WHERE tax_type = ? AND valid_to IS NULL ORDER BY valid_from DESC LIMIT 1`
- [ ] Write `ledger_wallet_service.go` — `DepositManager` and `WithdrawManager` use `clause.Locking{Strength: "UPDATE"}` on `ManagerWallet`; `DepositPlatform` / `WithdrawPlatform` lock the singleton by `name = 'turfinn_main'`; `WithdrawManager` returns `ErrInsufficientBalance` if available < amount
- [ ] Run `go build ./...`
- [ ] Commit: `feat: add fee, tax and ledger wallet services`

---

## Phase 4 — Settlement Service

**Files to create:**
- `backend/internal/application/service/settlement_service.go` — `ComputeSplit(bookingAmountPaisa, cfg, gfr, vatRate, whtRate) SplitResult` + `Settle(ctx, tx, paymentOrder, cardType) error`
- `backend/internal/application/service/settlement_service_test.go`

**Key invariant (assert before commit, rollback if fails):**
```
ownerPayoutPaisa + turfinnRevenuePaisa + gatewayFeePaisa == totalPaidPaisa
```

**Tasks:**
- [ ] Write `ComputeSplit` — pure function, all integer arithmetic with banker's rounding `(x * bps + 5000) / 10000`; returns `SplitResult` struct with all computed fields
- [ ] Write `settlement_service_test.go` — table-driven tests covering: standard split, zero commission override, rounding edge cases, invariant assertion
- [ ] Write `Settle(ctx, tx, paymentOrder, cardType)` — runs inside caller's transaction: lookup rates → compute split → INSERT `booking_settlement` → INSERT `booking_tax_lines` → `DepositManager(pending)` → `DepositPlatform` → assert invariant
- [ ] Run `go test ./backend/internal/application/service/... -run TestComputeSplit`
- [ ] Commit: `feat: add settlement service with split formula and tests`

---

## Phase 5 — Payment Service + Handler

**Files to create:**
- `backend/internal/application/service/payment_service.go` — `InitiatePayment`, `HandleSuccess`, `HandleIPN`, `HandleFail`, `HandleCancel`
- `backend/internal/interfaces/dto/payment_dto.go`
- `backend/internal/interfaces/http/handler/payment_handler.go`

**Routes to add in `router.go`:**
```
bookings.POST("/:id/pay", paymentH.Initiate)          // auth required
v1.POST("/payment/success", paymentH.Success)          // no auth (SSLCommerz callback)
v1.POST("/payment/ipn",     paymentH.IPN)              // no auth
v1.POST("/payment/fail",    paymentH.Fail)             // no auth
v1.POST("/payment/cancel",  paymentH.Cancel)           // no auth
```

**Tasks:**
- [ ] Write `payment_dto.go` — `InitiateResponse{RedirectURL string}`, SSLCommerz callback form fields struct
- [ ] Write `InitiatePayment(ctx, bookingID, userID)` — get fee config → calculate total → INSERT `payment_order` (pending) → call `sslcommerz.Initiate` outside any DB tx → return gateway URL
- [ ] Write `HandleSuccess` / `HandleIPN` (identical logic) — pre-check idempotency → verify HMAC → call SSLCommerz Validate API → `db.Transaction(Settle(...))` → return 200
- [ ] Write `HandleFail` / `HandleCancel` — single UPDATE `payment_order.status`, no wallet writes
- [ ] Write `payment_handler.go` — Echo handler, binds form params for callbacks, delegates to service
- [ ] Manual smoke test: run backend locally, initiate a test payment, verify `payment_orders` row created
- [ ] Commit: `feat: add SSLCommerz payment initiation and settlement callbacks`

---

## Phase 6 — Payout System

**Files to create:**
- `backend/internal/application/service/payout_service.go` — `AddPayoutMethod`, `ListPayoutMethods`, `DeletePayoutMethod`, `RequestPayout`, `ListPayouts`
- `backend/internal/interfaces/dto/payout_dto.go`
- `backend/internal/interfaces/http/handler/payout_handler.go`

**Routes to add (`/manager` group, auth + RequireManager):**
```
POST   /manager/payout-methods
GET    /manager/payout-methods
DELETE /manager/payout-methods/:id
POST   /manager/payouts
GET    /manager/payouts
```

**Pre-checks before `RequestPayout` transaction:**
- KYC status = approved (query `user_verifications`)
- `payout_method.is_verified = true`
- `amount >= payout_min_threshold`
- `amount <= available_balance`
- No `pending/approved/processing` payout exists for this manager

**Tasks:**
- [ ] Write `payout_service.go` — `RequestPayout` runs `Withdraw(available, amount, 'payout_hold')` + INSERT `payout_request` inside single tx; all pre-checks outside tx
- [ ] Write `payout_dto.go` + `payout_handler.go`
- [ ] Add routes to `router.go`
- [ ] Commit: `feat: add manager payout methods and payout request flow`

---

## Phase 7 — Admin Payout Management + Fee Config Endpoints

**Files to create:**
- `backend/internal/interfaces/http/handler/admin_finance_handler.go`

**Routes to add (`/admin` group, RequireRole admin):**
```
GET  /admin/payouts
PUT  /admin/payouts/:id/approve
PUT  /admin/payouts/:id/process
PUT  /admin/payouts/:id/complete    body: { transfer_reference }
PUT  /admin/payouts/:id/reject      body: { rejection_reason }
GET  /admin/fee-configs
POST /admin/fee-configs
PUT  /admin/fee-configs/:id
GET  /admin/gateway-fee-rates
PUT  /admin/gateway-fee-rates/:card_type
POST /admin/gateway-fee-reconciliations
```

**Tasks:**
- [ ] Write `admin_finance_handler.go` — payout state machine: `approve` → `process` → `complete` (writes `transfer_reference`) or `reject` (releases hold via `Deposit`); fee config CRUD; gateway rate update
- [ ] Add routes to `router.go`
- [ ] Commit: `feat: add admin payout management and fee config endpoints`

---

## Phase 8 — Manager Financials Endpoints

**Files to create:**
- `backend/internal/interfaces/http/handler/manager_finance_handler.go`
- `backend/internal/interfaces/dto/ledger_dto.go`

**Routes to add (`/manager` group):**
```
GET /manager/wallet
GET /manager/wallet/transactions
GET /manager/financials/settlements
GET /manager/financials/fee-config
GET /manager/financials/analytics
GET /manager/tax/wht-certificates
GET /manager/tax/summary
```

**Tasks:**
- [ ] Write `ledger_dto.go` — wallet balance response, settlement list item, WHT certificate response
- [ ] Write `manager_finance_handler.go` — wallet summary (available + pending), paginated tx history, paginated settlements with full split breakdown, fee config display, tax summary
- [ ] Add routes to `router.go`
- [ ] Commit: `feat: add manager wallet and financials endpoints`

---

## Phase 9 — Super Admin Finance Endpoints

**Files to modify/create:**
- Extend `backend/internal/interfaces/http/handler/superadmin_handler.go` or new `superadmin_finance_handler.go`

**Routes to add (`/super-admin` group):**
```
GET /super-admin/finance/platform-wallet
GET /super-admin/finance/revenue-summary
GET /super-admin/finance/manager-balances
GET /super-admin/finance/receivables
GET /super-admin/tax/export             query: ?type=vat|tds&from=YYYY-MM&to=YYYY-MM  → CSV
```

**Tasks:**
- [ ] Write platform wallet summary endpoint (balance + recent 20 txs)
- [ ] Write revenue summary (GMV, gross fees, gateway costs, net revenue — aggregate from `booking_settlements`)
- [ ] Write manager balances list (all `manager_wallets` joined with user name)
- [ ] Write receivables list (outstanding `manager_receivables`)
- [ ] Write CSV tax export — query `booking_tax_lines` for period, stream CSV with `Content-Disposition: attachment`
- [ ] Add routes to `router.go`
- [ ] Commit: `feat: add super admin finance and tax export endpoints`

---

## Phase 10 — Hold Graduation (Nightly Job)

**Files to create/modify:**
- `backend/internal/infrastructure/worker/hold_graduation_worker.go`
- Modify `backend/internal/application/service/tasks.go` — add `TypeHoldGraduation = "finance:hold_graduation"`
- Modify `backend/internal/infrastructure/worker/scheduler.go` — register `"0 2 * * *"` cron
- Modify `backend/internal/infrastructure/worker/worker.go` — register handler

**Tasks:**
- [ ] Add `TypeHoldGraduation` constant to `tasks.go`
- [ ] Write `hold_graduation_worker.go` — `Handle(*asynq.Task)`: runs the bulk UPDATE SQL from spec (graduate settlements where `settled_at <= NOW() - hold_days`, move pending → available, mark `graduated = true`); uses two separate queries in one transaction: update wallet balances + mark settlements graduated; logs count of graduated rows
- [ ] Register `"0 2 * * *"` cron in `NewScheduler()`
- [ ] Register `TypeHoldGraduation` handler in `RegisterHandlers()`
- [ ] Commit: `feat: add nightly hold graduation worker`

---

## Phase 11 — Wire Everything (main.go + router.go)

**Files to modify:**
- `backend/cmd/api/main.go`
- `backend/internal/interfaces/http/router.go`
- `docker-compose.yml` or `.env.example` — add SSLCommerz env vars

**Tasks:**
- [ ] Instantiate in `main.go`: `sslczClient`, `feeService`, `taxService`, `ledgerWalletSvc`, `settlementSvc`, `paymentSvc`, `payoutSvc`; pass to their handlers
- [ ] Add all new handlers to `NewRouter(...)` signature and register their routes
- [ ] Add `SSLCZ_STORE_ID`, `SSLCZ_STORE_PASSWD`, `SSLCZ_BASE_URL`, `APP_BASE_URL` to `.env.example` and `docker-compose.yml`
- [ ] Run `go build ./...` — clean compile
- [ ] Run `go test ./...` — all existing tests pass
- [ ] Commit: `feat: wire split-payment ledger into main.go and router`

---

## Out of Scope (follow-on plans)

| Item | Why deferred |
|---|---|
| SSLCommerz refund API call | Needs production credentials + sandbox testing |
| bKash/bank transfer automation | Manual transfer + reference recording for now |
| NBR e-filing | Accountant uses CSV export from Phase 9 |
| Flutter manager financials UI | Separate plan |

---

## Env Vars Summary

```env
SSLCZ_STORE_ID=your_store_id
SSLCZ_STORE_PASSWD=your_store_password
SSLCZ_BASE_URL=https://sandbox.sslcommerz.com
APP_BASE_URL=https://app.turfinn.com
```
