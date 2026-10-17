package service

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/interfaces/dto"
	"gorm.io/gorm"
)

// Sentinel errors for payout operations.
var (
	ErrKYCNotApproved       = errors.New("KYC not approved")
	ErrPayoutMethodNotFound = errors.New("payout method not found or not verified")
	ErrBelowMinThreshold    = errors.New("amount is below minimum payout threshold")
	ErrPayoutAlreadyPending = errors.New("a payout is already in progress")
	ErrPayoutMethodInUse    = errors.New("payout method has in-flight payout requests")
)

// PayoutService handles payout method management and payout request creation.
type PayoutService struct {
	db        *gorm.DB
	walletSvc *LedgerWalletService
}

// NewPayoutService constructs a PayoutService.
func NewPayoutService(db *gorm.DB, walletSvc *LedgerWalletService) *PayoutService {
	return &PayoutService{db: db, walletSvc: walletSvc}
}

// AddPayoutMethod inserts a new payout method for the manager (unverified by default).
func (s *PayoutService) AddPayoutMethod(ctx context.Context, managerID uuid.UUID, req dto.AddPayoutMethodRequest) (*entity.PayoutMethod, error) {
	method := &entity.PayoutMethod{
		ManagerID:     managerID,
		MethodType:    req.MethodType,
		AccountNumber: req.AccountNumber,
		AccountName:   strPtr(req.AccountName),
		BankName:      strPtr(req.BankName),
		RoutingNumber: strPtr(req.RoutingNumber),
		IsVerified:    false,
	}
	if err := s.db.WithContext(ctx).Create(method).Error; err != nil {
		return nil, fmt.Errorf("payout: create payout method: %w", err)
	}
	return method, nil
}

// ListPayoutMethods returns all payout methods for a manager, newest first.
func (s *PayoutService) ListPayoutMethods(ctx context.Context, managerID uuid.UUID) ([]entity.PayoutMethod, error) {
	var methods []entity.PayoutMethod
	if err := s.db.WithContext(ctx).
		Where("manager_id = ?", managerID).
		Order("created_at DESC").
		Find(&methods).Error; err != nil {
		return nil, fmt.Errorf("payout: list payout methods: %w", err)
	}
	return methods, nil
}

// DeletePayoutMethod removes a payout method owned by the given manager.
func (s *PayoutService) DeletePayoutMethod(ctx context.Context, managerID, methodID uuid.UUID) error {
	// Guard: reject delete if any in-flight payout requests reference this method.
	var refCount int64
	if err := s.db.WithContext(ctx).Session(&gorm.Session{}).
		Model(&entity.PayoutRequest{}).
		Where("payout_method_id = ? AND status IN ?", methodID,
			[]string{entity.PayoutStatusPending, entity.PayoutStatusApproved, entity.PayoutStatusProcessing}).
		Count(&refCount).Error; err != nil {
		return fmt.Errorf("payout: check method references: %w", err)
	}
	if refCount > 0 {
		return ErrPayoutMethodInUse
	}

	result := s.db.WithContext(ctx).
		Where("id = ? AND manager_id = ?", methodID, managerID).
		Delete(&entity.PayoutMethod{})
	if result.Error != nil {
		return fmt.Errorf("payout: delete payout method: %w", result.Error)
	}
	if result.RowsAffected == 0 {
		return ErrPayoutMethodNotFound
	}
	return nil
}

// RequestPayout validates eligibility and creates a payout request, deducting
// the amount from the manager's available balance as a hold.
func (s *PayoutService) RequestPayout(ctx context.Context, managerID uuid.UUID, req dto.RequestPayoutRequest) (*entity.PayoutRequest, error) {
	methodID, err := uuid.Parse(req.PayoutMethodID)
	if err != nil {
		return nil, fmt.Errorf("payout: invalid payout_method_id: %w", err)
	}

	// 1. KYC check — manager_kyc must have status='approved'.
	var kyc entity.ManagerKYC
	if err := s.db.WithContext(ctx).
		Where("user_id = ? AND status = ?", managerID, "approved").
		First(&kyc).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrKYCNotApproved
		}
		return nil, fmt.Errorf("payout: check KYC: %w", err)
	}

	// 2. Load verified payout method owned by this manager.
	var method entity.PayoutMethod
	if err := s.db.WithContext(ctx).
		Where("id = ? AND manager_id = ? AND is_verified = ?", methodID, managerID, true).
		First(&method).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrPayoutMethodNotFound
		}
		return nil, fmt.Errorf("payout: load payout method: %w", err)
	}

	// 3. Fee config — get payout_min_threshold_paisa (manager-specific or global).
	var feeCfg entity.PartnerFeeConfig
	err = s.db.WithContext(ctx).
		Where("manager_id = ? AND (valid_to IS NULL OR valid_to >= CURRENT_DATE)", managerID).
		Order("valid_from DESC").
		Limit(1).
		First(&feeCfg).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		// Fallback: global default (manager_id IS NULL).
		if err2 := s.db.WithContext(ctx).
			Where("manager_id IS NULL").
			Order("valid_from DESC").
			Limit(1).
			First(&feeCfg).Error; err2 != nil {
			return nil, fmt.Errorf("payout: load fee config: %w", err2)
		}
	} else if err != nil {
		return nil, fmt.Errorf("payout: load fee config: %w", err)
	}

	if req.AmountPaisa < feeCfg.PayoutMinThresholdPaisa {
		return nil, ErrBelowMinThreshold
	}

	// 4. Optimistic fast-path: check no pending payout is already in progress.
	// This is a best-effort check outside the transaction to fail fast for obvious
	// duplicates. The definitive guard is re-checked inside the transaction below.
	var pendingCount int64
	if err := s.db.WithContext(ctx).Session(&gorm.Session{}).
		Model(&entity.PayoutRequest{}).
		Where("manager_id = ? AND status IN ?", managerID, []string{
			entity.PayoutStatusPending,
			entity.PayoutStatusApproved,
			entity.PayoutStatusProcessing,
		}).
		Count(&pendingCount).Error; err != nil {
		return nil, fmt.Errorf("payout: check pending payouts: %w", err)
	}
	if pendingCount > 0 {
		return nil, ErrPayoutAlreadyPending
	}

	// 5. Check available balance.
	var wallet entity.ManagerWallet
	if err := s.db.WithContext(ctx).
		Where("manager_id = ?", managerID).
		First(&wallet).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrInsufficientLedgerBalance
		}
		return nil, fmt.Errorf("payout: load manager wallet: %w", err)
	}
	if req.AmountPaisa > wallet.AvailableBalancePaisa {
		return nil, ErrInsufficientLedgerBalance
	}

	// Transaction: withdraw from wallet and insert payout request.
	var payoutReq entity.PayoutRequest
	txErr := s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Lock wallet and get/create it inside the transaction.
		w, err := s.walletSvc.GetOrCreateManagerWallet(ctx, tx, managerID)
		if err != nil {
			return fmt.Errorf("payout: get/create manager wallet in tx: %w", err)
		}

		// Definitive pending check inside the transaction lock — guards against
		// concurrent payout requests that passed the optimistic check simultaneously.
		var pendingCountTx int64
		if err := tx.WithContext(ctx).Session(&gorm.Session{}).
			Model(&entity.PayoutRequest{}).
			Where("manager_id = ? AND status IN ?", managerID,
				[]string{entity.PayoutStatusPending, entity.PayoutStatusApproved, entity.PayoutStatusProcessing}).
			Count(&pendingCountTx).Error; err != nil {
			return fmt.Errorf("payout: check pending (tx): %w", err)
		}
		if pendingCountTx > 0 {
			return ErrPayoutAlreadyPending
		}

		// Pre-generate the payout request ID so it can be passed as refID to
		// WithdrawManager, linking the wallet transaction back to the payout request.
		payoutReq = entity.PayoutRequest{
			ID:             uuid.New(),
			ManagerID:      managerID,
			PayoutMethodID: methodID,
			AmountPaisa:    req.AmountPaisa,
			Status:         entity.PayoutStatusPending,
		}

		if err := s.walletSvc.WithdrawManager(ctx, tx, w.ID, req.AmountPaisa,
			"payout_hold", "payout_request", &payoutReq.ID, "payout hold"); err != nil {
			return err
		}

		if err := tx.WithContext(ctx).Create(&payoutReq).Error; err != nil {
			return fmt.Errorf("payout: insert payout request: %w", err)
		}
		return nil
	})
	if txErr != nil {
		return nil, txErr
	}

	return &payoutReq, nil
}

// ListPayouts returns a paginated list of payout requests for a manager.
func (s *PayoutService) ListPayouts(ctx context.Context, managerID uuid.UUID, page, limit int) ([]entity.PayoutRequest, int64, error) {
	var total int64
	q := s.db.WithContext(ctx).Model(&entity.PayoutRequest{}).Where("manager_id = ?", managerID)

	if err := q.Session(&gorm.Session{}).Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("payout: count payout requests: %w", err)
	}

	var requests []entity.PayoutRequest
	offset := (page - 1) * limit
	if err := q.Session(&gorm.Session{}).
		Order("created_at DESC").
		Offset(offset).
		Limit(limit).
		Find(&requests).Error; err != nil {
		return nil, 0, fmt.Errorf("payout: list payout requests: %w", err)
	}

	return requests, total, nil
}
