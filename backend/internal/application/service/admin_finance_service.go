package service

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/interfaces/dto"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// Sentinel errors for admin finance operations.
var (
	ErrPayoutNotFound         = errors.New("payout request not found")
	ErrInvalidStateTransition = errors.New("invalid payout state transition")
	ErrFeeConfigNotFound      = errors.New("fee config not found")
	ErrInvalidFeeConfigInput  = errors.New("invalid fee config input")
)

// AdminFinanceService handles admin-side payout state machine and fee config CRUD.
type AdminFinanceService struct {
	db        *gorm.DB
	walletSvc *LedgerWalletService
}

// NewAdminFinanceService constructs an AdminFinanceService.
func NewAdminFinanceService(db *gorm.DB, walletSvc *LedgerWalletService) *AdminFinanceService {
	return &AdminFinanceService{db: db, walletSvc: walletSvc}
}

// ApprovePayout transitions a payout request from pending → approved.
// Uses a single conditional UPDATE to avoid TOCTOU races between concurrent admins.
func (s *AdminFinanceService) ApprovePayout(ctx context.Context, payoutID uuid.UUID) (*entity.PayoutRequest, error) {
	now := time.Now()
	result := s.db.WithContext(ctx).
		Model(&entity.PayoutRequest{}).
		Where("id = ? AND status = ?", payoutID, entity.PayoutStatusPending).
		Updates(map[string]any{
			"status":       entity.PayoutStatusApproved,
			"processed_at": &now,
		})
	if result.Error != nil {
		return nil, fmt.Errorf("admin_finance: approve payout: %w", result.Error)
	}
	if result.RowsAffected == 0 {
		// Could be not found OR wrong state — load to distinguish.
		var pr entity.PayoutRequest
		if err := s.db.WithContext(ctx).First(&pr, "id = ?", payoutID).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return nil, ErrPayoutNotFound
			}
			return nil, fmt.Errorf("admin_finance: approve payout reload: %w", err)
		}
		return nil, ErrInvalidStateTransition
	}
	var pr entity.PayoutRequest
	if err := s.db.WithContext(ctx).First(&pr, "id = ?", payoutID).Error; err != nil {
		return nil, fmt.Errorf("admin_finance: approve payout reload: %w", err)
	}
	return &pr, nil
}

// ProcessPayout transitions a payout request from approved → processing.
// Uses a single conditional UPDATE to avoid TOCTOU races between concurrent admins.
func (s *AdminFinanceService) ProcessPayout(ctx context.Context, payoutID uuid.UUID) (*entity.PayoutRequest, error) {
	result := s.db.WithContext(ctx).
		Model(&entity.PayoutRequest{}).
		Where("id = ? AND status = ?", payoutID, entity.PayoutStatusApproved).
		Update("status", entity.PayoutStatusProcessing)
	if result.Error != nil {
		return nil, fmt.Errorf("admin_finance: process payout: %w", result.Error)
	}
	if result.RowsAffected == 0 {
		var pr entity.PayoutRequest
		if err := s.db.WithContext(ctx).First(&pr, "id = ?", payoutID).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return nil, ErrPayoutNotFound
			}
			return nil, fmt.Errorf("admin_finance: process payout reload: %w", err)
		}
		return nil, ErrInvalidStateTransition
	}
	var pr entity.PayoutRequest
	if err := s.db.WithContext(ctx).First(&pr, "id = ?", payoutID).Error; err != nil {
		return nil, fmt.Errorf("admin_finance: process payout reload: %w", err)
	}
	return &pr, nil
}

// CompletePayout transitions a payout request from processing → completed and
// records the external transfer reference.
// Uses a single conditional UPDATE to avoid TOCTOU races between concurrent admins.
func (s *AdminFinanceService) CompletePayout(ctx context.Context, payoutID uuid.UUID, transferReference string) (*entity.PayoutRequest, error) {
	now := time.Now()
	result := s.db.WithContext(ctx).
		Model(&entity.PayoutRequest{}).
		Where("id = ? AND status = ?", payoutID, entity.PayoutStatusProcessing).
		Updates(map[string]any{
			"status":             entity.PayoutStatusCompleted,
			"transfer_reference": transferReference,
			"completed_at":       &now,
		})
	if result.Error != nil {
		return nil, fmt.Errorf("admin_finance: complete payout: %w", result.Error)
	}
	if result.RowsAffected == 0 {
		var pr entity.PayoutRequest
		if err := s.db.WithContext(ctx).First(&pr, "id = ?", payoutID).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return nil, ErrPayoutNotFound
			}
			return nil, fmt.Errorf("admin_finance: complete payout reload: %w", err)
		}
		return nil, ErrInvalidStateTransition
	}
	var pr entity.PayoutRequest
	if err := s.db.WithContext(ctx).First(&pr, "id = ?", payoutID).Error; err != nil {
		return nil, fmt.Errorf("admin_finance: complete payout reload: %w", err)
	}
	return &pr, nil
}

// RejectPayout transitions a payout from pending|approved|processing → rejected
// and releases the held balance back to the manager's available balance.
func (s *AdminFinanceService) RejectPayout(ctx context.Context, payoutID uuid.UUID, reason string) (*entity.PayoutRequest, error) {
	var payoutReq entity.PayoutRequest
	txErr := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Load and lock the payout request with SELECT FOR UPDATE to prevent
		// concurrent state transitions from racing with this rejection.
		if err := tx.WithContext(ctx).
			Clauses(clause.Locking{Strength: "UPDATE"}).
			First(&payoutReq, "id = ?", payoutID).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrPayoutNotFound
			}
			return fmt.Errorf("admin_finance: reject payout load: %w", err)
		}

		validStatuses := map[string]bool{
			entity.PayoutStatusPending:    true,
			entity.PayoutStatusApproved:   true,
			entity.PayoutStatusProcessing: true,
		}
		if !validStatuses[payoutReq.Status] {
			return ErrInvalidStateTransition
		}

		// Lock the manager wallet directly — if it doesn't exist the hold was
		// never placed, which indicates data corruption; return an error rather
		// than silently creating a phantom wallet.
		var w entity.ManagerWallet
		if err := tx.WithContext(ctx).
			Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("manager_id = ?", payoutReq.ManagerID).
			First(&w).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return fmt.Errorf("admin_finance: reject payout: manager wallet not found for manager %s", payoutReq.ManagerID)
			}
			return fmt.Errorf("admin_finance: reject payout: lock manager wallet: %w", err)
		}

		// Release the held amount back to the manager's available balance.
		if err := s.walletSvc.DepositManager(
			ctx, tx, w.ID, payoutReq.AmountPaisa,
			"payout_release", "payout_request", &payoutReq.ID,
			"payout hold released on rejection",
		); err != nil {
			return fmt.Errorf("admin_finance: release payout hold: %w", err)
		}

		// Update payout request status.
		now := time.Now()
		if err := tx.WithContext(ctx).
			Model(&payoutReq).
			Updates(map[string]any{
				"status":           entity.PayoutStatusRejected,
				"rejection_reason": reason,
				"processed_at":     now,
			}).Error; err != nil {
			return fmt.Errorf("admin_finance: reject payout: %w", err)
		}
		payoutReq.Status = entity.PayoutStatusRejected
		payoutReq.RejectionReason = &reason
		payoutReq.ProcessedAt = &now
		return nil
	})
	if txErr != nil {
		return nil, txErr
	}
	return &payoutReq, nil
}

// ListAllPayouts returns a paginated list of all payout requests, optionally
// filtered by status.
func (s *AdminFinanceService) ListAllPayouts(ctx context.Context, page, limit int, status string) ([]entity.PayoutRequest, int64, error) {
	q := s.db.WithContext(ctx).Model(&entity.PayoutRequest{})
	if status != "" {
		q = q.Where("status = ?", status)
	}

	var total int64
	if err := q.Session(&gorm.Session{}).Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("admin_finance: count payout requests: %w", err)
	}

	var requests []entity.PayoutRequest
	offset := (page - 1) * limit
	if err := q.Session(&gorm.Session{}).
		Order("created_at DESC").
		Offset(offset).
		Limit(limit).
		Find(&requests).Error; err != nil {
		return nil, 0, fmt.Errorf("admin_finance: list payout requests: %w", err)
	}

	return requests, total, nil
}

// ListFeeConfigs returns all PartnerFeeConfig rows, newest first.
func (s *AdminFinanceService) ListFeeConfigs(ctx context.Context) ([]entity.PartnerFeeConfig, error) {
	var configs []entity.PartnerFeeConfig
	if err := s.db.WithContext(ctx).
		Order("created_at DESC").
		Find(&configs).Error; err != nil {
		return nil, fmt.Errorf("admin_finance: list fee configs: %w", err)
	}
	return configs, nil
}

// CreateFeeConfig inserts a new PartnerFeeConfig row.
func (s *AdminFinanceService) CreateFeeConfig(ctx context.Context, req dto.AdminCreateFeeConfigRequest) (*entity.PartnerFeeConfig, error) {
	cfg := entity.PartnerFeeConfig{
		CommissionBps:           req.CommissionBps,
		PayoutMinThresholdPaisa: req.PayoutMinThresholdPaisa,
		HoldDays:                req.HoldDays,
	}

	if req.ManagerID != nil && *req.ManagerID != "" {
		managerUUID, err := uuid.Parse(*req.ManagerID)
		if err != nil {
			return nil, fmt.Errorf("%w: invalid manager_id: %v", ErrInvalidFeeConfigInput, err)
		}
		cfg.ManagerID = &managerUUID
	}

	if req.ValidFrom != nil && *req.ValidFrom != "" {
		t, err := time.Parse("2006-01-02", *req.ValidFrom)
		if err != nil {
			return nil, fmt.Errorf("%w: invalid valid_from: %v", ErrInvalidFeeConfigInput, err)
		}
		cfg.ValidFrom = &t
	}

	if req.ValidTo != nil && *req.ValidTo != "" {
		t, err := time.Parse("2006-01-02", *req.ValidTo)
		if err != nil {
			return nil, fmt.Errorf("%w: invalid valid_to: %v", ErrInvalidFeeConfigInput, err)
		}
		cfg.ValidTo = &t
	}

	if err := s.db.WithContext(ctx).Create(&cfg).Error; err != nil {
		return nil, fmt.Errorf("admin_finance: create fee config: %w", err)
	}
	return &cfg, nil
}

// UpdateFeeConfig updates non-nil fields on the PartnerFeeConfig identified by id.
// Returns ErrFeeConfigNotFound when no row exists with that id.
func (s *AdminFinanceService) UpdateFeeConfig(ctx context.Context, id uuid.UUID, req dto.AdminUpdateFeeConfigRequest) (*entity.PartnerFeeConfig, error) {
	updates := make(map[string]any)

	if req.CommissionBps != nil {
		updates["commission_bps"] = *req.CommissionBps
	}
	if req.PayoutMinThresholdPaisa != nil {
		updates["payout_min_threshold_paisa"] = *req.PayoutMinThresholdPaisa
	}
	if req.HoldDays != nil {
		updates["hold_days"] = *req.HoldDays
	}
	if req.ValidFrom != nil {
		if *req.ValidFrom == "" {
			updates["valid_from"] = nil
		} else {
			t, err := time.Parse("2006-01-02", *req.ValidFrom)
			if err != nil {
				return nil, fmt.Errorf("admin_finance: invalid valid_from date: %w", err)
			}
			updates["valid_from"] = t
		}
	}
	if req.ValidTo != nil {
		if *req.ValidTo == "" {
			updates["valid_to"] = nil
		} else {
			t, err := time.Parse("2006-01-02", *req.ValidTo)
			if err != nil {
				return nil, fmt.Errorf("admin_finance: invalid valid_to date: %w", err)
			}
			updates["valid_to"] = t
		}
	}

	if len(updates) == 0 {
		// No-op: just return the existing record.
		var cfg entity.PartnerFeeConfig
		if err := s.db.WithContext(ctx).First(&cfg, "id = ?", id).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return nil, ErrFeeConfigNotFound
			}
			return nil, fmt.Errorf("admin_finance: load fee config: %w", err)
		}
		return &cfg, nil
	}

	updates["updated_at"] = gorm.Expr("NOW()")

	result := s.db.WithContext(ctx).
		Model(&entity.PartnerFeeConfig{}).
		Where("id = ?", id).
		Updates(updates)
	if result.Error != nil {
		return nil, fmt.Errorf("admin_finance: update fee config: %w", result.Error)
	}
	if result.RowsAffected == 0 {
		return nil, ErrFeeConfigNotFound
	}

	var cfg entity.PartnerFeeConfig
	if err := s.db.WithContext(ctx).First(&cfg, "id = ?", id).Error; err != nil {
		return nil, fmt.Errorf("admin_finance: reload fee config: %w", err)
	}
	return &cfg, nil
}

// ListGatewayFeeRates returns all GatewayFeeRate rows, ordered by card_type ascending.
func (s *AdminFinanceService) ListGatewayFeeRates(ctx context.Context) ([]entity.GatewayFeeRate, error) {
	var rates []entity.GatewayFeeRate
	if err := s.db.WithContext(ctx).
		Order("card_type ASC").
		Find(&rates).Error; err != nil {
		return nil, fmt.Errorf("admin_finance: list gateway fee rates: %w", err)
	}
	return rates, nil
}

// UpdateGatewayFeeRate upserts a GatewayFeeRate row by card_type.
func (s *AdminFinanceService) UpdateGatewayFeeRate(ctx context.Context, cardType string, feeBps int) (*entity.GatewayFeeRate, error) {
	rate := entity.GatewayFeeRate{
		CardType: cardType,
		FeeBps:   feeBps,
	}

	if err := s.db.WithContext(ctx).
		Clauses(clause.OnConflict{
			Columns:   []clause.Column{{Name: "card_type"}},
			DoUpdates: clause.AssignmentColumns([]string{"fee_bps", "updated_at"}),
		}).
		Create(&rate).Error; err != nil {
		return nil, fmt.Errorf("admin_finance: upsert gateway fee rate: %w", err)
	}

	// Reload to get current state (covers both insert and update paths).
	if err := s.db.WithContext(ctx).
		Where("card_type = ?", cardType).
		First(&rate).Error; err != nil {
		return nil, fmt.Errorf("admin_finance: reload gateway fee rate: %w", err)
	}
	return &rate, nil
}

// CreateGatewayFeeReconciliation inserts a new reconciliation row.
// DiffPaisa is a GENERATED ALWAYS column in Postgres — do not set it.
func (s *AdminFinanceService) CreateGatewayFeeReconciliation(ctx context.Context, req dto.AdminCreateReconciliationRequest) (*entity.GatewayFeeReconciliation, error) {
	settlementID, err := uuid.Parse(req.SettlementID)
	if err != nil {
		return nil, fmt.Errorf("admin_finance: invalid settlement_id: %w", err)
	}

	rec := entity.GatewayFeeReconciliation{
		SettlementID: settlementID,
		ChargedPaisa: req.ChargedPaisa,
		ActualPaisa:  req.ActualPaisa,
	}

	if err := s.db.WithContext(ctx).
		Omit("diff_paisa").
		Create(&rec).Error; err != nil {
		return nil, fmt.Errorf("admin_finance: create reconciliation: %w", err)
	}

	// Reload to get the DB-computed diff_paisa.
	if err := s.db.WithContext(ctx).First(&rec, "id = ?", rec.ID).Error; err != nil {
		return nil, fmt.Errorf("admin_finance: reload reconciliation: %w", err)
	}
	return &rec, nil
}
