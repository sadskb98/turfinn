package service

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"github.com/turfinn/backend/internal/interfaces/dto"
	"gorm.io/gorm"
)

type BookingService struct {
	bookingRepo domain.BookingRepository
	pitchRepo   domain.PitchRepository
	walletSvc   *WalletService
	gameSvc     *GamificationService
	db          *gorm.DB
	asynq       *asynq.Client
	ledger      *LedgerService
	events      *BookingEventService
	pricing     *PricingService
	settle      *WeeklySettlementService
}

func NewBookingService(bookingRepo domain.BookingRepository, pitchRepo domain.PitchRepository, walletSvc *WalletService, gameSvc *GamificationService, db *gorm.DB, asynqClient *asynq.Client) *BookingService {
	return &BookingService{
		bookingRepo: bookingRepo,
		pitchRepo:   pitchRepo,
		walletSvc:   walletSvc,
		gameSvc:     gameSvc,
		db:          db,
		asynq:       asynqClient,
		ledger:      NewLedgerService(db),
		events:      NewBookingEventService(db),
		pricing:     NewPricingService(db),
		settle:      NewWeeklySettlementService(db),
	}
}

func (s *BookingService) Create(ctx context.Context, userID uuid.UUID, req dto.CreateBookingRequest) (*entity.Booking, error) {
	// Time validations
	now := time.Now()
	if req.StartsAt.Before(now) {
		return nil, fmt.Errorf("cannot book in the past")
	}
	if req.EndsAt.Before(req.StartsAt) || req.EndsAt.Equal(req.StartsAt) {
		return nil, fmt.Errorf("end time must be after start time")
	}
	duration := req.EndsAt.Sub(req.StartsAt)
	if duration > 4*time.Hour {
		return nil, fmt.Errorf("maximum booking duration is 4 hours")
	}
	if duration < 30*time.Minute {
		return nil, fmt.Errorf("minimum booking duration is 30 minutes")
	}

	// Operating hours: 08:00 - 00:00
	startHour := req.StartsAt.Hour()
	endHour := req.EndsAt.Hour()
	endMin := req.EndsAt.Minute()
	if startHour < 8 {
		return nil, fmt.Errorf("bookings start from 08:00")
	}
	// End time can be up to 00:00 (midnight) but not after
	if endHour > 0 && endHour < 8 && !(endHour == 0 && endMin == 0) {
		return nil, fmt.Errorf("bookings end by midnight")
	}

	// Max 30 days in advance
	if req.StartsAt.After(now.Add(30 * 24 * time.Hour)) {
		return nil, fmt.Errorf("cannot book more than 30 days in advance")
	}

	pitchID, err := uuid.Parse(req.PitchID)
	if err != nil {
		return nil, fmt.Errorf("invalid pitch_id")
	}

	pitch, err := s.pitchRepo.FindByID(ctx, pitchID)
	if err != nil {
		return nil, fmt.Errorf("pitch not found")
	}

	// Pricing
	hours := req.EndsAt.Sub(req.StartsAt).Hours()
	basePrice := hours * pitch.PricePerHour
	finalPrice := s.applyPricingRules(ctx, pitchID, req.StartsAt, basePrice)

	booking := entity.NewBooking(pitchID, userID, req.StartsAt, req.EndsAt, finalPrice)
	booking.Notes = req.Notes

	// Resolve payment mode. Empty request → use the pitch's default. Reject
	// if the pitch doesn't allow the requested mode (e.g. an owner who
	// only takes cash forces partial_online).
	mode := req.PaymentMode
	if mode == "" {
		mode = pitch.DefaultPaymentMode
		if mode == "" {
			mode = entity.PaymentModeFullOnline
		}
	}
	if mode == entity.PaymentModePartialOnline && !pitch.AllowsPartialPayment {
		return nil, fmt.Errorf("this pitch requires full online payment")
	}
	if mode == entity.PaymentModeFullOnline && !pitch.AllowsFullPayment {
		return nil, fmt.Errorf("this pitch requires partial online payment (commission online + cash at venue)")
	}
	booking.PaymentMode = mode

	// Cash split: full_online charges everything online; partial charges
	// only the platform commission online and the owner collects the
	// rest as cash at the venue.
	//
	// Commission resolution goes through PricingService — single source
	// of truth for: trial 0% / ERP-only 0% / per-pitch override / volume
	// tier from monthly count. ERP-only pitches reject app bookings
	// outright since they're invisible to the player UI by design.
	if pitch.Plan == entity.PitchPlanERPOnly {
		return nil, fmt.Errorf("this pitch is on the ERP-only plan and not bookable through the app")
	}
	totalPaisa := int64(finalPrice * 100)
	monthlyVolume, _ := s.pricing.MonthlyVolume(ctx, pitchID)
	commissionBps := s.pricing.ResolveCommissionBps(ctx, pitch, "turfinn", monthlyVolume)
	commissionPaisa := totalPaisa * int64(commissionBps) / 10000
	if mode == entity.PaymentModePartialOnline {
		booking.CashDuePaisa = totalPaisa - commissionPaisa
	}

	// Atomic conflict check + insert inside a serializable transaction
	// Prevents double-booking under concurrent requests
	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Lock conflicting rows — SELECT FOR UPDATE prevents another tx from inserting
		var conflictCount int64
		if err := tx.Model(&entity.Booking{}).
			Where("pitch_id = ? AND status NOT IN ? AND starts_at < ? AND ends_at > ?",
				pitchID, []entity.BookingStatus{entity.BookingCancelled}, req.EndsAt, req.StartsAt).
			Set("gorm:query_option", "FOR UPDATE").
			Count(&conflictCount).Error; err != nil {
			return fmt.Errorf("check availability: %w", err)
		}
		if conflictCount > 0 {
			return fmt.Errorf("slot not available")
		}
		return tx.Create(booking).Error
	})
	if err != nil {
		return nil, err
	}

	// Enqueue gamification to worker — non-blocking, retryable
	if s.asynq != nil {
		EnqueueBookingGamification(s.asynq, userID, booking.ID, req.StartsAt)
	}

	go enqueueFCM(s.asynq, userID, "Booking Confirmed!",
		fmt.Sprintf("Your booking at %s on %s is confirmed.", pitch.Name, req.StartsAt.Format("Jan 2, 3:04 PM")),
		map[string]string{"type": "booking_confirmed", "booking_id": booking.ID.String()},
	)

	// SMS — same channel, more reliable in low-connectivity Bangladesh and
	// nice for users who don't grant push permission.
	smsBody := fmt.Sprintf("Turfinn: Booking confirmed at %s on %s. Total %.0f BDT.",
		pitch.Name, req.StartsAt.Format("Jan 2 3:04 PM"), booking.TotalCost)
	if booking.PaymentMode == entity.PaymentModePartialOnline {
		online := float64(totalPaisa-booking.CashDuePaisa) / 100.0
		cash := float64(booking.CashDuePaisa) / 100.0
		smsBody = fmt.Sprintf("Turfinn: Booking confirmed at %s on %s. Pay %.0f BDT online + %.0f BDT cash at venue.",
			pitch.Name, req.StartsAt.Format("Jan 2 3:04 PM"), online, cash)
	}
	go enqueueSMSToUser(s.asynq, s.db, userID, smsBody)

	// Analytics + ledger — best-effort, never block the booking. Use the
	// dynamic commission we already computed (pitch.plan-aware) so the
	// ledger reflects the same rate the customer was charged.
	if s.ledger != nil {
		if err := s.ledger.RecordBookingPayment(ctx, nil, booking.ID, totalPaisa, commissionBps); err != nil {
			fmt.Printf("ledger record (booking_payment) failed: %v\n", err)
		}
	}
	// Settlement: credit the pitch owner's running balance. Weekly cron
	// drains it. We do this AFTER the ledger insert so the totals match.
	if s.settle != nil {
		ownerShare := totalPaisa - (totalPaisa * int64(commissionBps) / 10000)
		if ownerShare > 0 && pitch.OwnerID != uuid.Nil {
			_ = s.settle.CreditOwner(s.db.WithContext(ctx), pitch.OwnerID, ownerShare)
		}
	}
	if s.events != nil {
		uid := userID
		_ = s.events.Record(ctx, EventBookingConfirmed, &uid, "", map[string]any{
			"booking_id":   booking.ID.String(),
			"pitch_id":     booking.PitchID.String(),
			"amount_paisa": totalPaisa,
		})
	}

	return booking, nil
}

func (s *BookingService) applyPricingRules(ctx context.Context, pitchID uuid.UUID, startsAt time.Time, basePrice float64) float64 {
	if s.db == nil {
		return basePrice
	}

	var rules []struct {
		Multiplier    float64 `gorm:"column:multiplier"`
		FixedAmount   float64 `gorm:"column:fixed_amount"`
		AppliesToDays string  `gorm:"column:applies_to_days"`
		TimeFrom      string  `gorm:"column:time_from"`
		TimeTo        string  `gorm:"column:time_to"`
	}

	// Get pitch owner's pricing rules — pitch-specific rules take precedence over owner-wide rules
	s.db.WithContext(ctx).Raw(`
		SELECT pr.multiplier, pr.fixed_amount, pr.applies_to_days, pr.time_from, pr.time_to
		FROM pricing_rules pr
		JOIN pitches p ON pr.owner_id = p.owner_id
		WHERE (pr.pitch_id = ? OR pr.pitch_id IS NULL)
		AND pr.is_active = true
		ORDER BY pr.pitch_id DESC NULLS LAST
		LIMIT 1
	`, pitchID).Scan(&rules)

	if len(rules) == 0 {
		return basePrice
	}

	rule := rules[0]

	// Check day applicability
	if rule.AppliesToDays != "" {
		dayName := startsAt.Weekday().String()[:3] // Mon, Tue, etc.
		if !strings.Contains(rule.AppliesToDays, dayName) {
			return basePrice
		}
	}

	// Check time range
	if rule.TimeFrom != "" && rule.TimeTo != "" {
		startTime := fmt.Sprintf("%02d:%02d", startsAt.Hour(), startsAt.Minute())
		if startTime < rule.TimeFrom || startTime >= rule.TimeTo {
			return basePrice
		}
	}

	// Apply multiplier or fixed amount
	if rule.FixedAmount > 0 {
		return rule.FixedAmount
	}
	return basePrice * rule.Multiplier
}

func (s *BookingService) GetByID(ctx context.Context, id uuid.UUID) (*entity.Booking, error) {
	return s.bookingRepo.FindByID(ctx, id)
}

func (s *BookingService) ListByUser(ctx context.Context, userID uuid.UUID, page, limit int) ([]*entity.Booking, int64, error) {
	return s.bookingRepo.ListByUser(ctx, userID, page, limit)
}

// MarkCashCollected records that the owner physically collected the cash
// portion of a partial-payment booking. Idempotent — re-marking is a no-op.
//
// Authorization: caller must be the pitch's owner (managerID matches
// pitch.owner_id). Errors otherwise to keep cross-pitch managers honest.
func (s *BookingService) MarkCashCollected(ctx context.Context, bookingID, managerID uuid.UUID) error {
	var booking entity.Booking
	if err := s.db.WithContext(ctx).
		Preload("Pitch").
		First(&booking, "id = ?", bookingID).Error; err != nil {
		return fmt.Errorf("booking not found")
	}
	if booking.Pitch.OwnerID != managerID {
		return fmt.Errorf("not authorized: this booking is not at one of your pitches")
	}
	if booking.PaymentMode != entity.PaymentModePartialOnline {
		return fmt.Errorf("booking is fully paid online — no cash to collect")
	}
	if booking.CashCollectedAt != nil {
		return nil // idempotent
	}
	if booking.CashDuePaisa <= 0 {
		return fmt.Errorf("nothing to collect")
	}

	now := time.Now()
	if err := s.db.WithContext(ctx).Model(&entity.Booking{}).
		Where("id = ? AND cash_collected_at IS NULL", bookingID).
		Updates(map[string]any{
			"cash_collected_paisa": booking.CashDuePaisa,
			"cash_collected_at":    now,
			"updated_at":           now,
		}).Error; err != nil {
		return fmt.Errorf("mark cash collected: %w", err)
	}

	// Ledger row: cash → pitch_owner. Same transaction_ref as the original
	// booking_payment so trial balance lines up cleanly.
	if s.ledger != nil {
		if err := s.ledger.Record(ctx, nil, EntryBookingPayment,
			AcctCash, AcctPitchOwner, booking.CashDuePaisa,
			"BKG-"+bookingID.String(), "booking", bookingID,
			"Cash collected at venue"); err != nil {
			fmt.Printf("ledger record (cash collected) failed: %v\n", err)
		}
	}
	return nil
}

func (s *BookingService) UpdateStatus(ctx context.Context, id uuid.UUID, status entity.BookingStatus) error {
	return s.bookingRepo.UpdateStatus(ctx, id, status)
}

func (s *BookingService) Cancel(ctx context.Context, id, requesterID uuid.UUID) error {
	booking, err := s.bookingRepo.FindByID(ctx, id)
	if err != nil {
		return fmt.Errorf("booking not found")
	}
	if booking.UserID != requesterID {
		return fmt.Errorf("forbidden")
	}
	if booking.Status != entity.BookingPending && booking.Status != entity.BookingConfirmed {
		return fmt.Errorf("cannot cancel booking in status %s", booking.Status)
	}

	// Cancellation policy: 6+ hours before = full refund, <1 hour = no refund
	hoursUntilStart := time.Until(booking.StartsAt).Hours()
	if hoursUntilStart < 0 {
		return fmt.Errorf("cannot cancel a past booking")
	}

	if err := s.bookingRepo.UpdateStatus(ctx, id, entity.BookingCancelled); err != nil {
		return err
	}

	go enqueueFCM(s.asynq, requesterID, "Booking Cancelled",
		"Your booking has been cancelled.",
		map[string]string{"type": "booking_cancelled", "booking_id": id.String()},
	)

	// SMS — explain the refund window in one line so the user knows what to
	// expect without opening the app.
	var smsBody string
	if hoursUntilStart >= 6 && booking.TotalCost > 0 {
		smsBody = fmt.Sprintf(
			"Turfinn: Your booking at %s on %s is cancelled. Refund of %.0f BDT will reach you in 3-7 business days.",
			booking.Pitch.Name, booking.StartsAt.Format("Jan 2 3:04 PM"), booking.TotalCost)
	} else {
		smsBody = fmt.Sprintf(
			"Turfinn: Your booking at %s on %s is cancelled. No refund (cancellation < 6h before kickoff).",
			booking.Pitch.Name, booking.StartsAt.Format("Jan 2 3:04 PM"))
	}
	go enqueueSMSToUser(s.asynq, s.db, requesterID, smsBody)

	// Refund policy: 6+ hours = 100% refund to wallet
	if hoursUntilStart >= 6 && booking.TotalCost > 0 {
		go func() {
			_ = s.walletSvc.TopUp(context.Background(), requesterID, int(booking.TotalCost))
		}()
		if s.ledger != nil {
			refundPaisa := int64(booking.TotalCost * 100)
			if err := s.ledger.RecordBookingRefund(ctx, nil, booking.ID, refundPaisa, "user_cancelled"); err != nil {
				fmt.Printf("ledger record (booking_refund) failed: %v\n", err)
			}
		}
	}
	// < 6 hours: no refund (money goes to turf owner per PRD)

	if s.events != nil {
		uid := requesterID
		_ = s.events.Record(ctx, EventBookingCancelled, &uid, "", map[string]any{
			"booking_id":   booking.ID.String(),
			"hours_before": hoursUntilStart,
			"refunded":     hoursUntilStart >= 6,
		})
	}

	return nil
}
