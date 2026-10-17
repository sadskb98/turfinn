package dto

// --- Enhanced Analytics ---

type HourlyBookingCount struct {
	DayOfWeek int     `json:"day_of_week"` // 0=Sunday, 6=Saturday
	Hour      int     `json:"hour"`        // 0-23
	Count     int64   `json:"count"`
	Revenue   float64 `json:"revenue"`
}

type HeatmapResponse struct {
	Period string               `json:"period"`
	Data   []HourlyBookingCount `json:"data"`
}

type PeakHour struct {
	Hour    int     `json:"hour"`
	Count   int64   `json:"count"`
	Revenue float64 `json:"revenue"`
}

type PeakHoursResponse struct {
	Period    string     `json:"period"`
	Busiest   []PeakHour `json:"busiest"`
	Slowest   []PeakHour `json:"slowest"`
	AvgPerDay float64    `json:"avg_bookings_per_day"`
}

type CustomerInsight struct {
	UserID       string  `json:"user_id"`
	Name         string  `json:"name"`
	Phone        string  `json:"phone"`
	BookingCount int64   `json:"booking_count"`
	TotalSpent   float64 `json:"total_spent"`
	LastVisit    string  `json:"last_visit"`
}

type CustomerInsightsResponse struct {
	Period          string            `json:"period"`
	TotalCustomers  int64             `json:"total_customers"`
	NewCustomers    int64             `json:"new_customers"`
	ReturningPct    float64           `json:"returning_pct"`
	TopCustomers    []CustomerInsight `json:"top_customers"`
}

// --- Enhanced Financials ---

type DailyLedgerEntry struct {
	Date          string  `json:"date"`
	BookingCount  int64   `json:"booking_count"`
	TotalRevenue  float64 `json:"total_revenue"`
	AppRevenue    float64 `json:"app_revenue"`
	WalkInRevenue float64 `json:"walkin_revenue"`
	Commission    float64 `json:"commission"`
}

type DailyLedgerResponse struct {
	From    string             `json:"from"`
	To      string             `json:"to"`
	Entries []DailyLedgerEntry `json:"entries"`
	Summary DailyLedgerEntry   `json:"summary"`
}

type PitchPnLEntry struct {
	PitchID      string  `json:"pitch_id"`
	PitchName    string  `json:"pitch_name"`
	Revenue      float64 `json:"revenue"`
	BookingCount int64   `json:"booking_count"`
	BookedHours  float64 `json:"booked_hours"`
	OccupancyPct float64 `json:"occupancy_pct"`
	Commission   float64 `json:"commission"`
	NetRevenue   float64 `json:"net_revenue"`
}

// --- Manager Promo Codes ---

type ManagerPromoResponse struct {
	ID            string  `json:"id"`
	Code          string  `json:"code"`
	DiscountType  string  `json:"discount_type"`
	DiscountValue float64 `json:"discount_value"`
	MaxUses       int     `json:"max_uses"`
	UsedCount     int     `json:"used_count"`
	ValidFrom     string  `json:"valid_from"`
	ValidTo       string  `json:"valid_to"`
	IsActive      bool    `json:"is_active"`
	CreatedAt     string  `json:"created_at"`
}

type CreateManagerPromoRequest struct {
	Code          string  `json:"code" validate:"required,min=3,max=20"`
	DiscountType  string  `json:"discount_type" validate:"required,oneof=percent fixed"`
	DiscountValue float64 `json:"discount_value" validate:"required,gt=0"`
	MaxUses       int     `json:"max_uses" validate:"required,min=1,max=10000"`
	ValidFrom     string  `json:"valid_from" validate:"required"`
	ValidTo       string  `json:"valid_to" validate:"required"`
}
