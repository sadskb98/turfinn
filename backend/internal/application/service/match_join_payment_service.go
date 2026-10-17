package service

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/rs/zerolog/log"
	"gorm.io/gorm"

	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"github.com/turfinn/backend/internal/infrastructure/sslcommerz"
	"github.com/turfinn/backend/internal/interfaces/dto"
)

// Errors surfaced to the HTTP layer for clean status mapping.
var (
	ErrJoinMatchNotFound          = errors.New("match not found")
	ErrMatchClosed            = errors.New("match is full or no longer accepting players")
	ErrAlreadyJoined          = errors.New("already joined this match")
	ErrPendingPaymentExists   = errors.New("a pending payment already exists for this match")
)

// MatchJoinPaymentService orchestrates the SSL gateway session for joining a
// match. The flow:
//
//  1. InitiatePayment — looks up the match, computes total (per_head + fee),
//     creates a `pending` payment row, and asks SSLCommerz for a gateway URL.
//     Returns the URL for the client to open. NO seat reservation yet — that
//     happens on success so the seat isn't held during checkout abandonment.
//
//  2. HandleSuccess — called by /payment/match/success. Verifies HMAC,
//     validates with SSL, then atomically: marks the payment success and
//     calls match_post_repo.JoinPost (which is the existing race-safe
//     UPDATE … WHERE spots_filled < spots_total). If the match filled while
//     the user was paying, JoinPost returns "match is full"; we mark the
//     payment refundable and return that error so the handler can refund.
type MatchJoinPaymentService struct {
	db          *gorm.DB
	matchRepo   domain.MatchPostRepository
	userRepo    domain.UserRepository
	sslcz       *sslcommerz.Client
	storePasswd string
	appBaseURL  string
	asynq       *asynq.Client
	ledger      *LedgerService
	events      *BookingEventService
}

func NewMatchJoinPaymentService(
	db *gorm.DB,
	matchRepo domain.MatchPostRepository,
	userRepo domain.UserRepository,
	sslcz *sslcommerz.Client,
	storePasswd, appBaseURL string,
) *MatchJoinPaymentService {
	return &MatchJoinPaymentService{
		db:          db,
		matchRepo:   matchRepo,
		userRepo:    userRepo,
		sslcz:       sslcz,
		storePasswd: storePasswd,
		appBaseURL:  appBaseURL,
		ledger:      NewLedgerService(db),
		events:      NewBookingEventService(db),
	}
}

// WithAsynq attaches an asynq client so the service can fire SMS / FCM
// notifications. Optional — methods short-circuit when nil.
func (s *MatchJoinPaymentService) WithAsynq(client *asynq.Client) *MatchJoinPaymentService {
	s.asynq = client
	return s
}

// InitiatePayment validates the match + capacity, creates a pending
// MatchJoinPayment row, opens the SSL gateway session, and returns the URL.
// On gateway failure, the pending row is rolled back so we don't leave noise.
func (s *MatchJoinPaymentService) InitiatePayment(
	ctx context.Context,
	matchPostID, userID uuid.UUID,
) (gatewayURL string, paymentID uuid.UUID, err error) {
	// Step 1: load + validate the match.
	post, err := s.matchRepo.FindByID(ctx, matchPostID)
	if err != nil {
		return "", uuid.Nil, fmt.Errorf("match lookup: %w", err)
	}
	if post == nil {
		return "", uuid.Nil, ErrJoinMatchNotFound
	}
	if post.Status != "open" || post.SpotsFilled >= post.SpotsTotal {
		return "", uuid.Nil, ErrMatchClosed
	}
	if post.AuthorID == userID {
		// Hosts join their own match for free — no payment session needed.
		// Caller should hit POST /feed/:id/join directly. Surface a clear error.
		return "", uuid.Nil, fmt.Errorf("hosts don't pay to join their own match")
	}

	// Step 2: reject duplicate joins (covers: already paid + race vs an
	// in-flight pending payment from this same user).
	var joinCount int64
	if err := s.db.WithContext(ctx).
		Model(&entity.MatchPostJoin{}).
		Where("post_id = ? AND user_id = ?", matchPostID, userID).
		Count(&joinCount).Error; err != nil {
		return "", uuid.Nil, fmt.Errorf("check duplicate join: %w", err)
	}
	if joinCount > 0 {
		return "", uuid.Nil, ErrAlreadyJoined
	}

	// Supersede any previous pending payment from this user for this match.
	// Rationale: if the user is calling Initiate a second time, they've
	// abandoned whatever earlier session they had — UI flow has them on the
	// confirm sheet, not in the SSL gateway. We can't dependably catch the
	// "user closed the WebView" event for SSL's session bookkeeping, so we
	// just supersede here and let the SSL session naturally time out on
	// their side. The unique join constraint + race-safe JoinPost protect
	// against double-spending if both somehow get paid.
	if err := s.db.WithContext(ctx).
		Model(&entity.MatchJoinPayment{}).
		Where("match_post_id = ? AND user_id = ? AND status = ?",
			matchPostID, userID, entity.MatchPaymentPending).
		Updates(map[string]any{
			"status":     entity.MatchPaymentCancelled,
			"updated_at": time.Now(),
		}).Error; err != nil {
		return "", uuid.Nil, fmt.Errorf("supersede pending: %w", err)
	}

	// Step 3: compute total — per-head share + commitment fee.
	perHead := 0
	if post.PerHeadCostBDT != nil {
		perHead = *post.PerHeadCostBDT
	}
	total := perHead + post.JoinFeeBDT
	if total <= 0 {
		return "", uuid.Nil, fmt.Errorf("nothing to charge for this match")
	}
	amountPaisa := int64(total) * 100
	amountTaka := fmt.Sprintf("%.2f", float64(total))

	// Step 4: load user for SSL customer details.
	user, err := s.userRepo.FindByID(ctx, userID)
	if err != nil {
		return "", uuid.Nil, fmt.Errorf("load user: %w", err)
	}

	// Step 5: insert pending payment row. Tran ID disambiguates the callback
	// path in the success/IPN handler ("MJP-" prefix → match join).
	payment := entity.MatchJoinPayment{
		MatchPostID: matchPostID,
		UserID:      userID,
		AmountPaisa: amountPaisa,
		Currency:    "BDT",
		Status:      entity.MatchPaymentPending,
	}
	if err := s.db.WithContext(ctx).Create(&payment).Error; err != nil {
		return "", uuid.Nil, fmt.Errorf("create payment row: %w", err)
	}
	tranID := fmt.Sprintf("MJP-%s", payment.ID.String())
	payment.TranID = &tranID
	if err := s.db.WithContext(ctx).Model(&payment).Update("tran_id", tranID).Error; err != nil {
		return "", uuid.Nil, fmt.Errorf("set tran_id: %w", err)
	}

	customerName := "Player"
	if user.Name != "" {
		customerName = user.Name
	}
	customerPhone := ""
	if user.Phone != nil && *user.Phone != "" {
		customerPhone = *user.Phone
	}

	// Step 6: open SSL gateway session.
	gw, err := s.sslcz.Initiate(ctx, sslcommerz.InitiateRequest{
		TranID:          tranID,
		TotalAmount:     amountTaka,
		Currency:        "BDT",
		ProductName:     "Match join — " + post.Title,
		ProductCategory: "sports",
		CustomerName:    customerName,
		CustomerPhone:   customerPhone,
		SuccessURL:      s.appBaseURL + "/api/v1/payment/match/success",
		FailURL:         s.appBaseURL + "/api/v1/payment/match/fail",
		CancelURL:       s.appBaseURL + "/api/v1/payment/match/cancel",
		IPNURL:          s.appBaseURL + "/api/v1/payment/match/ipn",
	})
	if err != nil {
		// Compensating delete so abandoned pending rows don't accumulate.
		_ = s.db.WithContext(ctx).Delete(&payment).Error
		return "", uuid.Nil, fmt.Errorf("ssl initiate: %w", err)
	}
	return gw, payment.ID, nil
}

// HandleSuccessWithParams is the modern entry point — takes the FULL form
// payload from SSL (~30 fields) so HMAC verification can resolve any
// `verify_key` field name SSL throws at it. The legacy DTO-based version
// only carried 11 fields and silently failed verification on every real
// payment because verify_key referenced fields like `value_a`,
// `currency_amount`, `risk_level` etc. that we hadn't modeled.
func (s *MatchJoinPaymentService) HandleSuccessWithParams(ctx context.Context, params map[string]string) error {
	tranID := params["tran_id"]
	valID := params["val_id"]
	if tranID == "" {
		return fmt.Errorf("missing tran_id")
	}

	var payment entity.MatchJoinPayment
	if err := s.db.WithContext(ctx).First(&payment, "tran_id = ?", tranID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return fmt.Errorf("match-join payment not found for tran_id %q", tranID)
		}
		return fmt.Errorf("read payment: %w", err)
	}
	if payment.Status == entity.MatchPaymentSuccess {
		return nil // idempotent
	}

	if !sslcommerz.VerifySign(params, s.storePasswd) {
		// Surface the exact computed string vs expected sign so we can diff
		// when iterating on the algorithm.
		dbg, computed := sslcommerz.DebugSignString(params, s.storePasswd)
		log.Warn().
			Str("tran_id", tranID).
			Str("verify_key", params["verify_key"]).
			Str("expected_sign", params["verify_sign"]).
			Str("computed_sign", computed).
			Str("hash_input", dbg).
			Msg("HMAC verification failed")
		return fmt.Errorf("HMAC verification failed for %q", tranID)
	}
	validateResp, err := s.sslcz.Validate(ctx, valID)
	if err != nil {
		log.Warn().Err(err).Str("tran_id", tranID).Str("val_id", valID).
			Msg("ssl validate request failed")
		return fmt.Errorf("ssl validate: %w", err)
	}
	if validateResp.Status != "VALID" {
		log.Warn().Str("tran_id", tranID).Str("val_id", valID).
			Str("ssl_status", validateResp.Status).
			Msg("ssl validate returned non-VALID")
		return fmt.Errorf("ssl status %q for %q", validateResp.Status, tranID)
	}

	joinErr := s.matchRepo.JoinPost(ctx, payment.MatchPostID, payment.UserID)
	now := time.Now()
	updates := map[string]any{
		"val_id":       &valID,
		"bank_tran_id": &validateResp.BankTranID,
		"status":       entity.MatchPaymentSuccess,
		"updated_at":   now,
	}
	if joinErr != nil {
		updates["status"] = entity.MatchPaymentFailed
		updates["refund_status"] = entity.RefundRequested
		updates["refund_reason"] = entity.RefundReasonAutoCancel
		updates["refund_requested_at"] = now
	}
	if err := s.db.WithContext(ctx).Model(&payment).Updates(updates).Error; err != nil {
		return fmt.Errorf("mark payment terminal: %w", err)
	}
	if joinErr != nil {
		return fmt.Errorf("payment ok but join failed (will refund): %w", joinErr)
	}
	// Fire-and-forget telemetry: ledger entry for the deposit + funnel event.
	// Failures here log but don't roll back the payment — the money is real,
	// the analytics are ancillary.
	if err := s.ledger.RecordMatchJoinPayment(ctx, nil, payment.ID, payment.MatchPostID, payment.AmountPaisa); err != nil {
		log.Warn().Err(err).Str("tran_id", tranID).Msg("ledger record (match_payment) failed")
	}
	uid := payment.UserID
	if err := s.events.Record(ctx, EventMatchPaid, &uid, "", map[string]any{
		"match_post_id": payment.MatchPostID.String(),
		"amount_paisa":  payment.AmountPaisa,
	}); err != nil {
		log.Warn().Err(err).Str("tran_id", tranID).Msg("event (match_paid) failed")
	}
	// Quorum check: this join might have just tipped the match into
	// confirmed territory. CreateBookingForMatchIfQuorum is idempotent;
	// safe to call on every join.
	if _, err := s.CreateBookingForMatchIfQuorum(ctx, payment.MatchPostID); err != nil {
		log.Warn().Err(err).Str("match_post_id", payment.MatchPostID.String()).
			Msg("quorum-first booking creation failed (refund not affected)")
	}
	return nil
}

// HandleSuccess — kept for backward compat. Delegates to the params-map
// version after expanding the DTO.
func (s *MatchJoinPaymentService) HandleSuccess(ctx context.Context, params dto.SSLCallbackParams) error {
	var payment entity.MatchJoinPayment
	if err := s.db.WithContext(ctx).First(&payment, "tran_id = ?", params.TranID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return fmt.Errorf("match-join payment not found for tran_id %q", params.TranID)
		}
		return fmt.Errorf("read payment: %w", err)
	}
	if payment.Status == entity.MatchPaymentSuccess {
		return nil // idempotent
	}

	if !sslcommerz.VerifySign(paramsAsMap(params), s.storePasswd) {
		return fmt.Errorf("HMAC verification failed for %q", params.TranID)
	}
	validateResp, err := s.sslcz.Validate(ctx, params.ValID)
	if err != nil {
		return fmt.Errorf("ssl validate: %w", err)
	}
	if validateResp.Status != "VALID" {
		return fmt.Errorf("ssl status %q for %q", validateResp.Status, params.TranID)
	}

	// Atomic seat reservation. If the match is full at this point, JoinPost
	// fails — we mark the payment as success-but-refundable so the next sweep
	// (admin or cron) can issue the refund.
	joinErr := s.matchRepo.JoinPost(ctx, payment.MatchPostID, payment.UserID)
	now := time.Now()
	updates := map[string]any{
		"val_id":       &params.ValID,
		"bank_tran_id": &validateResp.BankTranID, // needed for any future refund
		"status":       entity.MatchPaymentSuccess,
		"updated_at":   now,
	}
	if joinErr != nil {
		// Money was charged but the seat raced away — auto-flag for refund.
		updates["status"] = entity.MatchPaymentFailed
		updates["refund_status"] = entity.RefundRequested
		updates["refund_reason"] = entity.RefundReasonAutoCancel
		updates["refund_requested_at"] = now
	}
	if err := s.db.WithContext(ctx).Model(&payment).Updates(updates).Error; err != nil {
		return fmt.Errorf("mark payment terminal: %w", err)
	}
	if joinErr != nil {
		return fmt.Errorf("payment ok but join failed (will refund): %w", joinErr)
	}
	return nil
}

// MarkRefundsRequested flags every successful payment for this match as
// "refund requested" so the cron picks them up. Used by host-cancel and
// auto-cancel paths.
func (s *MatchJoinPaymentService) MarkRefundsRequested(
	ctx context.Context,
	matchPostID uuid.UUID,
	reason string,
) (int, error) {
	now := time.Now()
	res := s.db.WithContext(ctx).Model(&entity.MatchJoinPayment{}).
		Where("match_post_id = ? AND status = ? AND refund_status IS NULL",
			matchPostID, entity.MatchPaymentSuccess).
		Updates(map[string]any{
			"refund_status":       entity.RefundRequested,
			"refund_reason":       reason,
			"refund_requested_at": now,
			"updated_at":          now,
		})
	return int(res.RowsAffected), res.Error
}

// ProcessPendingRefunds runs SSL refund for every payment with
// refund_status='requested' or 'refund_failed'. Called by the cron worker
// every few minutes. Each row is attempted at most ~10 times — beyond that
// it stays "refund_failed" and admins triage manually.
func (s *MatchJoinPaymentService) ProcessPendingRefunds(ctx context.Context) (success, failed int, err error) {
	const maxAttempts = 10
	var rows []entity.MatchJoinPayment
	if err := s.db.WithContext(ctx).
		Where("refund_status IN ? AND refund_attempts < ?",
			[]string{entity.RefundRequested, entity.RefundFailed}, maxAttempts).
		Limit(50).
		Find(&rows).Error; err != nil {
		return 0, 0, err
	}

	for _, p := range rows {
		// Spacing protects us from SSL's per-minute rate limit.
		select {
		case <-ctx.Done():
			return success, failed, ctx.Err()
		case <-time.After(500 * time.Millisecond):
		}
		if p.BankTranID == nil || *p.BankTranID == "" {
			s.bumpRefundFailure(ctx, &p, fmt.Errorf("no bank_tran_id captured at success time"))
			failed++
			continue
		}
		amountTaka := fmt.Sprintf("%.2f", float64(p.AmountPaisa)/100.0)
		remarks := "Match cancelled"
		if p.RefundReason != nil {
			remarks = "Match cancelled — " + *p.RefundReason
		}
		resp, refErr := s.sslcz.Refund(ctx, *p.BankTranID, amountTaka, remarks)
		if refErr != nil {
			s.bumpRefundFailure(ctx, &p, refErr)
			failed++
			continue
		}
		now := time.Now()
		err := s.db.WithContext(ctx).Model(&p).Updates(map[string]any{
			"refund_status":       entity.RefundDone,
			"refund_ref_id":       &resp.RefundRefID,
			"refund_completed_at": now,
			"refund_attempts":     p.RefundAttempts + 1,
			"last_refund_error":   nil,
			"updated_at":          now,
		}).Error
		if err != nil {
			failed++
			continue
		}
		// Ledger row for the actual outflow. Reason embeds in description so
		// trial balance / VAT report can attribute it.
		reason := "joiner_cancelled"
		if p.RefundReason != nil && *p.RefundReason != "" {
			reason = *p.RefundReason
		}
		if err := s.ledger.RecordMatchJoinRefund(ctx, nil, p.ID, p.AmountPaisa, reason); err != nil {
			log.Warn().Err(err).Str("payment_id", p.ID.String()).Msg("ledger record (refund) failed")
		}
		// SMS — confirms the refund landed so user doesn't have to open the app.
		go enqueueSMSToUser(s.asynq, s.db, p.UserID,
			fmt.Sprintf("Turfinn: Refund of %.0f BDT processed. Allow 3-7 business days for it to appear on your card / mobile banking.",
				float64(p.AmountPaisa)/100.0))
		success++
	}
	return success, failed, nil
}

func (s *MatchJoinPaymentService) bumpRefundFailure(ctx context.Context, p *entity.MatchJoinPayment, refErr error) {
	now := time.Now()
	msg := refErr.Error()
	_ = s.db.WithContext(ctx).Model(p).Updates(map[string]any{
		"refund_status":     entity.RefundFailed,
		"refund_attempts":   p.RefundAttempts + 1,
		"last_refund_error": &msg,
		"updated_at":        now,
	}).Error
}

// CancelMatchByHost is the host-driven cancel path. Marks the post cancelled
// and triggers refunds for everyone who paid. The cron picks up the
// 'requested' rows and actually issues the SSL refund calls.
func (s *MatchJoinPaymentService) CancelMatchByHost(
	ctx context.Context,
	matchPostID, callerID uuid.UUID,
	reason string,
) (refundsRequested int, err error) {
	post, err := s.matchRepo.FindByID(ctx, matchPostID)
	if err != nil {
		return 0, err
	}
	if post == nil {
		return 0, ErrJoinMatchNotFound
	}
	if post.AuthorID != callerID {
		return 0, fmt.Errorf("only the host can cancel this match")
	}
	if post.Status == "cancelled" {
		return 0, fmt.Errorf("match already cancelled")
	}

	// Mark the post cancelled in one transaction with the refund flagging.
	now := time.Now()
	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&post).Updates(map[string]any{
			"status":               "cancelled",
			"cancelled_at":         now,
			"cancellation_reason":  reason,
			"updated_at":           now,
		}).Error; err != nil {
			return fmt.Errorf("mark post cancelled: %w", err)
		}
		// Inline the same flagging logic — needs the same tx.
		res := tx.Model(&entity.MatchJoinPayment{}).
			Where("match_post_id = ? AND status = ? AND refund_status IS NULL",
				matchPostID, entity.MatchPaymentSuccess).
			Updates(map[string]any{
				"refund_status":       entity.RefundRequested,
				"refund_reason":       entity.RefundReasonHostCancel,
				"refund_requested_at": now,
				"updated_at":          now,
			})
		if res.Error != nil {
			return fmt.Errorf("flag refunds: %w", res.Error)
		}
		refundsRequested = int(res.RowsAffected)
		return nil
	})
	if err == nil {
		if e := s.events.Record(ctx, EventMatchHostCancelled, &callerID, "", map[string]any{
			"match_post_id":      matchPostID.String(),
			"reason":             reason,
			"refunds_requested":  refundsRequested,
		}); e != nil {
			log.Warn().Err(e).Str("match_post_id", matchPostID.String()).
				Msg("event (match_host_cancelled) failed")
		}
	}
	return refundsRequested, err
}

// AdminPaymentRow is one row of the super-admin refund queue. Joins user +
// match-post details so the operator UI doesn't have to make N+1 lookups.
type AdminPaymentRow struct {
	ID             uuid.UUID  `json:"id"`
	MatchPostID    uuid.UUID  `json:"match_post_id"`
	MatchTitle     string     `json:"match_title"`
	UserID         uuid.UUID  `json:"user_id"`
	UserName       string     `json:"user_name"`
	UserPhone      string     `json:"user_phone"`
	AmountPaisa    int64      `json:"amount_paisa"`
	Status         string     `json:"status"`
	RefundStatus   *string    `json:"refund_status"`
	RefundReason   *string    `json:"refund_reason"`
	RefundAttempts int        `json:"refund_attempts"`
	RefundRefID    *string    `json:"refund_ref_id"`
	LastRefundError *string   `json:"last_refund_error"`
	CreatedAt      time.Time  `json:"created_at"`
	RefundRequestedAt *time.Time `json:"refund_requested_at"`
	RefundCompletedAt *time.Time `json:"refund_completed_at"`
}

// AdminPaymentFilter is a thin filter struct so handlers don't have to thread
// a half-dozen optional args.
type AdminPaymentFilter struct {
	Status       string // payment status: "" = all
	RefundStatus string // refund status: "" = all
	Search       string // ILIKE on user name / phone / tran_id
	Page         int
	Limit        int
}

// AdminListPayments returns paginated rows for the super-admin refund queue.
// We hand-roll the joins via a raw SELECT so all the display fields land in
// one round-trip and we don't accidentally N+1 on every row preload.
func (s *MatchJoinPaymentService) AdminListPayments(
	ctx context.Context,
	f AdminPaymentFilter,
) ([]AdminPaymentRow, int64, error) {
	if f.Page < 1 {
		f.Page = 1
	}
	if f.Limit <= 0 || f.Limit > 100 {
		f.Limit = 25
	}

	q := s.db.WithContext(ctx).Table("match_join_payments AS p").
		Joins("LEFT JOIN match_posts m ON m.id = p.match_post_id").
		Joins("LEFT JOIN users u ON u.id = p.user_id")
	if f.Status != "" {
		q = q.Where("p.status = ?", f.Status)
	}
	if f.RefundStatus == "any" {
		q = q.Where("p.refund_status IS NOT NULL")
	} else if f.RefundStatus != "" {
		q = q.Where("p.refund_status = ?", f.RefundStatus)
	}
	if f.Search != "" {
		like := "%" + f.Search + "%"
		q = q.Where(
			"u.name ILIKE ? OR u.phone ILIKE ? OR p.tran_id ILIKE ? OR m.title ILIKE ?",
			like, like, like, like,
		)
	}

	var total int64
	if err := q.Session(&gorm.Session{}).Count(&total).Error; err != nil {
		return nil, 0, err
	}

	type row struct {
		AdminPaymentRow
		// Anonymous embeds so gorm can scan into the typed fields below.
	}
	var rows []AdminPaymentRow
	err := q.
		Select(`p.id, p.match_post_id, COALESCE(m.title,'') AS match_title,
			p.user_id, COALESCE(u.name,'') AS user_name,
			COALESCE(u.phone,'') AS user_phone,
			p.amount_paisa, p.status, p.refund_status, p.refund_reason,
			p.refund_attempts, p.refund_ref_id, p.last_refund_error,
			p.created_at, p.refund_requested_at, p.refund_completed_at`).
		Order("COALESCE(p.refund_requested_at, p.created_at) DESC").
		Offset((f.Page - 1) * f.Limit).
		Limit(f.Limit).
		Scan(&rows).Error
	if err != nil {
		return nil, 0, err
	}
	return rows, total, nil
}

// AdminRetryRefund flips a row from refund_failed back to requested so the
// next cron tick picks it up. Operator override for stuck refunds.
func (s *MatchJoinPaymentService) AdminRetryRefund(
	ctx context.Context,
	paymentID uuid.UUID,
) error {
	res := s.db.WithContext(ctx).Model(&entity.MatchJoinPayment{}).
		Where("id = ? AND status = ? AND refund_status IS NOT NULL AND refund_status <> ?",
			paymentID, entity.MatchPaymentSuccess, entity.RefundDone).
		Updates(map[string]any{
			"refund_status":     entity.RefundRequested,
			"refund_attempts":   0,
			"last_refund_error": nil,
			"updated_at":        time.Now(),
		})
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return fmt.Errorf("payment not eligible for retry (not refundable or already refunded)")
	}
	return nil
}

// AdminMarkRefunded is the manual override for refunds settled outside our
// system (e.g. operator processed it via SSL portal). Stores a free-form
// note in refund_ref_id prefixed with "manual:" so the UI can flag it.
func (s *MatchJoinPaymentService) AdminMarkRefunded(
	ctx context.Context,
	paymentID uuid.UUID,
	operatorNote string,
) error {
	now := time.Now()
	tag := "manual:" + operatorNote
	if operatorNote == "" {
		tag = "manual"
	}
	// Load the payment first so we know the amount for the ledger entry.
	var payment entity.MatchJoinPayment
	if err := s.db.WithContext(ctx).First(&payment, "id = ?", paymentID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return fmt.Errorf("payment not found")
		}
		return err
	}
	wasAlreadyRefunded := payment.RefundStatus != nil && *payment.RefundStatus == entity.RefundDone

	res := s.db.WithContext(ctx).Model(&entity.MatchJoinPayment{}).
		Where("id = ?", paymentID).
		Updates(map[string]any{
			"refund_status":       entity.RefundDone,
			"refund_ref_id":       &tag,
			"refund_completed_at": &now,
			"last_refund_error":   nil,
			"updated_at":          now,
		})
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return fmt.Errorf("payment not found")
	}
	// Ledger entry only on the transition from "not refunded" to "refunded".
	// Re-marking an already-refunded row would double-count the outflow.
	if !wasAlreadyRefunded {
		reason := "manual_override"
		if operatorNote != "" {
			reason = "manual:" + operatorNote
		}
		if err := s.ledger.RecordMatchJoinRefund(ctx, nil, payment.ID, payment.AmountPaisa, reason); err != nil {
			log.Warn().Err(err).Str("payment_id", payment.ID.String()).Msg("ledger record (manual refund) failed")
		}
	}
	return nil
}

// AdminCancellationRow is a flat row for the cancelled-matches admin log.
type AdminCancellationRow struct {
	MatchID            uuid.UUID  `json:"match_id"`
	Title              string     `json:"title"`
	HostName           string     `json:"host_name"`
	PitchName          string     `json:"pitch_name"`
	MatchDate          time.Time  `json:"match_date"`
	CancelledAt        *time.Time `json:"cancelled_at"`
	CancellationReason string     `json:"cancellation_reason"`
	JoinerCount        int        `json:"joiner_count"`
	RefundsRequested   int        `json:"refunds_requested"`
	RefundsCompleted   int        `json:"refunds_completed"`
	RefundsFailed      int        `json:"refunds_failed"`
}

// AdminListCancellations returns the cancellation audit log with refund
// roll-up counts so operators can see at a glance which cancellations have
// outstanding refunds. Filtered to status='cancelled' match_posts only.
func (s *MatchJoinPaymentService) AdminListCancellations(
	ctx context.Context,
	page, limit int,
) ([]AdminCancellationRow, int64, error) {
	if page < 1 {
		page = 1
	}
	if limit <= 0 || limit > 100 {
		limit = 25
	}

	var total int64
	if err := s.db.WithContext(ctx).Table("match_posts").
		Where("status = ?", "cancelled").
		Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var rows []AdminCancellationRow
	err := s.db.WithContext(ctx).
		Raw(`
			SELECT
				m.id AS match_id,
				m.title,
				COALESCE(u.name,'') AS host_name,
				COALESCE(p.name,'') AS pitch_name,
				m.match_date,
				m.cancelled_at,
				COALESCE(m.cancellation_reason,'') AS cancellation_reason,
				(SELECT COUNT(*) FROM match_post_joins jx WHERE jx.post_id = m.id) AS joiner_count,
				(SELECT COUNT(*) FROM match_join_payments mp WHERE mp.match_post_id = m.id AND mp.refund_status IS NOT NULL) AS refunds_requested,
				(SELECT COUNT(*) FROM match_join_payments mp WHERE mp.match_post_id = m.id AND mp.refund_status = ?) AS refunds_completed,
				(SELECT COUNT(*) FROM match_join_payments mp WHERE mp.match_post_id = m.id AND mp.refund_status = ?) AS refunds_failed
			FROM match_posts m
			LEFT JOIN users u ON u.id = m.author_id
			LEFT JOIN pitches p ON p.id = m.pitch_id
			WHERE m.status = 'cancelled'
			ORDER BY m.cancelled_at DESC NULLS LAST, m.updated_at DESC
			LIMIT ? OFFSET ?
		`, entity.RefundDone, entity.RefundFailed, limit, (page-1)*limit).
		Scan(&rows).Error
	if err != nil {
		return nil, 0, err
	}
	return rows, total, nil
}

// ManagerListCancellations is the per-pitch-owner cut of cancelled matches.
// Matches are filtered to those at pitches the manager owns. Same row shape
// as the super-admin variant — managers see refund roll-ups so they can
// flag stuck refunds upstream.
func (s *MatchJoinPaymentService) ManagerListCancellations(
	ctx context.Context,
	managerID uuid.UUID,
	page, limit int,
) ([]AdminCancellationRow, int64, error) {
	if page < 1 {
		page = 1
	}
	if limit <= 0 || limit > 100 {
		limit = 25
	}

	var total int64
	if err := s.db.WithContext(ctx).Table("match_posts AS m").
		Joins("JOIN pitches p ON p.id = m.pitch_id").
		Where("m.status = ? AND p.owner_id = ?", "cancelled", managerID).
		Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var rows []AdminCancellationRow
	err := s.db.WithContext(ctx).
		Raw(`
			SELECT
				m.id AS match_id,
				m.title,
				COALESCE(u.name,'') AS host_name,
				COALESCE(p.name,'') AS pitch_name,
				m.match_date,
				m.cancelled_at,
				COALESCE(m.cancellation_reason,'') AS cancellation_reason,
				(SELECT COUNT(*) FROM match_post_joins jx WHERE jx.post_id = m.id) AS joiner_count,
				(SELECT COUNT(*) FROM match_join_payments mp WHERE mp.match_post_id = m.id AND mp.refund_status IS NOT NULL) AS refunds_requested,
				(SELECT COUNT(*) FROM match_join_payments mp WHERE mp.match_post_id = m.id AND mp.refund_status = ?) AS refunds_completed,
				(SELECT COUNT(*) FROM match_join_payments mp WHERE mp.match_post_id = m.id AND mp.refund_status = ?) AS refunds_failed
			FROM match_posts m
			JOIN pitches p ON p.id = m.pitch_id
			LEFT JOIN users u ON u.id = m.author_id
			WHERE m.status = 'cancelled' AND p.owner_id = ?
			ORDER BY m.cancelled_at DESC NULLS LAST, m.updated_at DESC
			LIMIT ? OFFSET ?
		`, entity.RefundDone, entity.RefundFailed, managerID, limit, (page-1)*limit).
		Scan(&rows).Error
	if err != nil {
		return nil, 0, err
	}
	return rows, total, nil
}

// CreateBookingForMatchIfQuorum is the heart of quorum-first matchmaking.
// Called after every successful join. If the match has now crossed its
// quorum threshold (default 50% spots filled) AND no booking has been
// created yet, it inserts a confirmed Booking on the pitch — locking the
// slot against solo bookers.
//
// Idempotent: the unique partial index on
// bookings(source_match_post_id) WHERE source_match_post_id IS NOT NULL AND
// status != 'cancelled' guarantees we never create more than one booking
// per match. We also short-circuit when match_post.booking_id is set.
//
// Returns the booking ID (or nil) and any error. Errors are surfaced but
// the caller should log-and-continue rather than fail the join.
func (s *MatchJoinPaymentService) CreateBookingForMatchIfQuorum(
	ctx context.Context,
	matchPostID uuid.UUID,
) (*uuid.UUID, error) {
	post, err := s.matchRepo.FindByID(ctx, matchPostID)
	if err != nil || post == nil {
		return nil, err
	}
	// Only Turfinn-pitch matches reserve a slot. External / custom pitches
	// stay informal — the host arranges the venue themselves.
	if post.PitchID == nil {
		return nil, nil
	}
	if post.BookingID != nil {
		return post.BookingID, nil // already booked
	}
	if post.Status != "open" {
		return nil, nil
	}
	quorum := post.QuorumMinPct
	if quorum <= 0 || quorum > 100 {
		quorum = 50
	}
	// Need at least quorum% of spots filled.
	if post.SpotsFilled*100 < post.SpotsTotal*quorum {
		return nil, nil
	}
	// Compute the booking total and create the row in one transaction so a
	// crash mid-flight either rolls back both updates or commits both.
	end := post.MatchDate.Add(time.Duration(post.DurationMinutes) * time.Minute)
	totalCost := 0.0
	if post.Pitch != nil {
		totalCost = post.Pitch.PricePerHour * float64(post.DurationMinutes) / 60.0
	}

	var bookingID uuid.UUID
	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Re-check inside the tx to avoid a race where two joins both think
		// they tipped the quorum.
		var fresh entity.MatchPost
		if err := tx.First(&fresh, "id = ?", matchPostID).Error; err != nil {
			return err
		}
		if fresh.BookingID != nil {
			bookingID = *fresh.BookingID
			return nil
		}
		booking := entity.NewBooking(*post.PitchID, post.AuthorID, post.MatchDate, end, totalCost)
		booking.Status = entity.BookingConfirmed
		booking.Source = "match"
		booking.PaymentMode = entity.PaymentModePartialOnline // joiners pay online; host owes cash share at venue
		booking.SourceMatchPostID = &matchPostID
		// In partial mode the cash side equals the owner share.
		totalPaisa := int64(totalCost * 100)
		booking.CashDuePaisa = totalPaisa - (totalPaisa * 1500 / 10000) // 85% cash
		if err := tx.Create(booking).Error; err != nil {
			return fmt.Errorf("create match booking: %w", err)
		}
		bookingID = booking.ID
		return tx.Model(&entity.MatchPost{}).
			Where("id = ?", matchPostID).
			Update("booking_id", booking.ID).Error
	})
	if err != nil {
		return nil, err
	}
	if bookingID == uuid.Nil {
		return nil, nil
	}
	// Best-effort SMS to the host so they know the match is confirmed +
	// what cash they owe the venue.
	hostMsg := fmt.Sprintf(
		"Turfinn: Your match has %d/%d players — slot at %s on %s is now confirmed. Bring %.0f BDT cash to the pitch.",
		post.SpotsFilled, post.SpotsTotal,
		post.Pitch.Name, post.MatchDate.Format("Jan 2 3:04 PM"),
		float64(int64(totalCost*100)-(int64(totalCost*100)*1500/10000))/100.0)
	go enqueueSMSToUser(s.asynq, s.db, post.AuthorID, hostMsg)
	return &bookingID, nil
}

// MyPaymentInfo is the per-match payment summary returned by PaymentStatusFor.
// Empty Status means "no payment row" (e.g., the user is the host).
type MyPaymentInfo struct {
	Status       string
	RefundStatus *string
}

// PaymentStatusFor looks up the caller's most recent payment row for each
// supplied match post. Used by /feed/mine and /feed/:id to surface the
// "Refund queued" / "Refunded" badges in the player UI.
func (s *MatchJoinPaymentService) PaymentStatusFor(
	ctx context.Context,
	userID uuid.UUID,
	postIDs []uuid.UUID,
) (map[uuid.UUID]MyPaymentInfo, error) {
	out := make(map[uuid.UUID]MyPaymentInfo, len(postIDs))
	if len(postIDs) == 0 {
		return out, nil
	}
	var rows []entity.MatchJoinPayment
	// Order DESC so the latest row wins on duplicates (superseded pendings).
	if err := s.db.WithContext(ctx).
		Where("user_id = ? AND match_post_id IN ?", userID, postIDs).
		Order("created_at DESC").
		Find(&rows).Error; err != nil {
		return nil, err
	}
	for _, p := range rows {
		if _, exists := out[p.MatchPostID]; exists {
			continue
		}
		out[p.MatchPostID] = MyPaymentInfo{
			Status:       p.Status,
			RefundStatus: p.RefundStatus,
		}
	}
	return out, nil
}

// LeaveMatchByJoiner is the joiner-driven cancel path. The user pulls out of
// a match they joined; we release their seat and queue an SSL refund. To stop
// last-minute drop-outs gaming the system, refunds only fire if the cutoff
// hasn't passed (default 60 minutes before kickoff). Past the cutoff we still
// release the seat (so the host can re-fill) but flag the payment as a
// dispute the host can choose to refund manually.
func (s *MatchJoinPaymentService) LeaveMatchByJoiner(
	ctx context.Context,
	matchPostID, userID uuid.UUID,
	cutoffMinutes int,
) (refunded bool, err error) {
	post, err := s.matchRepo.FindByID(ctx, matchPostID)
	if err != nil {
		return false, err
	}
	if post == nil {
		return false, ErrJoinMatchNotFound
	}
	if post.AuthorID == userID {
		return false, fmt.Errorf("hosts cancel via host-cancel — use POST /feed/:id/cancel")
	}

	// Refund only if we're outside the cutoff window. cutoffMinutes<=0 means
	// "always allow refund" (admin/test override).
	now := time.Now()
	allowRefund := cutoffMinutes <= 0 ||
		post.MatchDate.After(now.Add(time.Duration(cutoffMinutes)*time.Minute))

	err = s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Release the seat first — if this fails the user wasn't a joiner
		// and we shouldn't touch any payment row.
		if err := s.matchRepo.LeavePost(ctx, matchPostID, userID); err != nil {
			return err
		}
		if !allowRefund {
			return nil
		}
		// Flag this user's most recent successful payment for refund. There
		// is at most one — the unique join constraint enforces it.
		res := tx.Model(&entity.MatchJoinPayment{}).
			Where("match_post_id = ? AND user_id = ? AND status = ? AND refund_status IS NULL",
				matchPostID, userID, entity.MatchPaymentSuccess).
			Updates(map[string]any{
				"refund_status":       entity.RefundRequested,
				"refund_reason":       entity.RefundReasonJoinerCancel,
				"refund_requested_at": now,
				"updated_at":          now,
			})
		if res.Error != nil {
			return fmt.Errorf("flag refund: %w", res.Error)
		}
		refunded = res.RowsAffected > 0
		return nil
	})
	if err == nil {
		if e := s.events.Record(ctx, EventMatchLeft, &userID, "", map[string]any{
			"match_post_id": matchPostID.String(),
			"refund_queued": refunded,
		}); e != nil {
			log.Warn().Err(e).Str("match_post_id", matchPostID.String()).
				Msg("event (match_left) failed")
		}
	}
	return refunded, err
}

// ExpireStalePending sweeps every pending payment older than the TTL.
// Called by the match:auto_cancel cron. Prevents users getting locked out
// when they abandon a checkout session.
func (s *MatchJoinPaymentService) ExpireStalePending(ctx context.Context) (int, error) {
	const pendingTTL = 15 * time.Minute
	cutoff := time.Now().Add(-pendingTTL)
	res := s.db.WithContext(ctx).
		Model(&entity.MatchJoinPayment{}).
		Where("status = ? AND created_at < ?", entity.MatchPaymentPending, cutoff).
		Updates(map[string]any{
			"status":     entity.MatchPaymentExpired,
			"updated_at": time.Now(),
		})
	return int(res.RowsAffected), res.Error
}

// HandleFail / HandleCancel mark the pending row as terminal so the cron
// release/expire path doesn't pick it up.
func (s *MatchJoinPaymentService) HandleTerminal(ctx context.Context, tranID, status string) error {
	return s.db.WithContext(ctx).Model(&entity.MatchJoinPayment{}).
		Where("tran_id = ? AND status = ?", tranID, entity.MatchPaymentPending).
		Updates(map[string]any{"status": status, "updated_at": time.Now()}).Error
}
