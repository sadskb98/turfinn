package entity

import (
	"time"

	"github.com/google/uuid"
)

type Pitch struct {
	ID          uuid.UUID `gorm:"type:uuid;primaryKey"`
	Name        string    `gorm:"not null"`
	Description string
	Address     string    `gorm:"not null"`
	City        string    `gorm:"index;not null"`
	Latitude    float64
	Longitude   float64
	PricePerHour float64  `gorm:"not null"`
	Surface     string    // grass, artificial, futsal
	Capacity    int
	ImageURLs      string    // comma-separated
	BannerURL      string    `gorm:"column:banner_url"`
	OwnerID        uuid.UUID `gorm:"type:uuid;index;not null"`
	IsActive       bool      `gorm:"default:true"`
	ServiceRadiusKM *float64  `gorm:"column:service_radius_km"`

	// Payment mode preferences. Owners who don't trust full online payment
	// can default to partial; players can still toggle if both are allowed.
	AllowsPartialPayment bool   `gorm:"column:allows_partial_payment;not null;default:true"`
	AllowsFullPayment    bool   `gorm:"column:allows_full_payment;not null;default:true"`
	DefaultPaymentMode   string `gorm:"column:default_payment_mode;size:20;not null;default:'partial_online'"`

	// Business plan + commission. marketplace pitches show in the player
	// app and pay tier-based commission on app bookings; both plans pay
	// the walkin rate on walk-in bookings logged via the manager panel.
	// MarketplaceFeeBps + WalkinFeeBps are deprecated defaults from
	// migration 042 (kept to avoid a destructive rename); the runtime
	// resolver reads tier config + the *Override fields below.
	Plan               string `gorm:"column:plan;size:20;not null;default:'marketplace'"`
	MarketplaceFeeBps  int    `gorm:"column:marketplace_fee_bps;not null;default:1000"`
	WalkinFeeBps       int    `gorm:"column:walkin_fee_bps;not null;default:300"`

	// Per-pitch override columns. nil = use Aviv tier defaults from
	// config; non-nil = use this exact rate (negotiated for high-volume
	// turfs). Override always wins over tier table.
	MarketplaceFeeBpsOverride *int       `gorm:"column:marketplace_fee_bps_override"`
	WalkinFeeBpsOverride      *int       `gorm:"column:walkin_fee_bps_override"`
	// Trial: 60-day grace period from onboarding where commission = 0%.
	TrialEndsAt          *time.Time `gorm:"column:trial_ends_at"`
	// Premium ERP gate: nil or past timestamp = locked, future = unlocked.
	PremiumActiveUntil   *time.Time `gorm:"column:premium_active_until"`
	// Marketing boost add-on toggle (per-pitch).
	MarketingBoostActive bool       `gorm:"column:marketing_boost_active;not null;default:false"`

	CreatedAt      time.Time
	UpdatedAt      time.Time
}

// Pitch plan constants — kept narrow on purpose so we don't end up with
// a sprawl of half-supported tiers.
const (
	PitchPlanMarketplace = "marketplace"
	PitchPlanERPOnly     = "erp_only"
)

// FeeBpsForBookingSource returns the commission rate (basis points) for
// a booking originating from the given source. "turfinn" / "" = app-led
// bookings; "walk_in" = manager-logged walk-ins. ERP-only pitches reject
// app-led bookings entirely so this is only called for valid combos.
func (p *Pitch) FeeBpsForBookingSource(source string) int {
	if source == "walk_in" {
		return p.WalkinFeeBps
	}
	// Anything else = customer-driven booking via the marketplace.
	return p.MarketplaceFeeBps
}

func NewPitch(name, address, city string, ownerID uuid.UUID, pricePerHour float64) *Pitch {
	return &Pitch{
		ID:           uuid.New(),
		Name:         name,
		Address:      address,
		City:         city,
		OwnerID:      ownerID,
		PricePerHour: pricePerHour,
		IsActive:     true,
	}
}
