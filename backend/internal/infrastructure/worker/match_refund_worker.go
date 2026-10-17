package worker

import (
	"context"
	"time"

	"github.com/hibiken/asynq"
	"github.com/rs/zerolog/log"
	"gorm.io/gorm"

	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/config"
	"github.com/turfinn/backend/internal/domain/entity"
)

const (
	TypeMatchRefundRetry  = "match:refund_retry"
	TypeMatchAutoCancel   = "match:auto_cancel"
)

// MatchRefundWorker processes pending SSL refunds and auto-cancels match
// posts whose kickoff has passed without filling.
type MatchRefundWorker struct {
	db        *gorm.DB
	paySvc    *service.MatchJoinPaymentService
}

func NewMatchRefundWorker(db *gorm.DB, paySvc *service.MatchJoinPaymentService) *MatchRefundWorker {
	return &MatchRefundWorker{db: db, paySvc: paySvc}
}

// HandleRefundRetry — retries SSLCommerz refund calls for any
// match_join_payments row flagged 'requested' or 'refund_failed'.
// Runs every 5 minutes via the scheduler.
func (w *MatchRefundWorker) HandleRefundRetry(ctx context.Context, _ *asynq.Task) error {
	ok, fail, err := w.paySvc.ProcessPendingRefunds(ctx)
	if err != nil {
		log.Error().Err(err).Msg("refund retry batch failed")
		return err
	}
	if ok > 0 || fail > 0 {
		log.Info().Int("ok", ok).Int("failed", fail).Msg("refund retry batch")
	}
	return nil
}

// HandleAutoCancel — auto-cancels matches that won't fill in time.
//
// CRUCIAL: this only runs BEFORE kickoff, never after. If we auto-cancelled
// post-kickoff, joiners who paid and physically showed up to play would get
// refunded — i.e. they'd play for free.
//
// Auto-cancel triggers when:
//   1. The match's kickoff is within MATCH_AUTO_CANCEL_BUFFER_MINUTES from now
//      (default 30 min — gives joiners + host time to bail and find alternatives)
//   2. Spots filled is below MATCH_AUTO_CANCEL_MIN_FILL_PCT (default 50%)
//   3. Match is still 'open' (host hasn't already cancelled)
//
// Once kickoff time has passed, the match is locked in. Either:
//   - It happened (settlement worker, future plan, will mark it 'completed'
//     and pay the pitch owner)
//   - The host should have explicitly cancelled to refund joiners
//   - Or whoever paid + didn't show forfeits per cancellation policy
//
// We deliberately do NOT touch matches with match_date <= NOW(): those are
// settlement territory.
func (w *MatchRefundWorker) HandleAutoCancel(ctx context.Context, _ *asynq.Task) error {
	cfg := config.LoadMatchConfig()
	now := time.Now()

	// Piggyback on this 5-min cron: clear out abandoned checkout sessions
	// so users can retry without hitting "you have a pending payment".
	if expired, err := w.paySvc.ExpireStalePending(ctx); err != nil {
		log.Warn().Err(err).Msg("expire stale pending failed")
	} else if expired > 0 {
		log.Info().Int("expired", expired).Msg("stale pending payments cleared")
	}
	cutoff := now.Add(time.Duration(cfg.AutoCancelBufferMinutes) * time.Minute)
	minFillPct := cfg.AutoCancelMinFillPct
	if minFillPct < 0 || minFillPct > 100 {
		minFillPct = 50
	}

	// Pull candidate matches: still open, kickoff is in the close-future window
	// [now, now + buffer], and underfilled. The fill check uses an integer
	// expression so Postgres can evaluate without floats.
	var ids []struct {
		ID string
	}
	if err := w.db.WithContext(ctx).
		Table("match_posts").
		Select("id").
		Where("status = 'open'").
		Where("match_date > ?", now).
		Where("match_date <= ?", cutoff).
		Where("(spots_filled * 100) < (spots_total * ?)", minFillPct).
		Scan(&ids).Error; err != nil {
		return err
	}
	if len(ids) == 0 {
		return nil
	}
	for _, row := range ids {
		err := w.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
			// Re-check status inside the transaction in case host cancelled
			// concurrently (their action wins; we no-op).
			res := tx.Exec(`
				UPDATE match_posts
				SET status='cancelled', cancelled_at=?, cancellation_reason='auto_cancelled_underfilled', updated_at=?
				WHERE id = ? AND status='open'
			`, now, now, row.ID)
			if res.Error != nil {
				return res.Error
			}
			if res.RowsAffected == 0 {
				return nil // already cancelled by someone else
			}
			return tx.Model(&entity.MatchJoinPayment{}).
				Where("match_post_id = ? AND status = ? AND refund_status IS NULL",
					row.ID, entity.MatchPaymentSuccess).
				Updates(map[string]any{
					"refund_status":       entity.RefundRequested,
					"refund_reason":       entity.RefundReasonAutoCancel,
					"refund_requested_at": now,
					"updated_at":          now,
				}).Error
		})
		if err != nil {
			log.Warn().Err(err).Str("match_post_id", row.ID).Msg("auto-cancel failed")
		}
	}
	log.Info().
		Int("auto_cancelled", len(ids)).
		Int("buffer_min", cfg.AutoCancelBufferMinutes).
		Int("min_fill_pct", minFillPct).
		Msg("match auto-cancel pass (pre-kickoff only)")
	return nil
}

func RegisterMatchRefundHandlers(mux *asynq.ServeMux, w *MatchRefundWorker) {
	mux.HandleFunc(TypeMatchRefundRetry, w.HandleRefundRetry)
	mux.HandleFunc(TypeMatchAutoCancel, w.HandleAutoCancel)
}
