// Package service — WeeklySettlementService manages the running per-owner
// payable balance + weekly batched payouts for the Aviv pricing model.
//
// Distinct from SettlementService (which does per-booking tax-aware
// splits via the older PaymentOrder pipeline). This service is the
// simpler "money owed to the turf owner accumulates in
// settlement_accounts; weekly cron drains them" flow that the manager
// panel surfaces.
//
// This service IS the float capture mechanism: faster settlement = less
// float for Turfinn; weekly is the negotiated middle ground.
package service

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/rs/zerolog/log"
	"gorm.io/gorm"
)

type WeeklySettlementService struct {
	db     *gorm.DB
	ledger *LedgerService
}

func NewWeeklySettlementService(db *gorm.DB) *WeeklySettlementService {
	return &WeeklySettlementService{db: db, ledger: NewLedgerService(db)}
}

// CreditOwner bumps a pitch owner's running settlement balance. Called
// from LedgerService.RecordBookingPayment whenever a pitch_owner credit
// row is inserted. Idempotent: tx is required so the ledger insert and
// the balance bump commit/rollback together.
func (s *WeeklySettlementService) CreditOwner(
	tx *gorm.DB,
	ownerID uuid.UUID,
	amountPaisa int64,
) error {
	if amountPaisa <= 0 || ownerID == uuid.Nil {
		return nil
	}
	return tx.Exec(`
		INSERT INTO settlement_accounts (owner_id, balance_paisa, created_at, updated_at)
		VALUES (?, ?, now(), now())
		ON CONFLICT (owner_id) DO UPDATE
		SET balance_paisa = settlement_accounts.balance_paisa + EXCLUDED.balance_paisa,
		    updated_at = now()
	`, ownerID, amountPaisa).Error
}

// RunWeekly drains every owner's positive settlement balance into ledger
// payout rows. Idempotent — re-running on a balance that's already been
// settled does nothing because we lock + reread inside the transaction.
//
// Real disbursement to bKash/bank is a manual export step until the
// disbursement APIs are integrated; this method only handles the ledger
// + balance accounting.
func (s *WeeklySettlementService) RunWeekly(ctx context.Context) (paid, skipped int, err error) {
	var rows []struct {
		ID           uuid.UUID
		OwnerID      uuid.UUID
		BalancePaisa int64
	}
	err = s.db.WithContext(ctx).Raw(`
		SELECT id, owner_id, balance_paisa
		  FROM settlement_accounts
		 WHERE balance_paisa > 0
	`).Scan(&rows).Error
	if err != nil {
		return 0, 0, err
	}
	now := time.Now()
	for _, r := range rows {
		txErr := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
			// Reread under lock — guards against a concurrent CreditOwner
			// landing while we iterate.
			var fresh struct {
				BalancePaisa int64
			}
			if err := tx.Raw(`
				SELECT balance_paisa FROM settlement_accounts
				 WHERE id = ? FOR UPDATE
			`, r.ID).Scan(&fresh).Error; err != nil {
				return err
			}
			if fresh.BalancePaisa <= 0 {
				return nil
			}
			// pitch_owner debit / cash credit — we're paying the owner
			// from our merchant cash. Counterparty stays on cash until
			// disbursement APIs mark it as an outbound transfer.
			if err := s.ledger.Record(ctx, tx, "settlement_payout",
				AcctPitchOwner, AcctCash, fresh.BalancePaisa,
				"SETTLE-"+r.ID.String(), "settlement_account", r.ID,
				"Weekly owner settlement"); err != nil {
				return fmt.Errorf("ledger record settlement: %w", err)
			}
			if err := tx.Exec(`
				UPDATE settlement_accounts
				   SET balance_paisa = balance_paisa - ?,
				       last_settled_at = ?,
				       updated_at = ?
				 WHERE id = ?
			`, fresh.BalancePaisa, now, now, r.ID).Error; err != nil {
				return err
			}
			return nil
		})
		if txErr != nil {
			log.Warn().Err(txErr).Str("settlement_account", r.ID.String()).
				Msg("settlement payout failed")
			skipped++
			continue
		}
		paid++
	}
	if paid > 0 || skipped > 0 {
		log.Info().Int("paid", paid).Int("skipped", skipped).
			Msg("weekly settlement run complete")
	}
	return paid, skipped, nil
}
