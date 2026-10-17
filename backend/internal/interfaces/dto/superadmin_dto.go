package dto

type NorthStarResponse struct {
	GMV           float64 `json:"gmv"`
	GMVMTD        float64 `json:"gmv_mtd"`
	NetRevenue    float64 `json:"net_revenue"`
	NetRevenueMTD float64 `json:"net_revenue_mtd"`
	ActiveTurfs   int64   `json:"active_turfs"`
	ActivePlayers int64   `json:"active_players"`
	TotalBookings int64   `json:"total_bookings"`
	BookingsMTD   int64   `json:"bookings_mtd"`
}

type CohortRowResponse struct {
	CohortMonth string  `json:"cohort_month"`
	MonthOffset int     `json:"month_offset"`
	Retained    int64   `json:"retained"`
	CohortSize  int64   `json:"cohort_size"`
	Rate        float64 `json:"rate"`
}

type FunnelStepResponse struct {
	EventType string  `json:"event_type"`
	Count     int64   `json:"count"`
	DropOff   float64 `json:"drop_off"`
}

type RevenuePointResponse struct {
	Date    string  `json:"date"`
	Revenue float64 `json:"revenue"`
}

type AuditLogResponse struct {
	ID         int64  `json:"id"`
	ActorID    string `json:"actor_id"`
	ActorRole  string `json:"actor_role"`
	Action     string `json:"action"`
	EntityType string `json:"entity_type"`
	EntityID   string `json:"entity_id"`
	OldValue   string `json:"old_value,omitempty"`
	NewValue   string `json:"new_value,omitempty"`
	IPAddress  string `json:"ip_address"`
	CreatedAt  string `json:"created_at"`
}

type IncomeStatementResponse struct {
	Revenue      int64 `json:"revenue_paisa"`
	Refunds      int64 `json:"refunds_paisa"`
	PromoExpense int64 `json:"promo_expense_paisa"`
	Net          int64 `json:"net_paisa"`
}

type VATRowResponse struct {
	Month            string  `json:"month"`
	TotalBookings    int64   `json:"total_bookings"`
	TotalGMV         float64 `json:"total_gmv"`
	TotalPlatformFee float64 `json:"total_platform_fee"`
	VATAmount        float64 `json:"vat_amount"`
}

type FraudFlagResponse struct {
	ID         string `json:"id"`
	EntityType string `json:"entity_type"`
	EntityID   string `json:"entity_id"`
	FlagType   string `json:"flag_type"`
	Details    string `json:"details"`
	Status     string `json:"status"`
	CreatedAt  string `json:"created_at"`
}

type RateLimitResponse struct {
	EndpointGroup     string `json:"endpoint_group"`
	RequestsPerMinute int    `json:"requests_per_minute"`
	Burst             int    `json:"burst"`
	IsEnabled         bool   `json:"is_enabled"`
}

type UpdateRateLimitRequest struct {
	RequestsPerMinute int `json:"requests_per_minute" validate:"required,min=1"`
	Burst             int `json:"burst" validate:"required,min=1"`
}

type APIKeyResponse struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	OwnerOrg  string `json:"owner_org"`
	Scopes    string `json:"scopes"`
	IsActive  bool   `json:"is_active"`
	ExpiresAt string `json:"expires_at,omitempty"`
	CreatedAt string `json:"created_at"`
}

type CreateAPIKeyRequest struct {
	Name     string `json:"name" validate:"required"`
	OwnerOrg string `json:"owner_org"`
	Scopes   string `json:"scopes"`
}

type APIKeyCreatedResponse struct {
	ID  string `json:"id"`
	Key string `json:"key"` // Only shown once at creation
}

type ZoneResponse struct {
	ID              string  `json:"id"`
	Name            string  `json:"name"`
	Slug            string  `json:"slug"`
	City            string  `json:"city"`
	Lat             float64 `json:"lat"`
	Lng             float64 `json:"lng"`
	RadiusKM        float64 `json:"radius_km"`
	IsActive        bool    `json:"is_active"`
	ZoneManagerID   string  `json:"zone_manager_id,omitempty"`
	ZoneManagerName string  `json:"zone_manager_name,omitempty"`
}

type CreateZoneRequest struct {
	Name     string  `json:"name" validate:"required"`
	Slug     string  `json:"slug" validate:"required"`
	City     string  `json:"city" validate:"required"`
	Lat      float64 `json:"lat"`
	Lng      float64 `json:"lng"`
	RadiusKM float64 `json:"radius_km"`
}

type OrgResponse struct {
	ID                 string `json:"id"`
	Name               string `json:"name"`
	ContactName        string `json:"contact_name"`
	ContactEmail       string `json:"contact_email"`
	Phone              string `json:"phone"`
	CreditLimitPaisa   int64  `json:"credit_limit_paisa"`
	WalletBalancePaisa int64  `json:"wallet_balance_paisa"`
	IsActive           bool   `json:"is_active"`
}

type CreateOrgRequest struct {
	Name             string `json:"name" validate:"required"`
	ContactName      string `json:"contact_name"`
	ContactEmail     string `json:"contact_email"`
	Phone            string `json:"phone"`
	BillingAddress   string `json:"billing_address"`
	CreditLimitPaisa int64  `json:"credit_limit_paisa"`
}

type AddCreditRequest struct {
	AmountPaisa int64 `json:"amount_paisa" validate:"required,gt=0"`
}

type ResellerResponse struct {
	ID                 string  `json:"id"`
	UserID             string  `json:"user_id"`
	Name               string  `json:"name"`
	CommissionPercent  float64 `json:"commission_percent"`
	TotalEarnedPaisa   int64   `json:"total_earned_paisa"`
	TotalPaidPaisa     int64   `json:"total_paid_paisa"`
	ActivePitchesCount int     `json:"active_pitches_count"`
	IsActive           bool    `json:"is_active"`
}

type CreateResellerRequest struct {
	UserID            string  `json:"user_id" validate:"required"`
	Name              string  `json:"name" validate:"required"`
	CommissionPercent float64 `json:"commission_percent" validate:"required,gt=0,lte=100"`
}

type BookingEventRequest struct {
	SessionID string `json:"session_id"`
	EventType string `json:"event_type" validate:"required,oneof=app_open pitch_search pitch_view slot_selected checkout_started payment_initiated booking_confirmed"`
	Metadata  string `json:"metadata"`
}

type MarketingSpendRequest struct {
	Month  string  `json:"month" validate:"required"` // YYYY-MM-01
	Amount float64 `json:"amount" validate:"required,gt=0"`
	Notes  string  `json:"notes"`
}
