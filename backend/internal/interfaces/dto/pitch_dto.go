package dto

// --- Pitch ---

type CreatePitchRequest struct {
	Name         string  `json:"name"           validate:"required"`
	Description  string  `json:"description"`
	Address      string  `json:"address"        validate:"required"`
	City         string  `json:"city"           validate:"required"`
	Latitude     float64 `json:"latitude"`
	Longitude    float64 `json:"longitude"`
	PricePerHour float64 `json:"price_per_hour" validate:"required,gt=0"`
	Surface      string  `json:"surface"`
	Capacity     int     `json:"capacity"`
}

type PitchResponse struct {
	ID              string   `json:"id"`
	Name            string   `json:"name"`
	Description     string   `json:"description"`
	Address         string   `json:"address"`
	City            string   `json:"city"`
	Latitude        float64  `json:"latitude"`
	Longitude       float64  `json:"longitude"`
	PricePerHour    float64  `json:"price_per_hour"`
	Surface         string   `json:"surface"`
	Capacity        int      `json:"capacity"`
	ImageURLs       string   `json:"image_urls"`
	BannerURL       string   `json:"banner_url"`
	IsActive        bool     `json:"is_active"`
	ServiceRadiusKM *float64 `json:"service_radius_km,omitempty"`
	DistanceKM      *float64 `json:"distance_km,omitempty"`

	// Payment mode: tells the booking UI which toggles to show.
	AllowsPartialPayment bool   `json:"allows_partial_payment"`
	AllowsFullPayment    bool   `json:"allows_full_payment"`
	DefaultPaymentMode   string `json:"default_payment_mode"`

	// Aviv pricing surface. Plan = "marketplace" or "erp_only".
	// Override fields are nil when the pitch uses default tier rates.
	// EffectiveCommissionBps is the rate that *would* apply to a new
	// marketplace booking right now (after trial / override / tier
	// resolution) — drives the panel's "current rate" display.
	Plan                      string  `json:"plan"`
	MarketplaceFeeBpsOverride *int    `json:"marketplace_fee_bps_override,omitempty"`
	WalkinFeeBpsOverride      *int    `json:"walkin_fee_bps_override,omitempty"`
	EffectiveCommissionBps    int     `json:"effective_commission_bps"`
	TrialEndsAt               *string `json:"trial_ends_at,omitempty"`
	PremiumActiveUntil        *string `json:"premium_active_until,omitempty"`
	MarketingBoostActive      bool    `json:"marketing_boost_active"`
}

type ListPitchesQuery struct {
	City   string  `query:"city"`
	Search string  `query:"search"`
	Lat    float64 `query:"lat"`
	Lng    float64 `query:"lng"`
	Radius float64 `query:"radius"`
	Page   int     `query:"page"  validate:"min=1"`
	Limit  int     `query:"limit" validate:"min=1,max=50"`
}
