package dto

import "time"

// --- Booking ---

type CreateBookingRequest struct {
	PitchID     string    `json:"pitch_id"  validate:"required,uuid"`
	StartsAt    time.Time `json:"starts_at" validate:"required"`
	EndsAt      time.Time `json:"ends_at"   validate:"required,gtfield=StartsAt"`
	Notes       string    `json:"notes"`
	// PaymentMode is "full_online" or "partial_online". When empty, the
	// pitch's default_payment_mode is used. Rejected if the pitch doesn't
	// allow the requested mode.
	PaymentMode string `json:"payment_mode,omitempty" validate:"omitempty,oneof=full_online partial_online"`
}

type BookingResponse struct {
	ID                 string    `json:"id"`
	PitchID            string    `json:"pitch_id"`
	PitchName          string    `json:"pitch_name"`
	UserID             string    `json:"user_id"`
	StartsAt           time.Time `json:"starts_at"`
	EndsAt             time.Time `json:"ends_at"`
	TotalCost          float64   `json:"total_cost"`
	Status             string    `json:"status"`
	Notes              string    `json:"notes"`
	PaymentMode        string    `json:"payment_mode"`
	CashDuePaisa       int64     `json:"cash_due_paisa"`
	CashCollectedPaisa int64     `json:"cash_collected_paisa"`
}

type ListBookingsQuery struct {
	Page  int `query:"page"  validate:"min=1"`
	Limit int `query:"limit" validate:"min=1,max=50"`
}
