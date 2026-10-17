package entity

import (
	"time"

	"github.com/google/uuid"
)

// ManagerWallet holds two buckets: funds available for payout and funds still
// in the hold window (pending_balance_paisa).
type ManagerWallet struct {
	ID                     uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	ManagerID              uuid.UUID `gorm:"type:uuid;uniqueIndex;not null"`
	AvailableBalancePaisa  int64     `gorm:"column:available_balance_paisa;not null;default:0"`
	PendingBalancePaisa    int64     `gorm:"column:pending_balance_paisa;not null;default:0"`
	CreatedAt              time.Time
	UpdatedAt              time.Time
}

// ManagerWalletTransaction records every credit/debit on a manager's wallet.
type ManagerWalletTransaction struct {
	ID            uuid.UUID  `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	WalletID      uuid.UUID  `gorm:"type:uuid;index;not null"`
	AmountPaisa   int64      `gorm:"column:amount_paisa;not null"`
	TxType        *string    `gorm:"column:tx_type;type:varchar(30)"`
	ReferenceType *string    `gorm:"column:reference_type;type:varchar(30)"`
	ReferenceID   *uuid.UUID `gorm:"column:reference_id;type:uuid"`
	Description   *string    `gorm:"column:description;type:text"`
	CreatedAt     time.Time
}

// PlatformWallet is a singleton that accumulates Turfinn's revenue share.
// Only one row exists: name = 'turfinn_main'.
type PlatformWallet struct {
	ID           uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	Name         string    `gorm:"column:name;type:varchar(50);uniqueIndex;not null;default:'turfinn_main'"`
	BalancePaisa int64     `gorm:"column:balance_paisa;not null;default:0"`
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

// PlatformWalletTransaction records every movement in the platform wallet.
type PlatformWalletTransaction struct {
	ID            uuid.UUID  `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	WalletID      uuid.UUID  `gorm:"type:uuid;index;not null"`
	AmountPaisa   int64      `gorm:"column:amount_paisa;not null"`
	TxType        *string    `gorm:"column:tx_type;type:varchar(30)"`
	ReferenceType *string    `gorm:"column:reference_type;type:varchar(30)"`
	ReferenceID   *uuid.UUID `gorm:"column:reference_id;type:uuid"`
	Description   *string    `gorm:"column:description;type:text"`
	CreatedAt     time.Time
}
