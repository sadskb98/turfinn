package entity

import (
	"time"

	"github.com/google/uuid"
)

// Payout status constants.
const (
	PayoutStatusPending    = "pending"
	PayoutStatusApproved   = "approved"
	PayoutStatusProcessing = "processing"
	PayoutStatusCompleted  = "completed"
	PayoutStatusRejected   = "rejected"
)

// ManagerReceivable status constants.
const (
	ReceivableStatusOutstanding = "outstanding"
	ReceivableStatusPaid        = "paid"
)

// PayoutMethod stores a manager's bank account or mobile-money account details.
type PayoutMethod struct {
	ID            uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	ManagerID     uuid.UUID `gorm:"type:uuid;index;not null"`
	MethodType    string    `gorm:"column:method_type;type:varchar(20);not null"`
	AccountNumber string    `gorm:"column:account_number;type:varchar(100);not null"`
	AccountName   *string   `gorm:"column:account_name;type:varchar(200)"`
	BankName      *string   `gorm:"column:bank_name;type:varchar(100)"`
	RoutingNumber *string   `gorm:"column:routing_number;type:varchar(50)"`
	IsVerified    bool      `gorm:"column:is_verified;not null;default:false"`
	CreatedAt     time.Time
	UpdatedAt     time.Time
}

// PayoutRequest is raised by a manager to withdraw their available balance.
type PayoutRequest struct {
	ID                uuid.UUID  `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	ManagerID         uuid.UUID  `gorm:"type:uuid;index;not null"`
	PayoutMethodID    uuid.UUID  `gorm:"type:uuid;not null"`
	AmountPaisa       int64      `gorm:"column:amount_paisa;not null"`
	Status            string     `gorm:"column:status;type:varchar(20);not null;default:'pending'"`
	TransferReference *string    `gorm:"column:transfer_reference;type:varchar(200)"`
	RejectionReason   *string    `gorm:"column:rejection_reason;type:text"`
	ProcessedAt       *time.Time `gorm:"column:processed_at"`
	CompletedAt       *time.Time `gorm:"column:completed_at"`
	CreatedAt         time.Time
}

// Refund tracks a gateway or wallet refund tied to a specific booking and
// payment order.
type Refund struct {
	ID             uuid.UUID  `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	BookingID      uuid.UUID  `gorm:"type:uuid;index;not null"`
	PaymentOrderID uuid.UUID  `gorm:"type:uuid;index;not null"`
	AmountPaisa    int64      `gorm:"column:amount_paisa;not null"`
	Reason         string     `gorm:"column:reason;type:text"`
	Status         string     `gorm:"column:status;type:varchar(20);not null;default:'pending'"`
	ProcessedAt    *time.Time `gorm:"column:processed_at"`
	CreatedAt      time.Time
}

// ManagerReceivable tracks what the platform owes a manager for a settled
// booking. Linked to a PayoutRequest once the obligation is paid out.
type ManagerReceivable struct {
	ID                uuid.UUID  `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	ManagerID         uuid.UUID  `gorm:"type:uuid;index;not null"`
	SettlementID      uuid.UUID  `gorm:"type:uuid;uniqueIndex;not null"`
	AmountPaisa       int64      `gorm:"column:amount_paisa;not null"`
	Status            string     `gorm:"column:status;type:varchar(20);not null;default:'outstanding'"`
	PaidViaPayoutID   *uuid.UUID `gorm:"type:uuid;column:paid_via_payout_id"`
	CreatedAt         time.Time
	UpdatedAt         time.Time
}

// GatewayFeeReconciliation records the difference between the fee charged to
// the customer and the fee actually billed by the gateway for a settlement.
// diff_paisa is a GENERATED column in Postgres (actual - charged).
type GatewayFeeReconciliation struct {
	ID           uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	SettlementID uuid.UUID `gorm:"type:uuid;uniqueIndex;not null"`
	ChargedPaisa int64     `gorm:"column:charged_paisa;not null"`
	ActualPaisa  int64     `gorm:"column:actual_paisa;not null"`
	DiffPaisa    int64     `gorm:"column:diff_paisa;->;-:migration"` // read-only; GENERATED ALWAYS in DB
	CreatedAt    time.Time
}
