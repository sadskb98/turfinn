package service

import (
	"context"
	"errors"
	"fmt"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"github.com/turfinn/backend/internal/infrastructure/sslcommerz"
	"github.com/turfinn/backend/internal/interfaces/dto"
	"gorm.io/gorm"
)

// Sentinel errors returned by InitiatePayment for clean handler routing.
var (
	ErrBookingNotFound = errors.New("booking not found")
	ErrNotBookingOwner = errors.New("booking does not belong to user")
	ErrNotPayable      = errors.New("booking status is not payable")
	ErrAlreadyPaid     = errors.New("booking already has a successful payment")
)

// PaymentService orchestrates SSLCommerz payment initiation and callback handling.
type PaymentService struct {
	db          *gorm.DB
	userRepo    domain.UserRepository
	sslcz       *sslcommerz.Client
	settleSvc   *SettlementService
	storePasswd string
	appBaseURL  string
}

// NewPaymentService constructs a PaymentService.
//
//   - db          — GORM DB handle (used outside transactions)
//   - userRepo    — UserRepository for loading customer details
//   - sslcz       — SSLCommerz HTTP client
//   - settleSvc   — SettlementService (runs inside a transaction on success)
//   - storePasswd — SSLCZ_STORE_PASSWD (used for HMAC verification)
//   - appBaseURL  — e.g. https://api.turfinn.com (no trailing slash)
func NewPaymentService(
	db *gorm.DB,
	userRepo domain.UserRepository,
	sslcz *sslcommerz.Client,
	settleSvc *SettlementService,
	storePasswd, appBaseURL string,
) *PaymentService {
	return &PaymentService{
		db:          db,
		userRepo:    userRepo,
		sslcz:       sslcz,
		settleSvc:   settleSvc,
		storePasswd: storePasswd,
		appBaseURL:  appBaseURL,
	}
}

// InitiatePayment creates a PaymentOrder and returns the SSLCommerz gateway URL.
//
// The booking must belong to userID and be in "pending" or "confirmed" status.
// An existing successful PaymentOrder for the same booking is rejected to prevent
// double-charging.
func (s *PaymentService) InitiatePayment(ctx context.Context, bookingID, userID uuid.UUID) (string, error) {
	// Step 1: Load the booking and verify ownership + status.
	var booking entity.Booking
	if err := s.db.WithContext(ctx).First(&booking, "id = ?", bookingID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return "", ErrBookingNotFound
		}
		return "", fmt.Errorf("payment initiate: read booking: %w", err)
	}
	if booking.UserID != userID {
		return "", ErrNotBookingOwner
	}
	if booking.Status != entity.BookingPending && booking.Status != entity.BookingConfirmed {
		return "", ErrNotPayable
	}

	// Step 1b: Load the user for real customer details.
	user, err := s.userRepo.FindByID(ctx, userID)
	if err != nil {
		return "", fmt.Errorf("payment initiate: load user: %w", err)
	}

	// Step 2: Reject if a successful payment already exists for this booking.
	var existingCount int64
	if err := s.db.WithContext(ctx).
		Model(&entity.PaymentOrder{}).
		Where("booking_id = ? AND status = ?", bookingID, entity.PaymentStatusSuccess).
		Count(&existingCount).Error; err != nil {
		return "", fmt.Errorf("payment initiate: check existing payment: %w", err)
	}
	if existingCount > 0 {
		return "", ErrAlreadyPaid
	}

	// Step 3: Determine the amount the gateway should charge. partial_online
	// charges only the platform commission (rest is cash at venue);
	// full_online charges the whole booking. cash_due_paisa is set on the
	// booking row at create-time and stays fixed regardless of currency
	// rounding here.
	totalPaisa := int64(math.Round(booking.TotalCost * 100))
	amountPaisa := totalPaisa
	if booking.PaymentMode == entity.PaymentModePartialOnline {
		amountPaisa = totalPaisa - booking.CashDuePaisa
		if amountPaisa <= 0 {
			return "", fmt.Errorf("partial-payment online amount is zero — booking misconfigured")
		}
	}
	amountTaka := fmt.Sprintf("%.2f", float64(amountPaisa)/100.0)

	// Step 4: Generate transaction ID.
	tranID := fmt.Sprintf("TRX-%s", bookingID.String())

	// Step 5: Insert pending PaymentOrder (outside any transaction — idempotent via unique tran_id).
	order := entity.PaymentOrder{
		BookingID:   bookingID,
		UserID:      userID,
		AmountPaisa: amountPaisa,
		Currency:    "BDT",
		Status:      entity.PaymentStatusPending,
		TranID:      strPtr(tranID),
	}
	if err := s.db.WithContext(ctx).Create(&order).Error; err != nil {
		return "", fmt.Errorf("payment initiate: insert payment_order: %w", err)
	}

	// Resolve customer name and phone from the loaded user, with safe fallbacks.
	customerName := "Customer"
	if user.Name != "" {
		customerName = user.Name
	}
	customerPhone := ""
	if user.Phone != nil && *user.Phone != "" {
		customerPhone = *user.Phone
	}

	// Step 6: Call SSLCommerz to open the gateway session.
	// On failure, best-effort delete the pending order so it does not accumulate as noise.
	gatewayURL, err := s.sslcz.Initiate(ctx, sslcommerz.InitiateRequest{
		TranID:          tranID,
		TotalAmount:     amountTaka,
		Currency:        "BDT",
		ProductName:     "Futsal Booking",
		ProductCategory: "sports",
		CustomerName:    customerName,
		CustomerPhone:   customerPhone,
		SuccessURL:      s.appBaseURL + "/api/v1/payment/success",
		FailURL:         s.appBaseURL + "/api/v1/payment/fail",
		CancelURL:       s.appBaseURL + "/api/v1/payment/cancel",
		IPNURL:          s.appBaseURL + "/api/v1/payment/ipn",
	})
	if err != nil {
		// Compensating delete: clean up the orphaned pending order.
		_ = s.db.WithContext(ctx).Delete(&order).Error
		return "", fmt.Errorf("payment initiate: sslcommerz initiate: %w", err)
	}

	return gatewayURL, nil
}

// HandleCallback processes SSLCommerz success and IPN callbacks.
// It is idempotent: if the payment order is already marked "success" it returns nil.
func (s *PaymentService) HandleCallback(ctx context.Context, params dto.SSLCallbackParams) error {
	// Step 1: Find the payment order by tran_id.
	var order entity.PaymentOrder
	if err := s.db.WithContext(ctx).First(&order, "tran_id = ?", params.TranID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return fmt.Errorf("payment callback: payment_order not found for tran_id %q", params.TranID)
		}
		return fmt.Errorf("payment callback: read payment_order: %w", err)
	}

	// Step 2: Idempotency — already processed.
	if order.Status == entity.PaymentStatusSuccess {
		return nil
	}

	// Step 3: Verify HMAC signature.
	if !sslcommerz.VerifySign(paramsAsMap(params), s.storePasswd) {
		return fmt.Errorf("payment callback: HMAC verification failed for tran_id %q", params.TranID)
	}

	// Step 4: Validate with SSLCommerz API.
	validateResp, err := s.sslcz.Validate(ctx, params.ValID)
	if err != nil {
		return fmt.Errorf("payment callback: sslcommerz validate: %w", err)
	}
	if validateResp.Status != "VALID" {
		return fmt.Errorf("payment callback: validation status %q for tran_id %q", validateResp.Status, params.TranID)
	}

	// Steps 5+6: Settle and mark success atomically — both inside the same transaction
	// so that a crash between steps cannot leave ledger committed but order still "pending"
	// (which would cause a double-settle on the next IPN retry).
	if err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := s.settleSvc.Settle(ctx, tx, &order, params.CardType); err != nil {
			return err
		}
		now := time.Now()
		valID := params.ValID
		return tx.WithContext(ctx).Model(&order).Updates(map[string]any{
			"status":     entity.PaymentStatusSuccess,
			"val_id":     &valID,
			"updated_at": now,
		}).Error
	}); err != nil {
		return fmt.Errorf("payment callback: settle+confirm: %w", err)
	}

	return nil
}

// HandleFail marks a payment order as failed and cancels the booking so the slot
// is freed immediately for other users.
func (s *PaymentService) HandleFail(ctx context.Context, tranID string) error {
	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var order entity.PaymentOrder
		if err := tx.Where("tran_id = ? AND status NOT IN ?", tranID,
			[]string{entity.PaymentStatusSuccess}).First(&order).Error; err != nil {
			return nil // already success or not found — ignore
		}
		if err := tx.Model(&order).Updates(map[string]any{
			"status": entity.PaymentStatusFailed, "updated_at": time.Now(),
		}).Error; err != nil {
			return fmt.Errorf("payment fail: update payment_order: %w", err)
		}
		return tx.Model(&entity.Booking{}).Where("id = ? AND status = ?",
			order.BookingID, entity.BookingPending).
			Update("status", entity.BookingCancelled).Error
	})
}

// HandleCancel marks a payment order as cancelled and cancels the booking so the
// slot is freed immediately for other users.
func (s *PaymentService) HandleCancel(ctx context.Context, tranID string) error {
	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var order entity.PaymentOrder
		if err := tx.Where("tran_id = ? AND status NOT IN ?", tranID,
			[]string{entity.PaymentStatusSuccess}).First(&order).Error; err != nil {
			return nil
		}
		if err := tx.Model(&order).Updates(map[string]any{
			"status": entity.PaymentStatusCancelled, "updated_at": time.Now(),
		}).Error; err != nil {
			return fmt.Errorf("payment cancel: update payment_order: %w", err)
		}
		return tx.Model(&entity.Booking{}).Where("id = ? AND status = ?",
			order.BookingID, entity.BookingPending).
			Update("status", entity.BookingCancelled).Error
	})
}

// paramsAsMap converts SSLCallbackParams to map[string]string for VerifySign.
func paramsAsMap(p dto.SSLCallbackParams) map[string]string {
	return map[string]string{
		"tran_id":      p.TranID,
		"val_id":       p.ValID,
		"amount":       p.Amount,
		"card_type":    p.CardType,
		"status":       p.Status,
		"verify_sign":  p.VerifySign,
		"verify_key":   p.VerifyKey,
		"store_amount": p.StoreAmount,
		"currency":     p.Currency,
		"tran_date":    p.TranDate,
		"bank_tran_id": p.BankTranID,
	}
}

