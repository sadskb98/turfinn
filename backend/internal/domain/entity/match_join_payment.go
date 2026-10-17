package entity

import (
	"time"

	"github.com/google/uuid"
)

const (
	MatchPaymentPending   = "pending"
	MatchPaymentSuccess   = "success"
	MatchPaymentFailed    = "failed"
	MatchPaymentCancelled = "cancelled"
	MatchPaymentExpired   = "expired"
)

type MatchJoinPayment struct {
	ID          uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	MatchPostID uuid.UUID `gorm:"type:uuid;not null;column:match_post_id"`
	UserID      uuid.UUID `gorm:"type:uuid;not null;column:user_id"`
	AmountPaisa int64     `gorm:"not null;column:amount_paisa"`
	Currency    string    `gorm:"size:3;not null;default:'BDT'"`
	TranID      *string   `gorm:"size:80;uniqueIndex;column:tran_id"`
	ValID       *string   `gorm:"size:120;column:val_id"`
	BankTranID  *string   `gorm:"size:120;column:bank_tran_id"` // captured on success — needed for SSL refund
	Status      string    `gorm:"size:20;not null;default:'pending'"`

	// Refund tracking
	RefundRefID       *string    `gorm:"size:120;column:refund_ref_id"`
	RefundStatus      *string    `gorm:"size:20;column:refund_status"` // requested | refunded | refund_failed
	RefundReason      *string    `gorm:"size:60;column:refund_reason"` // host_cancelled | auto_cancelled | dispute
	RefundRequestedAt *time.Time `gorm:"column:refund_requested_at"`
	RefundCompletedAt *time.Time `gorm:"column:refund_completed_at"`
	RefundAttempts    int        `gorm:"not null;default:0;column:refund_attempts"`
	LastRefundError   *string    `gorm:"type:text;column:last_refund_error"`

	CreatedAt time.Time
	UpdatedAt time.Time
}

const (
	RefundRequested = "requested"
	RefundDone      = "refunded"
	RefundFailed    = "refund_failed"

	RefundReasonHostCancel   = "host_cancelled"
	RefundReasonAutoCancel   = "auto_cancelled"
	RefundReasonJoinerCancel = "joiner_cancelled"
	RefundReasonDispute      = "dispute"
)

func (MatchJoinPayment) TableName() string { return "match_join_payments" }
