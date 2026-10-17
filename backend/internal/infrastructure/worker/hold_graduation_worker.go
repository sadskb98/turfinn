package worker

import (
	"context"
	"time"

	"github.com/hibiken/asynq"
	"github.com/rs/zerolog/log"
	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/domain/entity"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// TypeHoldGraduation is the local alias for the task type constant.
const TypeHoldGraduation = service.TypeHoldGraduation

// HoldGraduationWorker graduates pending manager wallet funds whose hold
// period has expired, moving them from pending to available.
type HoldGraduationWorker struct {
	db *gorm.DB
}

// NewHoldGraduationWorker constructs a HoldGraduationWorker.
func NewHoldGraduationWorker(db *gorm.DB) *HoldGraduationWorker {
	return &HoldGraduationWorker{db: db}
}

// Handle is the asynq task handler for TypeHoldGraduation.
// It finds all ungraduated settlements whose hold window has elapsed and moves
// the owner payout from pending to available in the manager's wallet.
// Each settlement is processed in its own transaction so a single failure does
// not prevent the remaining settlements from being processed.
func (w *HoldGraduationWorker) Handle(ctx context.Context, _ *asynq.Task) error {
	var settlements []entity.BookingSettlement
	err := w.db.WithContext(ctx).
		Where("graduated = false AND settled_at IS NOT NULL AND settled_at + (hold_days * INTERVAL '1 day') <= NOW()").
		Find(&settlements).Error
	if err != nil {
		log.Error().Err(err).Msg("hold_graduation: failed to query settlements")
		return err
	}

	graduated := 0
	for _, s := range settlements {
		settlement := s // capture range variable
		txErr := w.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
			// Resolve the manager (pitch owner) for this booking.
			var managerID string
			if err := tx.Raw(
				`SELECT p.owner_id FROM pitches p JOIN bookings b ON b.pitch_id = p.id WHERE b.id = ?`,
				settlement.BookingID,
			).Scan(&managerID).Error; err != nil {
				return err
			}

			// Lock the wallet row for this manager (upsert if not yet created).
			var wallet entity.ManagerWallet
			if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
				Where("manager_id = ?", managerID).
				First(&wallet).Error; err != nil {
				return err
			}

			// Move funds from pending to available.
			if err := tx.Model(&wallet).Updates(map[string]any{
				"pending_balance_paisa":   wallet.PendingBalancePaisa - settlement.OwnerPayoutPaisa,
				"available_balance_paisa": wallet.AvailableBalancePaisa + settlement.OwnerPayoutPaisa,
			}).Error; err != nil {
				return err
			}

			// Mark the settlement as graduated.
			now := time.Now()
			if err := tx.Model(&settlement).Updates(map[string]any{
				"graduated":    true,
				"graduated_at": now,
			}).Error; err != nil {
				return err
			}

			return nil
		})

		if txErr != nil {
			log.Error().Err(txErr).
				Str("settlement_id", settlement.ID.String()).
				Msg("hold_graduation: failed to graduate settlement, skipping")
			continue
		}
		graduated++
	}

	log.Info().Int("graduated", graduated).Int("total", len(settlements)).
		Msg("hold_graduation: completed")

	// Always return nil — per-settlement errors are logged above. Returning an
	// error here would cause asynq to retry the whole batch, which risks
	// double-graduating already-processed settlements.
	return nil
}
