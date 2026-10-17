package service

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
	"gorm.io/gorm"
)

// SplitResult holds the result of splitting a booking payment between all parties.
// All amounts are in paisa (1 BDT = 100 paisa).
type SplitResult struct {
	TotalPaidPaisa   int64
	OwnerPayoutPaisa int64
	// TurfinnRevenuePaisa is Turfinn's full commission. VAT and WHT obligations on this
	// amount are tracked in BookingTaxLine records but do not reduce the bucket split.
	TurfinnRevenuePaisa int64
	GatewayFeePaisa     int64
	VATAmountPaisa      int64
	WHTAmountPaisa      int64
}

// roundBps applies a basis-points rate to an amount using integer arithmetic.
// +5000 before dividing by 10000 provides rounding at the 0.5 boundary.
func roundBps(amount int64, bps int) int64 {
	return (amount*int64(bps) + 5000) / 10000
}

// ComputeSplit is a pure function that splits bookingAmountPaisa among all parties
// according to the supplied fee and tax configuration. It uses only integer
// arithmetic — no floating-point is involved at any stage.
//
// Algorithm:
//  1. gatewayFee    = roundBps(gross, gfr.FeeBps)
//  2. netAfterGW    = gross − gatewayFee
//  3. commission    = roundBps(netAfterGW, cfg.CommissionBps)
//  4. vatAmount     = roundBps(commission, vatRate.RateBps)   [sub-ledger only]
//  5. whtAmount     = roundBps(commission, whtRate.RateBps)   [sub-ledger only]
//  6. turfinnRev    = commission
//  7. ownerPayout   = gross − gatewayFee − commission
//  8. Invariant:    ownerPayout + turfinnRev + gatewayFee == gross  (panic if not)
//
// VAT and WHT are sub-ledger obligations inside Turfinn's commission bucket.
// They are written to booking_tax_lines for accounting but do not affect the
// three-bucket split: ownerPayout + turfinnRevenue + gatewayFee == gross always.
func ComputeSplit(
	bookingAmountPaisa int64,
	cfg *entity.PartnerFeeConfig,
	gfr *entity.GatewayFeeRate,
	vatRate *entity.TaxRate,
	whtRate *entity.TaxRate,
) SplitResult {
	gatewayFeePaisa := roundBps(bookingAmountPaisa, gfr.FeeBps)
	netAfterGateway := bookingAmountPaisa - gatewayFeePaisa

	turfinnCommissionPaisa := roundBps(netAfterGateway, cfg.CommissionBps)
	vatAmountPaisa := roundBps(turfinnCommissionPaisa, vatRate.RateBps)
	whtAmountPaisa := roundBps(turfinnCommissionPaisa, whtRate.RateBps)

	// Turfinn's revenue is the full commission. VAT and WHT are sub-ledger obligations
	// tracked in booking_tax_lines and do not affect the three-bucket split.
	turfinnRevenuePaisa := turfinnCommissionPaisa
	ownerPayoutPaisa := bookingAmountPaisa - gatewayFeePaisa - turfinnCommissionPaisa

	// Invariant: the three output buckets must reconstitute the gross payment.
	// A violation is a programming error (wrong formula), not a runtime error.
	if ownerPayoutPaisa+turfinnRevenuePaisa+gatewayFeePaisa != bookingAmountPaisa {
		panic(fmt.Sprintf(
			"settlement invariant violated: ownerPayout(%d) + turfinnRevenue(%d) + gatewayFee(%d) = %d != bookingAmount(%d)",
			ownerPayoutPaisa, turfinnRevenuePaisa, gatewayFeePaisa,
			ownerPayoutPaisa+turfinnRevenuePaisa+gatewayFeePaisa,
			bookingAmountPaisa,
		))
	}

	return SplitResult{
		TotalPaidPaisa:      bookingAmountPaisa,
		OwnerPayoutPaisa:    ownerPayoutPaisa,
		TurfinnRevenuePaisa: turfinnRevenuePaisa,
		GatewayFeePaisa:     gatewayFeePaisa,
		VATAmountPaisa:      vatAmountPaisa,
		WHTAmountPaisa:      whtAmountPaisa,
	}
}

// SettlementService orchestrates the full settlement flow for a confirmed payment:
// it computes the split, writes the immutable settlement and tax-line records, and
// credits the appropriate ledger wallets — all within a caller-owned transaction.
type SettlementService struct {
	db         *gorm.DB
	feeService *FeeService
	taxService *TaxService
	walletSvc  *LedgerWalletService
}

// NewSettlementService constructs a SettlementService with its dependencies.
func NewSettlementService(
	db *gorm.DB,
	feeService *FeeService,
	taxService *TaxService,
	walletSvc *LedgerWalletService,
) *SettlementService {
	return &SettlementService{
		db:         db,
		feeService: feeService,
		taxService: taxService,
		walletSvc:  walletSvc,
	}
}

// Settle runs the full settlement pipeline for a successful PaymentOrder.
// It MUST be called inside a caller-owned database transaction (tx).
//
// Steps:
//  1. Read the booking to obtain the pitch ID.
//  2. Read the pitch to obtain the manager's user ID (Pitch.OwnerID).
//  3. Look up fee config, gateway rate, VAT and WHT rates.
//  4. Compute the split.
//  5. Insert a BookingSettlement record.
//  6. Insert two BookingTaxLine records (VAT and WHT).
//  7. Get-or-create the manager's ledger wallet.
//  8. Credit manager pending balance with ownerPayoutPaisa.
//  9. Credit platform wallet with turfinnRevenuePaisa.
func (s *SettlementService) Settle(ctx context.Context, tx *gorm.DB, paymentOrder *entity.PaymentOrder, cardType string) error {
	// Step 1: Read the booking.
	var booking entity.Booking
	if err := tx.WithContext(ctx).First(&booking, "id = ?", paymentOrder.BookingID).Error; err != nil {
		return fmt.Errorf("settlement: read booking %s: %w", paymentOrder.BookingID, err)
	}

	// Step 2: Read the pitch to get the manager (owner) ID.
	var pitch entity.Pitch
	if err := tx.WithContext(ctx).First(&pitch, "id = ?", booking.PitchID).Error; err != nil {
		return fmt.Errorf("settlement: read pitch %s: %w", booking.PitchID, err)
	}
	managerID := pitch.OwnerID

	// Step 3a: Fee config for this manager (falls back to global default).
	cfg, err := s.feeService.GetConfig(ctx, managerID)
	if err != nil {
		return fmt.Errorf("settlement: get fee config for manager %s: %w", managerID, err)
	}

	// Step 3b: Gateway fee rate for the card type used.
	gfr, err := s.feeService.GetGatewayRate(ctx, cardType)
	if err != nil {
		return fmt.Errorf("settlement: get gateway rate for card type %q: %w", cardType, err)
	}

	// Step 3c: VAT rate.
	vatRate, err := s.taxService.GetRate(ctx, "vat")
	if err != nil {
		return fmt.Errorf("settlement: get vat rate: %w", err)
	}

	// Step 3d: WHT rate.
	whtRate, err := s.taxService.GetRate(ctx, "wht")
	if err != nil {
		return fmt.Errorf("settlement: get wht rate: %w", err)
	}

	// Step 4: Compute the split (pure, panics on invariant violation).
	split := ComputeSplit(paymentOrder.AmountPaisa, cfg, gfr, vatRate, whtRate)

	// Step 5: Insert the immutable settlement record.
	now := time.Now()
	settlement := entity.BookingSettlement{
		PaymentOrderID:      paymentOrder.ID,
		BookingID:           paymentOrder.BookingID,
		TotalPaidPaisa:      split.TotalPaidPaisa,
		OwnerPayoutPaisa:    split.OwnerPayoutPaisa,
		TurfinnRevenuePaisa: split.TurfinnRevenuePaisa,
		GatewayFeePaisa:     split.GatewayFeePaisa,
		HoldDays:            cfg.HoldDays,
		SettledAt:           &now,
	}
	if err := tx.WithContext(ctx).Create(&settlement).Error; err != nil {
		return fmt.Errorf("settlement: insert booking_settlement: %w", err)
	}

	// Step 6: Insert VAT and WHT tax lines.
	vatLine := entity.BookingTaxLine{
		SettlementID: settlement.ID,
		TaxType:      "vat",
		RateBps:      vatRate.RateBps,
		AmountPaisa:  split.VATAmountPaisa,
	}
	if err := tx.WithContext(ctx).Create(&vatLine).Error; err != nil {
		return fmt.Errorf("settlement: insert vat tax line: %w", err)
	}

	whtLine := entity.BookingTaxLine{
		SettlementID: settlement.ID,
		TaxType:      "wht",
		RateBps:      whtRate.RateBps,
		AmountPaisa:  split.WHTAmountPaisa,
	}
	if err := tx.WithContext(ctx).Create(&whtLine).Error; err != nil {
		return fmt.Errorf("settlement: insert wht tax line: %w", err)
	}

	// Step 7: Get or create the manager's ledger wallet (SELECT FOR UPDATE inside tx).
	wallet, err := s.walletSvc.GetOrCreateManagerWallet(ctx, tx, managerID)
	if err != nil {
		return fmt.Errorf("settlement: get or create manager wallet for manager %s: %w", managerID, err)
	}

	// Step 8: Credit manager pending balance — funds are held until hold_days expire.
	if split.OwnerPayoutPaisa > 0 {
		if err := s.walletSvc.DepositManagerPending(
			ctx, tx, wallet.ID, split.OwnerPayoutPaisa,
			"settlement", "booking_settlement", uuidPtr(settlement.ID), "booking payout",
		); err != nil {
			return fmt.Errorf("settlement: deposit manager pending: %w", err)
		}
	}

	// Step 9: Credit Turfinn's platform wallet with its net revenue.
	if split.TurfinnRevenuePaisa > 0 {
		if err := s.walletSvc.DepositPlatform(
			ctx, tx, split.TurfinnRevenuePaisa,
			"settlement", "booking_settlement", uuidPtr(settlement.ID), "turfinn revenue",
		); err != nil {
			return fmt.Errorf("settlement: deposit platform: %w", err)
		}
	}

	return nil
}

// uuidPtr is a convenience helper that returns a pointer to a uuid.UUID value.
func uuidPtr(id uuid.UUID) *uuid.UUID {
	return &id
}
