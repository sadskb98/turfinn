// Package worker — SplitDeadlineWorker fires when a pending_split
// booking's 30-minute deadline elapses. If the booking is still in
// pending_split, every paid share is refunded via SSL Refund and the
// booking is cancelled. Booking-level idempotency lives in the service.
package worker

import (
	"context"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/rs/zerolog/log"

	"github.com/turfinn/backend/internal/application/service"
)

type SplitDeadlineWorker struct {
	svc *service.BookingSplitService
}

func NewSplitDeadlineWorker(svc *service.BookingSplitService) *SplitDeadlineWorker {
	return &SplitDeadlineWorker{svc: svc}
}

// Handle reads the booking_id from the task payload and runs the
// expiry. Returns nil for "no-op" cases (booking already confirmed
// or cancelled) so asynq doesn't retry them.
func (w *SplitDeadlineWorker) Handle(ctx context.Context, t *asynq.Task) error {
	bookingID, err := uuid.ParseBytes(t.Payload())
	if err != nil {
		log.Error().Err(err).Bytes("payload", t.Payload()).
			Msg("split deadline: bad payload")
		// Bad payload is non-retryable.
		return nil
	}
	if err := w.svc.HandleDeadlineExpiry(ctx, bookingID); err != nil {
		log.Error().Err(err).Str("booking_id", bookingID.String()).
			Msg("split deadline: handler failed")
		return err
	}
	return nil
}

// RegisterSplitDeadlineHandlers wires the worker into the asynq mux.
func RegisterSplitDeadlineHandlers(mux *asynq.ServeMux, w *SplitDeadlineWorker) {
	mux.HandleFunc(service.TypeSplitDeadline, w.Handle)
}
