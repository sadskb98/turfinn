package service

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// ErrInsufficientLedgerBalance is returned when a ledger wallet withdrawal would
// make the balance negative.
var ErrInsufficientLedgerBalance = errors.New("insufficient available balance")

type LedgerWalletService struct {
	db *gorm.DB
}

func NewLedgerWalletService(db *gorm.DB) *LedgerWalletService {
	return &LedgerWalletService{db: db}
}

// GetOrCreateManagerWallet fetches the manager wallet inside the given transaction,
// using SELECT FOR UPDATE to prevent concurrent mutations. If no wallet exists yet
// one is created with zero balances.
//
// TOCTOU safety: if two goroutines both observe ErrRecordNotFound and race to
// INSERT, ON CONFLICT DO NOTHING ensures only one row lands. The subsequent
// SELECT FOR UPDATE then fetches whichever row won the race.
func (s *LedgerWalletService) GetOrCreateManagerWallet(ctx context.Context, tx *gorm.DB, managerID uuid.UUID) (*entity.ManagerWallet, error) {
	var wallet entity.ManagerWallet
	err := tx.WithContext(ctx).
		Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("manager_id = ?", managerID).
		First(&wallet).Error
	if err == nil {
		return &wallet, nil
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, fmt.Errorf("ledger: lock manager wallet for manager %s: %w", managerID, err)
	}

	// No wallet yet — insert with conflict guard so concurrent callers don't race.
	wallet = entity.ManagerWallet{ManagerID: managerID}
	if err := tx.WithContext(ctx).
		Clauses(clause.OnConflict{DoNothing: true}).
		Create(&wallet).Error; err != nil {
		return nil, fmt.Errorf("ledger: create manager wallet: %w", err)
	}
	// Re-fetch with lock — another transaction may have won the INSERT race.
	if err := tx.WithContext(ctx).
		Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("manager_id = ?", managerID).
		First(&wallet).Error; err != nil {
		return nil, fmt.Errorf("ledger: re-fetch manager wallet after create: %w", err)
	}
	return &wallet, nil
}

// DepositManager credits amountPaisa to available_balance_paisa on the manager wallet
// identified by walletID and records a transaction row.
func (s *LedgerWalletService) DepositManager(ctx context.Context, tx *gorm.DB, walletID uuid.UUID, amountPaisa int64, txType, refType string, refID *uuid.UUID, desc string) error {
	if amountPaisa <= 0 {
		return fmt.Errorf("ledger: amountPaisa must be positive, got %d", amountPaisa)
	}

	// SELECT FOR UPDATE serialises concurrent deposits/withdrawals on this wallet
	// within the same transaction batch.
	if err := tx.WithContext(ctx).
		Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("id = ?", walletID).
		First(&entity.ManagerWallet{}).Error; err != nil {
		return fmt.Errorf("ledger: lock manager wallet %s: %w", walletID, err)
	}

	if err := tx.WithContext(ctx).
		Model(&entity.ManagerWallet{}).
		Where("id = ?", walletID).
		Update("available_balance_paisa", gorm.Expr("available_balance_paisa + ?", amountPaisa)).Error; err != nil {
		return fmt.Errorf("ledger: update available balance: %w", err)
	}

	if err := tx.WithContext(ctx).Create(&entity.ManagerWalletTransaction{
		WalletID:      walletID,
		AmountPaisa:   amountPaisa,
		TxType:        strPtr(txType),
		ReferenceType: strPtr(refType),
		ReferenceID:   refID,
		Description:   strPtr(desc),
	}).Error; err != nil {
		return fmt.Errorf("ledger: insert manager wallet tx: %w", err)
	}
	return nil
}

// DepositManagerPending credits amountPaisa to pending_balance_paisa on the manager
// wallet identified by walletID and records a transaction row.
func (s *LedgerWalletService) DepositManagerPending(ctx context.Context, tx *gorm.DB, walletID uuid.UUID, amountPaisa int64, txType, refType string, refID *uuid.UUID, desc string) error {
	if amountPaisa <= 0 {
		return fmt.Errorf("ledger: amountPaisa must be positive, got %d", amountPaisa)
	}

	// SELECT FOR UPDATE serialises concurrent deposits/withdrawals on this wallet
	// within the same transaction batch.
	if err := tx.WithContext(ctx).
		Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("id = ?", walletID).
		First(&entity.ManagerWallet{}).Error; err != nil {
		return fmt.Errorf("ledger: lock manager wallet %s: %w", walletID, err)
	}

	if err := tx.WithContext(ctx).
		Model(&entity.ManagerWallet{}).
		Where("id = ?", walletID).
		Update("pending_balance_paisa", gorm.Expr("pending_balance_paisa + ?", amountPaisa)).Error; err != nil {
		return fmt.Errorf("ledger: update pending balance: %w", err)
	}

	if err := tx.WithContext(ctx).Create(&entity.ManagerWalletTransaction{
		WalletID:      walletID,
		AmountPaisa:   amountPaisa,
		TxType:        strPtr(txType),
		ReferenceType: strPtr(refType),
		ReferenceID:   refID,
		Description:   strPtr(desc),
	}).Error; err != nil {
		return fmt.Errorf("ledger: insert manager wallet tx: %w", err)
	}
	return nil
}

// WithdrawManager debits amountPaisa from available_balance_paisa on the manager wallet
// identified by walletID. Returns ErrInsufficientLedgerBalance when the balance is too low.
func (s *LedgerWalletService) WithdrawManager(ctx context.Context, tx *gorm.DB, walletID uuid.UUID, amountPaisa int64, txType, refType string, refID *uuid.UUID, desc string) error {
	if amountPaisa <= 0 {
		return fmt.Errorf("ledger: amountPaisa must be positive, got %d", amountPaisa)
	}

	var wallet entity.ManagerWallet
	if err := tx.WithContext(ctx).
		Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("id = ?", walletID).
		First(&wallet).Error; err != nil {
		return fmt.Errorf("ledger: lock manager wallet %s: %w", walletID, err)
	}

	if wallet.AvailableBalancePaisa < amountPaisa {
		return ErrInsufficientLedgerBalance
	}

	if err := tx.WithContext(ctx).
		Model(&entity.ManagerWallet{}).
		Where("id = ?", walletID).
		Update("available_balance_paisa", gorm.Expr("available_balance_paisa - ?", amountPaisa)).Error; err != nil {
		return fmt.Errorf("ledger: update available balance: %w", err)
	}

	if err := tx.WithContext(ctx).Create(&entity.ManagerWalletTransaction{
		WalletID:      walletID,
		AmountPaisa:   -amountPaisa,
		TxType:        strPtr(txType),
		ReferenceType: strPtr(refType),
		ReferenceID:   refID,
		Description:   strPtr(desc),
	}).Error; err != nil {
		return fmt.Errorf("ledger: insert manager wallet tx: %w", err)
	}
	return nil
}

// DepositPlatform credits amountPaisa to the 'turfinn_main' platform wallet and
// records a transaction row.
func (s *LedgerWalletService) DepositPlatform(ctx context.Context, tx *gorm.DB, amountPaisa int64, txType, refType string, refID *uuid.UUID, desc string) error {
	if amountPaisa <= 0 {
		return fmt.Errorf("ledger: amountPaisa must be positive, got %d", amountPaisa)
	}

	var wallet entity.PlatformWallet
	if err := tx.WithContext(ctx).
		Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("name = ?", "turfinn_main").
		First(&wallet).Error; err != nil {
		return fmt.Errorf("ledger: lock platform wallet: %w", err)
	}

	if err := tx.WithContext(ctx).
		Model(&entity.PlatformWallet{}).
		Where("id = ?", wallet.ID).
		Update("balance_paisa", gorm.Expr("balance_paisa + ?", amountPaisa)).Error; err != nil {
		return fmt.Errorf("ledger: update platform wallet balance: %w", err)
	}

	if err := tx.WithContext(ctx).Create(&entity.PlatformWalletTransaction{
		WalletID:      wallet.ID,
		AmountPaisa:   amountPaisa,
		TxType:        strPtr(txType),
		ReferenceType: strPtr(refType),
		ReferenceID:   refID,
		Description:   strPtr(desc),
	}).Error; err != nil {
		return fmt.Errorf("ledger: insert platform wallet tx: %w", err)
	}
	return nil
}

// WithdrawPlatform debits amountPaisa from the 'turfinn_main' platform wallet.
// Returns ErrInsufficientLedgerBalance when the balance is too low.
func (s *LedgerWalletService) WithdrawPlatform(ctx context.Context, tx *gorm.DB, amountPaisa int64, txType, refType string, refID *uuid.UUID, desc string) error {
	if amountPaisa <= 0 {
		return fmt.Errorf("ledger: amountPaisa must be positive, got %d", amountPaisa)
	}

	var wallet entity.PlatformWallet
	if err := tx.WithContext(ctx).
		Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("name = ?", "turfinn_main").
		First(&wallet).Error; err != nil {
		return fmt.Errorf("ledger: lock platform wallet: %w", err)
	}

	if wallet.BalancePaisa < amountPaisa {
		return ErrInsufficientLedgerBalance
	}

	if err := tx.WithContext(ctx).
		Model(&entity.PlatformWallet{}).
		Where("id = ?", wallet.ID).
		Update("balance_paisa", gorm.Expr("balance_paisa - ?", amountPaisa)).Error; err != nil {
		return fmt.Errorf("ledger: update platform wallet balance: %w", err)
	}

	if err := tx.WithContext(ctx).Create(&entity.PlatformWalletTransaction{
		WalletID:      wallet.ID,
		AmountPaisa:   -amountPaisa,
		TxType:        strPtr(txType),
		ReferenceType: strPtr(refType),
		ReferenceID:   refID,
		Description:   strPtr(desc),
	}).Error; err != nil {
		return fmt.Errorf("ledger: insert platform wallet tx: %w", err)
	}
	return nil
}
