package entity

import (
	"time"

	"github.com/google/uuid"
)

// Payment status constants.
const (
	PaymentStatusPending   = "pending"
	PaymentStatusSuccess   = "success"
	PaymentStatusFailed    = "failed"
	PaymentStatusCancelled = "cancelled"
)

// Refund status constants.
const (
	RefundStatusPending   = "pending"
	RefundStatusProcessed = "processed"
	RefundStatusRejected  = "rejected"
)

// PaymentOrder tracks the SSLCommerz payment lifecycle for a single booking.
type PaymentOrder struct {
	ID              uuid.UUID  `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	BookingID       uuid.UUID  `gorm:"type:uuid;index;not null"`
	UserID          uuid.UUID  `gorm:"type:uuid;index;not null"`
	AmountPaisa     int64      `gorm:"column:amount_paisa;not null"`
	Currency        string     `gorm:"column:currency;type:varchar(3);not null;default:'BDT'"`
	Status          string     `gorm:"column:status;type:varchar(20);not null;default:'pending'"`
	TranID          *string    `gorm:"column:tran_id;uniqueIndex"`
	ValID           *string    `gorm:"column:val_id"`
	GatewayResponse *string    `gorm:"column:gateway_response;type:jsonb"`
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

// BookingSettlement is the immutable record of how a payment was split among
// the platform, owner, and gateway. Created once per successful PaymentOrder.
type BookingSettlement struct {
	ID                   uuid.UUID  `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	PaymentOrderID       uuid.UUID  `gorm:"type:uuid;uniqueIndex;not null"`
	BookingID            uuid.UUID  `gorm:"type:uuid;index;not null"`
	TotalPaidPaisa       int64      `gorm:"column:total_paid_paisa;not null"`
	OwnerPayoutPaisa     int64      `gorm:"column:owner_payout_paisa;not null"`
	TurfinnRevenuePaisa  int64      `gorm:"column:turfinn_revenue_paisa;not null"`
	GatewayFeePaisa      int64      `gorm:"column:gateway_fee_paisa;not null"`
	HoldDays             int        `gorm:"column:hold_days;not null;default:3"`
	SettledAt            *time.Time `gorm:"column:settled_at"`
	Graduated            bool       `gorm:"column:graduated;not null;default:false"`
	GraduatedAt          *time.Time `gorm:"column:graduated_at"`
	CreatedAt            time.Time
	UpdatedAt            time.Time
}

// BookingTaxLine records one tax component (VAT, WHT, etc.) per settlement.
type BookingTaxLine struct {
	ID           uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	SettlementID uuid.UUID `gorm:"type:uuid;index;not null"`
	TaxType      string    `gorm:"column:tax_type;type:varchar(20);not null"`
	RateBps      int       `gorm:"column:rate_bps;not null"`
	AmountPaisa  int64     `gorm:"column:amount_paisa;not null"`
	CreatedAt    time.Time
}
