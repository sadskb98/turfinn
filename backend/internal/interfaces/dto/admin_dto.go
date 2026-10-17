package dto

type DashboardStats struct {
	TotalUsers    int64   `json:"total_users"`
	TotalPitches  int64   `json:"total_pitches"`
	TotalBookings int64   `json:"total_bookings"`
	TotalRevenue  float64 `json:"total_revenue"`
	TotalTeams    int64   `json:"total_teams"`
	TotalMatches  int64   `json:"total_matches"`
}

type AdminUserResponse struct {
	ID         string `json:"id"`
	Phone      string `json:"phone"`
	Name       string `json:"name"`
	AvatarURL  string `json:"avatar_url"`
	Position   string `json:"position"`
	SkillLevel string `json:"skill_level"`
	Role       string `json:"role"`
	IsActive   bool   `json:"is_active"`
	CreatedAt  string `json:"created_at"`
}

type AdminBookingResponse struct {
	ID        string  `json:"id"`
	PitchName string  `json:"pitch_name"`
	PitchID   string  `json:"pitch_id"`
	UserName  string  `json:"user_name"`
	UserPhone string  `json:"user_phone"`
	UserID    string  `json:"user_id"`
	StartsAt  string  `json:"starts_at"`
	EndsAt    string  `json:"ends_at"`
	TotalCost float64 `json:"total_cost"`
	Status    string  `json:"status"`
	CreatedAt string  `json:"created_at"`
}

type AdminPitchResponse struct {
	ID           string  `json:"id"`
	Name         string  `json:"name"`
	Address      string  `json:"address"`
	City         string  `json:"city"`
	PricePerHour float64 `json:"price_per_hour"`
	Surface      string  `json:"surface"`
	Capacity     int     `json:"capacity"`
	OwnerID      string  `json:"owner_id"`
	OwnerName    string  `json:"owner_name"`
	IsActive     bool    `json:"is_active"`
	CreatedAt    string  `json:"created_at"`

	// Aviv pricing surface (mirrors PitchResponse fields).
	Plan                      string  `json:"plan"`
	MarketplaceFeeBpsOverride *int    `json:"marketplace_fee_bps_override,omitempty"`
	WalkinFeeBpsOverride      *int    `json:"walkin_fee_bps_override,omitempty"`
	EffectiveCommissionBps    int     `json:"effective_commission_bps"`
	TrialEndsAt               *string `json:"trial_ends_at,omitempty"`
	PremiumActiveUntil        *string `json:"premium_active_until,omitempty"`
	MarketingBoostActive      bool    `json:"marketing_boost_active"`
}

type UpdateUserRoleRequest struct {
	Role string `json:"role" validate:"required,oneof=player manager admin"`
}

type TogglePitchRequest struct {
	IsActive bool `json:"is_active"`
}
