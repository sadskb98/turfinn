// Package service — booking_split_service.go implements the Split-Pay
// flow for group bookings.
//
// One captain creates a booking with N expected shares, pays their own
// share immediately, and shares a magic-link with the rest of the team.
// Each guest visits the link, claims one of the N share slots by phone
// number, pays via SSLCommerz, and once split_paid_count == split_share_count
// the booking transitions to confirmed (running the same side effects
// as a normal booking — ledger, settlement, SMS).
//
// If split_deadline_at (creation_time + 30min) elapses before the quorum
// hits, an asynq worker refunds every paid share via SSL Refund and
// cancels the booking.

package service

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/rs/zerolog/log"
	"gorm.io/gorm"

	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"github.com/turfinn/backend/internal/infrastructure/sslcommerz"
)

// SplitPayDeadline is how long a pending_split booking is held before
// the deadline worker refunds every paid share. Kept short so the slot
// stays bookable by other groups if the captain's friends ghost.
const SplitPayDeadline = 30 * time.Minute

// TypeSplitDeadline is the asynq task type for the deadline expiry
// worker (registered in scheduler.go / cmd/worker).
const TypeSplitDeadline = "booking:split_deadline"

type BookingSplitService struct {
	db          *gorm.DB
	bookingRepo domain.BookingRepository
	shareRepo   domain.BookingShareRepository
	pitchRepo   domain.PitchRepository
	userRepo    domain.UserRepository

	pricing *PricingService
	settle  *WeeklySettlementService
	ledger  *LedgerService

	sslcz       *sslcommerz.Client
	storePasswd string
	appBaseURL  string

	asynq *asynq.Client
}

func NewBookingSplitService(
	db *gorm.DB,
	bookingRepo domain.BookingRepository,
	shareRepo domain.BookingShareRepository,
	pitchRepo domain.PitchRepository,
	userRepo domain.UserRepository,
	sslcz *sslcommerz.Client,
	storePasswd, appBaseURL string,
) *BookingSplitService {
	return &BookingSplitService{
		db:          db,
		bookingRepo: bookingRepo,
		shareRepo:   shareRepo,
		pitchRepo:   pitchRepo,
		userRepo:    userRepo,
		pricing:     NewPricingService(db),
		settle:      NewWeeklySettlementService(db),
		ledger:      NewLedgerService(db),
		sslcz:       sslcz,
		storePasswd: storePasswd,
		appBaseURL:  appBaseURL,
	}
}

func (s *BookingSplitService) WithAsynq(client *asynq.Client) *BookingSplitService {
	s.asynq = client
	return s
}

// ── Initiate ─────────────────────────────────────────────────────────────

type InitiateSplitInput struct {
	CaptainID   uuid.UUID
	PitchID     uuid.UUID
	StartsAt    time.Time
	EndsAt      time.Time
	TotalShares int
	Notes       string
}

type InitiateSplitResult struct {
	BookingID  uuid.UUID
	Token      string
	DeadlineAt time.Time
	GatewayURL string // SSL URL for the captain to settle their own share
	PerShare   int64  // paisa per share (informational)
}

// InitiateSplit creates the pending_split booking, issues N share rows
// (share #1 pre-claimed for the captain), and immediately opens an SSL
// session for the captain to settle their own share. Returns the SSL
// gateway URL plus the magic-link token for the team WhatsApp blast.
func (s *BookingSplitService) InitiateSplit(ctx context.Context, in InitiateSplitInput) (*InitiateSplitResult, error) {
	if in.TotalShares < 2 {
		return nil, fmt.Errorf("split needs at least 2 shares")
	}
	if in.TotalShares > 30 {
		return nil, fmt.Errorf("split capped at 30 shares")
	}
	now := time.Now()
	if in.StartsAt.Before(now) || in.EndsAt.Before(in.StartsAt) {
		return nil, fmt.Errorf("invalid time window")
	}

	pitch, err := s.pitchRepo.FindByID(ctx, in.PitchID)
	if err != nil {
		return nil, fmt.Errorf("pitch not found")
	}
	if pitch.Plan == entity.PitchPlanERPOnly {
		return nil, fmt.Errorf("this pitch is on the ERP-only plan and not bookable through the app")
	}

	captain, err := s.userRepo.FindByID(ctx, in.CaptainID)
	if err != nil {
		return nil, fmt.Errorf("captain not found")
	}

	hours := in.EndsAt.Sub(in.StartsAt).Hours()
	totalTaka := hours * pitch.PricePerHour
	totalPaisa := int64(totalTaka * 100)
	perSharePaisa := totalPaisa / int64(in.TotalShares)
	// Distribute the rounding remainder onto share #1 so totals reconcile.
	remainder := totalPaisa - perSharePaisa*int64(in.TotalShares)

	token := generateToken()
	deadline := now.Add(SplitPayDeadline)

	booking := entity.NewBooking(in.PitchID, in.CaptainID, in.StartsAt, in.EndsAt, totalTaka)
	booking.Notes = in.Notes
	booking.Status = entity.BookingPendingSplit
	booking.PaymentMode = entity.PaymentModeFullOnline
	booking.SplitToken = &token
	booking.SplitDeadlineAt = &deadline
	booking.SplitShareCount = in.TotalShares
	booking.SplitPaidCount = 0

	// Build all shares up front. Share #1 absorbs the remainder so the
	// captain's amount may be a few paisa more than the others.
	shares := make([]*entity.BookingShare, 0, in.TotalShares)
	captainPhone := ""
	if captain.Phone != nil {
		captainPhone = *captain.Phone
	}
	for i := 1; i <= in.TotalShares; i++ {
		amt := perSharePaisa
		if i == 1 {
			amt += remainder
		}
		share := &entity.BookingShare{
			ID:          uuid.New(),
			BookingID:   booking.ID,
			ShareNo:     i,
			AmountPaisa: amt,
			Status:      entity.SharePending,
		}
		if i == 1 {
			cid := captain.ID
			share.PayerUserID = &cid
			if captainPhone != "" {
				p := captainPhone
				share.PayerPhone = &p
			}
		}
		shares = append(shares, share)
	}

	// Atomic conflict-check + booking insert + shares insert.
	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var conflicts int64
		if err := tx.Model(&entity.Booking{}).
			Where("pitch_id = ? AND status NOT IN ? AND starts_at < ? AND ends_at > ?",
				in.PitchID,
				[]entity.BookingStatus{entity.BookingCancelled},
				in.EndsAt, in.StartsAt).
			Set("gorm:query_option", "FOR UPDATE").
			Count(&conflicts).Error; err != nil {
			return fmt.Errorf("check availability: %w", err)
		}
		if conflicts > 0 {
			return fmt.Errorf("slot not available")
		}
		if err := tx.Create(booking).Error; err != nil {
			return fmt.Errorf("create booking: %w", err)
		}
		if err := tx.Create(shares).Error; err != nil {
			return fmt.Errorf("create shares: %w", err)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	// Schedule the deadline worker — fires at exactly split_deadline_at.
	if s.asynq != nil {
		payload := []byte(booking.ID.String())
		task := asynq.NewTask(TypeSplitDeadline, payload)
		_, _ = s.asynq.Enqueue(task,
			asynq.ProcessAt(deadline),
			asynq.Queue("default"),
			asynq.MaxRetry(3),
			asynq.Unique(SplitPayDeadline*2),
		)
	}

	// Open the captain's SSL session so they pay share #1 right away.
	captainShare := shares[0]
	gatewayURL, err := s.openShareGateway(ctx, booking, captainShare, captain.Name, captainPhone)
	if err != nil {
		// Roll back the booking — the captain never even got to the gateway.
		_ = s.db.WithContext(ctx).Delete(booking).Error
		return nil, fmt.Errorf("ssl initiate captain share: %w", err)
	}

	return &InitiateSplitResult{
		BookingID:  booking.ID,
		Token:      token,
		DeadlineAt: deadline,
		GatewayURL: gatewayURL,
		PerShare:   perSharePaisa,
	}, nil
}

// ── Public lookup ────────────────────────────────────────────────────────

type PublicSplitView struct {
	BookingID     uuid.UUID `json:"booking_id"`
	Token         string    `json:"token"`
	PitchName     string    `json:"pitch_name"`
	PitchCity     string    `json:"pitch_city"`
	StartsAt      time.Time `json:"starts_at"`
	EndsAt        time.Time `json:"ends_at"`
	CaptainName   string    `json:"captain_name"`
	TotalCostBDT  float64   `json:"total_cost_bdt"`
	PerShareBDT   float64   `json:"per_share_bdt"`
	ShareCount    int       `json:"share_count"`
	PaidCount     int       `json:"paid_count"`
	DeadlineAt    time.Time `json:"deadline_at"`
	HasOpenShare  bool      `json:"has_open_share"`
	BookingStatus string    `json:"booking_status"`
}

// GetByToken returns the public-safe view of a split booking. Only the
// captain's first name and the pitch metadata are exposed — never the
// captain's phone or any other player's identity.
func (s *BookingSplitService) GetByToken(ctx context.Context, token string) (*PublicSplitView, error) {
	var booking entity.Booking
	err := s.db.WithContext(ctx).
		Preload("Pitch").Preload("User").
		Where("split_token = ?", token).
		First(&booking).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, fmt.Errorf("split not found")
		}
		return nil, err
	}
	if booking.SplitDeadlineAt == nil {
		return nil, fmt.Errorf("not a split booking")
	}

	captainName := strings.SplitN(booking.User.Name, " ", 2)[0]
	if captainName == "" {
		captainName = "A friend"
	}
	perPaisa := int64(0)
	if booking.SplitShareCount > 0 {
		perPaisa = int64(booking.TotalCost*100) / int64(booking.SplitShareCount)
	}

	return &PublicSplitView{
		BookingID:     booking.ID,
		Token:         token,
		PitchName:     booking.Pitch.Name,
		PitchCity:     booking.Pitch.City,
		StartsAt:      booking.StartsAt,
		EndsAt:        booking.EndsAt,
		CaptainName:   captainName,
		TotalCostBDT:  booking.TotalCost,
		PerShareBDT:   float64(perPaisa) / 100.0,
		ShareCount:    booking.SplitShareCount,
		PaidCount:     booking.SplitPaidCount,
		DeadlineAt:    *booking.SplitDeadlineAt,
		HasOpenShare:  booking.SplitPaidCount < booking.SplitShareCount && booking.Status == entity.BookingPendingSplit,
		BookingStatus: string(booking.Status),
	}, nil
}

// ── Guest claim + pay ────────────────────────────────────────────────────

// ClaimAndInitiateShare assigns the next unclaimed share to the visitor's
// phone, opens an SSL session, returns the gateway URL. If the booking
// is already past its deadline or fully paid, returns an error so the
// public page can show a clean message.
func (s *BookingSplitService) ClaimAndInitiateShare(ctx context.Context, token, phone string) (string, error) {
	if phone == "" {
		return "", fmt.Errorf("phone required")
	}

	var (
		shareToOpen *entity.BookingShare
		booking     entity.Booking
	)

	err := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Preload("Pitch").
			Where("split_token = ?", token).
			First(&booking).Error; err != nil {
			return fmt.Errorf("split not found")
		}
		if booking.Status != entity.BookingPendingSplit {
			return fmt.Errorf("split closed")
		}
		if booking.SplitDeadlineAt != nil && time.Now().After(*booking.SplitDeadlineAt) {
			return fmt.Errorf("split expired")
		}
		var share entity.BookingShare
		err := tx.Raw(`SELECT * FROM booking_shares
		               WHERE booking_id = ? AND status = 'pending' AND payer_phone IS NULL
		               ORDER BY share_no ASC
		               LIMIT 1
		               FOR UPDATE SKIP LOCKED`, booking.ID).Scan(&share).Error
		if err != nil {
			return fmt.Errorf("find unclaimed: %w", err)
		}
		if share.ID == uuid.Nil {
			return fmt.Errorf("all shares claimed")
		}
		// Try to back-link to an existing user account by phone.
		var existing entity.User
		var userPtr *uuid.UUID
		if perr := tx.Where("phone = ?", phone).First(&existing).Error; perr == nil {
			userPtr = &existing.ID
		}
		updates := map[string]any{
			"payer_phone": phone,
			"updated_at":  time.Now(),
		}
		if userPtr != nil {
			updates["payer_user_id"] = *userPtr
		}
		if err := tx.Model(&entity.BookingShare{}).
			Where("id = ?", share.ID).Updates(updates).Error; err != nil {
			return fmt.Errorf("claim share: %w", err)
		}
		share.PayerPhone = &phone
		share.PayerUserID = userPtr
		shareToOpen = &share
		return nil
	})
	if err != nil {
		return "", err
	}
	return s.openShareGateway(ctx, &booking, shareToOpen, "Friend of "+booking.User.Name, phone)
}

// openShareGateway is the shared SSL hand-off. Called for both the
// captain's auto-share (#1) on InitiateSplit and for each guest claim.
func (s *BookingSplitService) openShareGateway(
	ctx context.Context,
	booking *entity.Booking,
	share *entity.BookingShare,
	customerName, customerPhone string,
) (string, error) {
	tranID := fmt.Sprintf("BSH-%s", share.ID.String())
	amountTaka := fmt.Sprintf("%.2f", float64(share.AmountPaisa)/100.0)

	// Persist tran_id on the share so callbacks can reconcile.
	if err := s.db.WithContext(ctx).
		Model(&entity.BookingShare{}).
		Where("id = ?", share.ID).
		Update("ssl_tx_id", tranID).Error; err != nil {
		return "", fmt.Errorf("set tran_id: %w", err)
	}

	url, err := s.sslcz.Initiate(ctx, sslcommerz.InitiateRequest{
		TranID:          tranID,
		TotalAmount:     amountTaka,
		Currency:        "BDT",
		ProductName:     "Match share — " + booking.Pitch.Name,
		ProductCategory: "sports",
		CustomerName:    customerName,
		CustomerPhone:   customerPhone,
		SuccessURL:      s.appBaseURL + "/api/v1/payment/split/success",
		FailURL:         s.appBaseURL + "/api/v1/payment/split/fail",
		CancelURL:       s.appBaseURL + "/api/v1/payment/split/cancel",
		IPNURL:          s.appBaseURL + "/api/v1/payment/split/ipn",
	})
	if err != nil {
		return "", fmt.Errorf("ssl initiate: %w", err)
	}
	return url, nil
}

// ── SSL callback ─────────────────────────────────────────────────────────

// HandleShareSuccess reconciles an SSL Commerz success callback for one
// share. Idempotent: duplicate IPNs are no-ops. When this call brings
// split_paid_count to split_share_count, the booking transitions to
// confirmed and runs the standard side effects (ledger, settlement).
func (s *BookingSplitService) HandleShareSuccess(ctx context.Context, params map[string]string) error {
	tranID := params["tran_id"]
	valID := params["val_id"]
	if !strings.HasPrefix(tranID, "BSH-") {
		return fmt.Errorf("not a split share tran_id: %q", tranID)
	}
	shareIDStr := strings.TrimPrefix(tranID, "BSH-")
	shareID, err := uuid.Parse(shareIDStr)
	if err != nil {
		return fmt.Errorf("bad tran_id: %w", err)
	}

	if !sslcommerz.VerifySign(params, s.storePasswd) {
		return fmt.Errorf("HMAC verification failed for %q", tranID)
	}
	validateResp, err := s.sslcz.Validate(ctx, valID)
	if err != nil {
		return fmt.Errorf("ssl validate: %w", err)
	}
	if validateResp.Status != "VALID" {
		return fmt.Errorf("ssl status %q", validateResp.Status)
	}

	now := time.Now()
	bankTranID := validateResp.BankTranID

	// Mark paid + bump booking counter atomically.
	var (
		booking      entity.Booking
		shareCount   int
		paidNow      int
		alreadyPaid  bool
		needsConfirm bool
	)
	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var share entity.BookingShare
		if err := tx.Where("id = ?", shareID).First(&share).Error; err != nil {
			return fmt.Errorf("share not found")
		}
		if share.Status == entity.SharePaid {
			alreadyPaid = true
			return nil
		}
		if share.Status != entity.SharePending {
			return fmt.Errorf("share in non-pending state %q", share.Status)
		}
		_ = valID // val_id is verified above, not persisted — we only need bank_tran_id for refunds.
		if err := tx.Model(&entity.BookingShare{}).
			Where("id = ? AND status = 'pending'", shareID).
			Updates(map[string]any{
				"status":     entity.SharePaid,
				"paid_at":    now,
				"ssl_tx_id":  tranID,
				"ssl_val_id": bankTranID, // legacy column name; holds bank_tran_id
				"updated_at": now,
			}).Error; err != nil {
			return fmt.Errorf("mark share paid: %w", err)
		}
		// Atomic counter bump.
		if err := tx.Model(&entity.Booking{}).
			Where("id = ?", share.BookingID).
			UpdateColumn("split_paid_count", gorm.Expr("split_paid_count + 1")).Error; err != nil {
			return fmt.Errorf("bump paid count: %w", err)
		}
		if err := tx.First(&booking, "id = ?", share.BookingID).Error; err != nil {
			return err
		}
		shareCount = booking.SplitShareCount
		paidNow = booking.SplitPaidCount
		needsConfirm = paidNow == shareCount && booking.Status == entity.BookingPendingSplit
		if needsConfirm {
			if err := tx.Model(&entity.Booking{}).
				Where("id = ? AND status = ?", booking.ID, entity.BookingPendingSplit).
				Updates(map[string]any{
					"status":     entity.BookingConfirmed,
					"updated_at": now,
				}).Error; err != nil {
				return fmt.Errorf("confirm booking: %w", err)
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	if alreadyPaid {
		return nil
	}

	if needsConfirm {
		s.runConfirmSideEffects(ctx, &booking)
		log.Info().Str("booking_id", booking.ID.String()).
			Int("paid", paidNow).Int("of", shareCount).
			Msg("split booking confirmed")
	}
	return nil
}

// runConfirmSideEffects fires the same downstream events a normal
// confirmed booking would: ledger payment row, settlement-account
// credit, FCM/SMS to the captain. Best-effort — failures here log
// but don't undo the confirmation.
func (s *BookingSplitService) runConfirmSideEffects(ctx context.Context, booking *entity.Booking) {
	pitch, err := s.pitchRepo.FindByID(ctx, booking.PitchID)
	if err != nil {
		log.Warn().Err(err).Msg("split confirm: pitch lookup")
		return
	}
	totalPaisa := int64(booking.TotalCost * 100)
	monthlyVolume, _ := s.pricing.MonthlyVolume(ctx, pitch.ID)
	commissionBps := s.pricing.ResolveCommissionBps(ctx, pitch, "turfinn", monthlyVolume)

	if s.ledger != nil {
		if err := s.ledger.RecordBookingPayment(ctx, nil, booking.ID, totalPaisa, commissionBps); err != nil {
			log.Warn().Err(err).Msg("split confirm: ledger record")
		}
	}
	if s.settle != nil {
		ownerShare := totalPaisa - (totalPaisa * int64(commissionBps) / 10000)
		if ownerShare > 0 && pitch.OwnerID != uuid.Nil {
			_ = s.settle.CreditOwner(s.db.WithContext(ctx), pitch.OwnerID, ownerShare)
		}
	}
	if s.asynq != nil {
		go enqueueFCM(s.asynq, booking.UserID, "Match locked!",
			fmt.Sprintf("All friends paid. Your booking at %s on %s is confirmed.",
				pitch.Name, booking.StartsAt.Format("Jan 2, 3:04 PM")),
			map[string]string{"type": "split_confirmed", "booking_id": booking.ID.String()},
		)
		go enqueueSMSToUser(s.asynq, s.db, booking.UserID,
			fmt.Sprintf("Turfinn: Match locked! %s on %s. Total %.0f BDT.",
				pitch.Name, booking.StartsAt.Format("Jan 2 3:04 PM"), booking.TotalCost),
		)
	}
}

// ── Deadline expiry ──────────────────────────────────────────────────────

// HandleDeadlineExpiry runs at exactly split_deadline_at. If the booking
// is still in pending_split, every paid share gets refunded via SSL
// Refund and the booking is cancelled. No-op if the booking already
// confirmed (the quorum hit before the deadline).
func (s *BookingSplitService) HandleDeadlineExpiry(ctx context.Context, bookingID uuid.UUID) error {
	var booking entity.Booking
	if err := s.db.WithContext(ctx).First(&booking, "id = ?", bookingID).Error; err != nil {
		return fmt.Errorf("booking not found")
	}
	if booking.Status != entity.BookingPendingSplit {
		return nil // already confirmed or cancelled — nothing to do
	}

	paidShares, err := s.shareRepo.ListPaidForBooking(ctx, bookingID)
	if err != nil {
		return fmt.Errorf("list paid shares: %w", err)
	}

	now := time.Now()
	refunded, failed := 0, 0
	for _, sh := range paidShares {
		if sh.SSLBankTranID == nil || *sh.SSLBankTranID == "" {
			// No bank_tran_id captured — can't refund. Mark as expired
			// so we don't retry forever; surface for manual reconciliation.
			_ = s.shareRepo.MarkRefunded(ctx, sh.ID, now)
			failed++
			continue
		}
		amountTaka := fmt.Sprintf("%.2f", float64(sh.AmountPaisa)/100.0)
		_, refErr := s.sslcz.Refund(ctx, *sh.SSLBankTranID, amountTaka, "split deadline expired")
		if refErr != nil {
			log.Warn().Err(refErr).Str("share_id", sh.ID.String()).
				Msg("ssl refund (split deadline) failed")
			failed++
			continue
		}
		if err := s.shareRepo.MarkRefunded(ctx, sh.ID, now); err != nil {
			log.Warn().Err(err).Str("share_id", sh.ID.String()).
				Msg("mark refunded (split deadline)")
		}
		refunded++
	}

	// Cancel the booking regardless of refund outcomes — SSL refund
	// failures are surfaced via failed counter for manual follow-up.
	if err := s.db.WithContext(ctx).
		Model(&entity.Booking{}).
		Where("id = ? AND status = ?", bookingID, entity.BookingPendingSplit).
		Updates(map[string]any{
			"status":     entity.BookingCancelled,
			"updated_at": now,
		}).Error; err != nil {
		return fmt.Errorf("cancel booking: %w", err)
	}

	log.Info().
		Str("booking_id", bookingID.String()).
		Int("refunded", refunded).
		Int("failed", failed).
		Msg("split deadline expired")
	return nil
}

// ── helpers ──────────────────────────────────────────────────────────────

// generateToken returns a 32-char hex string (16 bytes of entropy) used
// as the magic-link key. We don't sign it — the token itself is the
// secret, looked up directly in bookings.split_token (UNIQUE column).
func generateToken() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
