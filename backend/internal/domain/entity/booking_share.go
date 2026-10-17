package entity

import (
	"time"

	"github.com/google/uuid"
)

// BookingShare is one slice of a split-pay booking.
//
// Lifecycle:
//
//	pending  → captain initiated, share not yet paid
//	paid     → SSL Commerz validated; the share is reflected in split_paid_count
//	refunded → booking expired or was cancelled, money sent back to payer
//	expired  → deadline passed before payment (no money to refund)
type BookingShare struct {
	ID        uuid.UUID `gorm:"type:uuid;primaryKey"`
	BookingID uuid.UUID `gorm:"column:booking_id;type:uuid;index;not null"`

	// share_no is 1..booking.split_share_count — stable ordering for the
	// public page so each WhatsApp invite lands on a deterministic slot.
	ShareNo int `gorm:"column:share_no;not null"`

	AmountPaisa int64 `gorm:"column:amount_paisa;not null"`

	// PayerPhone is captured on the public pay page (E.164, BD-normalised).
	// PayerUserID is back-filled when the phone matches an existing user
	// or after the guest signs up post-payment.
	PayerPhone  *string    `gorm:"column:payer_phone"`
	PayerUserID *uuid.UUID `gorm:"column:payer_user_id"`

	// IsCaptainCover marks shares the captain volunteered to absorb when
	// a friend was broke or the deadline was about to miss. Booked
	// against the captain's user_id with a flag so we can analyse later.
	IsCaptainCover bool `gorm:"column:is_captain_cover;not null;default:false"`

	Status     ShareStatus `gorm:"column:status;type:varchar(20);default:'pending'"`
	PaidAt     *time.Time  `gorm:"column:paid_at"`
	RefundedAt *time.Time  `gorm:"column:refunded_at"`

	// SSLTxID is our caller-generated tran_id ("BSH-<uuid>") echoed back
	// in every SSL callback — used to look the share up.
	SSLTxID *string `gorm:"column:ssl_tx_id"`

	// SSLBankTranID is the bank-side transaction id returned by SSL's
	// Validate API. Required to issue a refund. Stored in the legacy
	// `ssl_val_id` column for v1 (the column was originally created for
	// val_id but we only ever need bank_tran_id, so we reuse it).
	SSLBankTranID *string `gorm:"column:ssl_val_id"`

	CreatedAt time.Time
	UpdatedAt time.Time
}

func (BookingShare) TableName() string { return "booking_shares" }

type ShareStatus string

const (
	SharePending  ShareStatus = "pending"
	SharePaid     ShareStatus = "paid"
	ShareRefunded ShareStatus = "refunded"
	ShareExpired  ShareStatus = "expired"
)
