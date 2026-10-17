// Package entity contains pure domain structs for zones & partners.
package entity

import (
	"time"

	"github.com/google/uuid"
)

type Zone struct {
	ID            uuid.UUID `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	Name          string    `gorm:"column:name"`
	Slug          string    `gorm:"column:slug;uniqueIndex"`
	City          string    `gorm:"column:city"`
	Lat           float64   `gorm:"column:lat"`
	Lng           float64   `gorm:"column:lng"`
	RadiusKM      float64   `gorm:"column:radius_km"`
	IsActive      bool      `gorm:"column:is_active"`
	ZoneManagerID uuid.UUID `gorm:"column:zone_manager_id"`
	CreatedAt     time.Time `gorm:"column:created_at"`
	UpdatedAt     time.Time `gorm:"column:updated_at"`

	ZoneManager *User `gorm:"foreignKey:ZoneManagerID"`
}

func (Zone) TableName() string { return "zones" }

type Organization struct {
	ID                uuid.UUID `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	Name              string    `gorm:"column:name"`
	ContactName       string    `gorm:"column:contact_name"`
	ContactEmail      string    `gorm:"column:contact_email"`
	Phone             string    `gorm:"column:phone"`
	BillingAddress    string    `gorm:"column:billing_address"`
	CreditLimitPaisa  int64     `gorm:"column:credit_limit_paisa"`
	WalletBalancePaisa int64    `gorm:"column:wallet_balance_paisa"`
	IsActive          bool      `gorm:"column:is_active"`
	CreatedAt         time.Time `gorm:"column:created_at"`
	UpdatedAt         time.Time `gorm:"column:updated_at"`
}

func (Organization) TableName() string { return "organizations" }

type OrgMember struct {
	OrgID   uuid.UUID `gorm:"primaryKey;column:org_id"`
	UserID  uuid.UUID `gorm:"primaryKey;column:user_id"`
	Role    string    `gorm:"column:role"` // owner, member
	AddedAt time.Time `gorm:"column:added_at"`

	User *User         `gorm:"foreignKey:UserID"`
	Org  *Organization `gorm:"foreignKey:OrgID"`
}

func (OrgMember) TableName() string { return "org_members" }

type Reseller struct {
	ID                 uuid.UUID `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	UserID             uuid.UUID `gorm:"column:user_id;uniqueIndex"`
	Name               string    `gorm:"column:name"`
	CommissionPercent  float64   `gorm:"column:commission_percent"`
	TotalEarnedPaisa   int64     `gorm:"column:total_earned_paisa"`
	TotalPaidPaisa     int64     `gorm:"column:total_paid_paisa"`
	ActivePitchesCount int       `gorm:"column:active_pitches_count"`
	IsActive           bool      `gorm:"column:is_active"`
	CreatedAt          time.Time `gorm:"column:created_at"`
	UpdatedAt          time.Time `gorm:"column:updated_at"`

	User *User `gorm:"foreignKey:UserID"`
}

func (Reseller) TableName() string { return "resellers" }

type RateLimitConfig struct {
	EndpointGroup     string    `gorm:"primaryKey;column:endpoint_group"`
	RequestsPerMinute int       `gorm:"column:requests_per_minute"`
	Burst             int       `gorm:"column:burst"`
	IsEnabled         bool      `gorm:"column:is_enabled"`
	UpdatedAt         time.Time `gorm:"column:updated_at"`
}

func (RateLimitConfig) TableName() string { return "rate_limit_config" }

type APIKey struct {
	ID                uuid.UUID  `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	Name              string     `gorm:"column:name"`
	KeyHash           string     `gorm:"column:key_hash"`
	OwnerOrg          string     `gorm:"column:owner_org"`
	Scopes            string     `gorm:"column:scopes;type:jsonb"`
	RateLimitOverride int        `gorm:"column:rate_limit_override"`
	LastUsedAt        *time.Time `gorm:"column:last_used_at"`
	ExpiresAt         *time.Time `gorm:"column:expires_at"`
	IsActive          bool       `gorm:"column:is_active"`
	CreatedAt         time.Time  `gorm:"column:created_at"`
}

func (APIKey) TableName() string { return "api_keys" }

// BookingEvent is defined in booking_event.go

type MarketingSpend struct {
	ID        uuid.UUID `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	Month     time.Time `gorm:"column:month;uniqueIndex"`
	Amount    float64   `gorm:"column:amount"`
	Notes     string    `gorm:"column:notes"`
	EnteredBy uuid.UUID `gorm:"column:entered_by"`
	CreatedAt time.Time `gorm:"column:created_at"`
}

func (MarketingSpend) TableName() string { return "marketing_spend" }
