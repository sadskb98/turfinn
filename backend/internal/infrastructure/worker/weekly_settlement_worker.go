// Package worker — WeeklySettlementWorker drains every owner's running
// settlement balance into ledger payout rows. Real money movement
// (bKash B2C / bank ACH) is a manual export step until disbursement
// APIs are integrated; this worker handles the accounting side.
//
// Cron-driven: registered at 02:00 UTC every Monday (08:00 BDT) so
// payouts land before owners start their week.
//
// Suppressed silent imports (config) — we don't read tier config here;
// the service does.
package worker

import (
	"context"

	"github.com/hibiken/asynq"
	"github.com/rs/zerolog/log"

	"github.com/turfinn/backend/internal/application/service"
)

const (
	TypeSettlementWeekly = "settlement:weekly_payout"
)

type WeeklySettlementWorker struct {
	svc *service.WeeklySettlementService
}

func NewWeeklySettlementWorker(svc *service.WeeklySettlementService) *WeeklySettlementWorker {
	return &WeeklySettlementWorker{svc: svc}
}

// Handle is the asynq entry point. Idempotent + safe to retry.
func (w *WeeklySettlementWorker) Handle(ctx context.Context, _ *asynq.Task) error {
	paid, skipped, err := w.svc.RunWeekly(ctx)
	if err != nil {
		log.Error().Err(err).Msg("weekly settlement run failed")
		return err
	}
	log.Info().Int("paid", paid).Int("skipped", skipped).
		Msg("weekly settlement run done")
	return nil
}

// RegisterWeeklySettlementHandlers wires the worker into the asynq mux.
func RegisterWeeklySettlementHandlers(mux *asynq.ServeMux, w *WeeklySettlementWorker) {
	mux.HandleFunc(TypeSettlementWeekly, w.Handle)
}
