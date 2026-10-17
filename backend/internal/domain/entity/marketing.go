// Package entity contains pure domain structs for marketing & growth.
package entity

import (
	"time"

	"github.com/google/uuid"
)

type PromoCode struct {
	ID               uuid.UUID `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	Code             string    `gorm:"column:code;uniqueIndex"`
	DiscountType     string    `gorm:"column:discount_type"` // percent, fixed
	DiscountValue    float64   `gorm:"column:discount_value"`
	MinBookingAmount float64   `gorm:"column:min_booking_amount"`
	MaxUses          int       `gorm:"column:max_uses"`
	UsedCount        int       `gorm:"column:used_count"`
	PerUserLimit     int       `gorm:"column:per_user_limit"`
	PitchIDs         string    `gorm:"column:pitch_ids;type:jsonb"`
	ValidFrom        time.Time `gorm:"column:valid_from"`
	ValidTo          time.Time `gorm:"column:valid_to"`
	CreatedBy        uuid.UUID `gorm:"column:created_by"`
	IsActive         bool       `gorm:"column:is_active"`
	CreatedAt        time.Time  `gorm:"column:created_at"`
	OwnerID          *uuid.UUID `json:"owner_id,omitempty" gorm:"type:uuid;index"`
}

func (PromoCode) TableName() string { return "promo_codes" }

type PromoCodeUse struct {
	ID              uuid.UUID `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	PromoCodeID     uuid.UUID `gorm:"column:promo_code_id"`
	UserID          uuid.UUID `gorm:"column:user_id"`
	BookingID       uuid.UUID `gorm:"column:booking_id"`
	DiscountApplied float64   `gorm:"column:discount_applied"`
	UsedAt          time.Time `gorm:"column:used_at"`
}

func (PromoCodeUse) TableName() string { return "promo_code_uses" }

type NotificationCampaign struct {
	ID            uuid.UUID  `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	Title         string     `gorm:"column:title"`
	Body          string     `gorm:"column:body"`
	SegmentType   string     `gorm:"column:segment_type"` // all, inactive_30d, pitch_users, city, captains
	SegmentParams string     `gorm:"column:segment_params;type:jsonb"`
	ScheduledAt   *time.Time `gorm:"column:scheduled_at"`
	SentAt        *time.Time `gorm:"column:sent_at"`
	SentCount     int        `gorm:"column:sent_count"`
	CreatedBy     uuid.UUID  `gorm:"column:created_by"`
	CreatedAt     time.Time  `gorm:"column:created_at"`
}

func (NotificationCampaign) TableName() string { return "notification_campaigns" }

type FeaturedPitch struct {
	ID         uuid.UUID `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	PitchID    uuid.UUID `gorm:"column:pitch_id"`
	Position   int       `gorm:"column:position"`
	StartsAt   time.Time `gorm:"column:starts_at"`
	EndsAt     time.Time `gorm:"column:ends_at"`
	AmountPaid float64   `gorm:"column:amount_paid"`
	CreatedBy  uuid.UUID `gorm:"column:created_by"`
	CreatedAt  time.Time `gorm:"column:created_at"`

	Pitch *Pitch `gorm:"foreignKey:PitchID"`
}

func (FeaturedPitch) TableName() string { return "featured_pitches" }

// LedgerTransaction tracks paisa-based wallet credits/debits for finance reporting
type LedgerTransaction struct {
	ID          uuid.UUID `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	UserID      uuid.UUID `gorm:"column:user_id"`
	AmountPaisa int64     `gorm:"column:amount_paisa"`
	Type        string    `gorm:"column:type"` // credit, debit, referral_reward, refund, promo
	Description string    `gorm:"column:description"`
	RefID       uuid.UUID `gorm:"column:ref_id"`
	CreatedAt   time.Time `gorm:"column:created_at"`
}

func (LedgerTransaction) TableName() string { return "wallet_transactions" }

type Referral struct {
	ID             uuid.UUID  `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	ReferrerID     uuid.UUID  `gorm:"column:referrer_id"`
	ReferredUserID uuid.UUID  `gorm:"column:referred_user_id"`
	BookingID      uuid.UUID  `gorm:"column:booking_id"`
	RewardAmount   int64      `gorm:"column:reward_amount"`
	Status         string     `gorm:"column:status"` // pending, rewarded, expired
	RewardedAt     *time.Time `gorm:"column:rewarded_at"`
	CreatedAt      time.Time  `gorm:"column:created_at"`

	Referrer     *User `gorm:"foreignKey:ReferrerID"`
	ReferredUser *User `gorm:"foreignKey:ReferredUserID"`
}

func (Referral) TableName() string { return "referrals" }

type Banner struct {
	ID           uuid.UUID  `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	ImageURL     string     `gorm:"column:image_url"`
	Title        string     `gorm:"column:title"`
	CtaURL       string     `gorm:"column:cta_url"`
	DisplayOrder int        `gorm:"column:display_order"`
	StartsAt     *time.Time `gorm:"column:starts_at"`
	EndsAt       *time.Time `gorm:"column:ends_at"`
	IsActive     bool       `gorm:"column:is_active"`
	CreatedAt    time.Time  `gorm:"column:created_at"`
}

func (Banner) TableName() string { return "banners" }
