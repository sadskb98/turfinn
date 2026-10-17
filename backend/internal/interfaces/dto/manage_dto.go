package dto

type ManagerDashboardStats struct {
	TotalPitches     int     `json:"total_pitches"`
	TotalBookings    int64   `json:"total_bookings"`
	TotalRevenue     float64 `json:"total_revenue"`
	TodayBookings    int64   `json:"today_bookings"`
	UpcomingBookings int64   `json:"upcoming_bookings"`
	// Cash collection KPI — sum of cash_due_paisa minus cash_collected_paisa
	// across all the manager's confirmed bookings. The dashboard surfaces
	// this so owners see uncollected money at a glance.
	CashToCollectBDT float64 `json:"cash_to_collect_bdt"`
}

type UpsertPitchRequest struct {
	Name            string   `json:"name" validate:"required"`
	Description     string   `json:"description"`
	Address         string   `json:"address" validate:"required"`
	City            string   `json:"city" validate:"required"`
	Latitude        float64  `json:"latitude"`
	Longitude       float64  `json:"longitude"`
	PricePerHour    float64  `json:"price_per_hour" validate:"required,gt=0"`
	Surface         string   `json:"surface"`
	Capacity        int      `json:"capacity"`
	ImageURLs       string   `json:"image_urls"`
	BannerURL       string   `json:"banner_url"`
	ServiceRadiusKM *float64 `json:"service_radius_km"`
}

// ManagerBookingResponse is defined in manager_dto.go
