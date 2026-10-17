package dto

import "time"

// --- Analytics ---

type AnalyticsSummaryResponse struct {
	Revenue      float64 `json:"revenue"`
	BookingCount int64   `json:"booking_count"`
	OccupancyPct float64 `json:"occupancy_pct"`
	AvgRating    float64 `json:"avg_rating"`
	Period       string  `json:"period"`
}

type DailyRevenue struct {
	Date   string  `json:"date"`
	Amount float64 `json:"amount"`
}

type RevenueChartResponse struct {
	Days int            `json:"days"`
	Data []DailyRevenue `json:"data"`
}

type PitchStats struct {
	PitchID      string  `json:"pitch_id"`
	PitchName    string  `json:"pitch_name"`
	BookingCount int64   `json:"booking_count"`
	Revenue      float64 `json:"revenue"`
	OccupancyPct float64 `json:"occupancy_pct"`
	AvgRating    float64 `json:"avg_rating"`
}

// --- Bookings ---

type ManagerBookingFilter struct {
	Status string
	Source string
	Date   string
	Page   int
	Limit  int
}

type ManagerBookingResponse struct {
	ID            string    `json:"id"`
	PitchID       string    `json:"pitch_id"`
	PitchName     string    `json:"pitch_name"`
	UserID        string    `json:"user_id"`
	CustomerName  string    `json:"customer_name"`
	CustomerPhone string    `json:"customer_phone,omitempty"`
	StartsAt      time.Time `json:"starts_at"`
	EndsAt        time.Time `json:"ends_at"`
	TotalCost     float64   `json:"total_cost"`
	Status        string    `json:"status"`
	Source        string    `json:"source"`
	PaymentMethod *string   `json:"payment_method,omitempty"`
	PaymentAmount *float64  `json:"payment_amount,omitempty"`
	Notes         string    `json:"notes"`

	// Cash settlement (partial-payment bookings only).
	PaymentMode        string     `json:"payment_mode"`
	CashDuePaisa       int64      `json:"cash_due_paisa"`
	CashCollectedPaisa int64      `json:"cash_collected_paisa"`
	CashCollectedAt    *time.Time `json:"cash_collected_at,omitempty"`
}

type CreateWalkInBookingRequest struct {
	PitchID       string    `json:"pitch_id" validate:"required,uuid"`
	StartsAt      time.Time `json:"starts_at" validate:"required"`
	EndsAt        time.Time `json:"ends_at" validate:"required"`
	CustomerName  string    `json:"customer_name" validate:"required,min=1,max=100"`
	PaymentMethod string    `json:"payment_method" validate:"required,oneof=cash card transfer"`
	PaymentAmount float64   `json:"payment_amount" validate:"required,gt=0"`
}

// --- Financials ---

type PaymentMethodBreakdown struct {
	Method string  `json:"method"`
	Amount float64 `json:"amount"`
	Count  int64   `json:"count"`
}

type FinancialsResponse struct {
	From            string                   `json:"from"`
	To              string                   `json:"to"`
	TotalRevenue    float64                  `json:"total_revenue"`
	TurfinnRevenue  float64                  `json:"turfinn_revenue"`
	WalkInRevenue   float64                  `json:"walk_in_revenue"`
	ByPaymentMethod []PaymentMethodBreakdown `json:"by_payment_method"`
}
