package entity

import (
	"time"

	"github.com/google/uuid"
)

type Booking struct {
	ID        uuid.UUID     `gorm:"type:uuid;primaryKey"`
	PitchID   uuid.UUID     `gorm:"type:uuid;index;not null"`
	UserID    uuid.UUID     `gorm:"type:uuid;index;not null"`
	StartsAt  time.Time     `gorm:"not null"`
	EndsAt    time.Time     `gorm:"not null"`
	TotalCost float64       `gorm:"not null"`
	Status    BookingStatus `gorm:"type:varchar(20);default:'pending'"`
	Notes         string
	Source        string   `gorm:"column:source;not null;default:'turfinn'"`
	PaymentMethod *string  `gorm:"column:payment_method"`
	PaymentAmount *float64 `gorm:"column:payment_amount"`

	// Payment mode + cash split. full_online: SSL collects everything.
	// partial_online: SSL collects only the platform commission;
	// cash_due_paisa is the owner share to settle at the venue.
	PaymentMode        string     `gorm:"column:payment_mode;size:20;not null;default:'full_online'"`
	CashDuePaisa       int64      `gorm:"column:cash_due_paisa;not null;default:0"`
	CashCollectedPaisa int64      `gorm:"column:cash_collected_paisa;not null;default:0"`
	CashCollectedAt    *time.Time `gorm:"column:cash_collected_at"`

	// SourceMatchPostID is set when the booking was auto-created by the
	// quorum-first matchmaking flow (see CreateBookingForMatchIfQuorum).
	// nil for normal player-driven bookings.
	SourceMatchPostID *uuid.UUID `gorm:"column:source_match_post_id"`

	// Split-pay fields. SplitToken is the public magic-link key — present
	// only when the booking was created via the Split-with-friends flow.
	// SplitDeadlineAt is captain-pay-time + 30min; once it passes, an
	// asynq worker refunds paid shares and cancels the booking.
	SplitToken       *string    `gorm:"column:split_token"`
	SplitDeadlineAt  *time.Time `gorm:"column:split_deadline_at"`
	SplitShareCount  int        `gorm:"column:split_share_count;not null;default:0"`
	SplitPaidCount   int        `gorm:"column:split_paid_count;not null;default:0"`

	CreatedAt time.Time
	UpdatedAt time.Time

	Pitch Pitch `gorm:"foreignKey:PitchID"`
	User  User  `gorm:"foreignKey:UserID"`
}

type BookingStatus string

const (
	BookingPending      BookingStatus = "pending"
	BookingPendingSplit BookingStatus = "pending_split"
	BookingConfirmed    BookingStatus = "confirmed"
	BookingCancelled    BookingStatus = "cancelled"
	BookingCompleted    BookingStatus = "completed"

	// Payment modes — kept as plain strings to match the column type.
	PaymentModeFullOnline    = "full_online"
	PaymentModePartialOnline = "partial_online"
)

func NewBooking(pitchID, userID uuid.UUID, startsAt, endsAt time.Time, totalCost float64) *Booking {
	return &Booking{
		ID:        uuid.New(),
		PitchID:   pitchID,
		UserID:    userID,
		StartsAt:  startsAt,
		EndsAt:    endsAt,
		TotalCost: totalCost,
		Status:    BookingPending,
		Source:    "turfinn",
	}
}
