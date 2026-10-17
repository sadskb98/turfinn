package dto

type PromoCodeResponse struct {
	ID               string  `json:"id"`
	Code             string  `json:"code"`
	DiscountType     string  `json:"discount_type"`
	DiscountValue    float64 `json:"discount_value"`
	MinBookingAmount float64 `json:"min_booking_amount"`
	MaxUses          int     `json:"max_uses"`
	UsedCount        int     `json:"used_count"`
	PerUserLimit     int     `json:"per_user_limit"`
	PitchIDs         string  `json:"pitch_ids"`
	ValidFrom        string  `json:"valid_from"`
	ValidTo          string  `json:"valid_to"`
	IsActive         bool    `json:"is_active"`
	CreatedAt        string  `json:"created_at"`
}

type CreatePromoCodeRequest struct {
	Code             string  `json:"code" validate:"required"`
	DiscountType     string  `json:"discount_type" validate:"required,oneof=percent fixed"`
	DiscountValue    float64 `json:"discount_value" validate:"required,gt=0"`
	MinBookingAmount float64 `json:"min_booking_amount"`
	MaxUses          int     `json:"max_uses"`
	PerUserLimit     int     `json:"per_user_limit"`
	PitchIDs         string  `json:"pitch_ids"`
	ValidFrom        string  `json:"valid_from" validate:"required"`
	ValidTo          string  `json:"valid_to" validate:"required"`
}

type ApplyPromoRequest struct {
	Code string `json:"code" validate:"required"`
}

type CampaignResponse struct {
	ID            string `json:"id"`
	Title         string `json:"title"`
	Body          string `json:"body"`
	SegmentType   string `json:"segment_type"`
	SegmentParams string `json:"segment_params"`
	ScheduledAt   string `json:"scheduled_at,omitempty"`
	SentAt        string `json:"sent_at,omitempty"`
	SentCount     int    `json:"sent_count"`
	CreatedAt     string `json:"created_at"`
}

type CreateCampaignRequest struct {
	Title         string `json:"title" validate:"required"`
	Body          string `json:"body" validate:"required"`
	SegmentType   string `json:"segment_type" validate:"required,oneof=all inactive_30d pitch_users city captains"`
	SegmentParams string `json:"segment_params"`
	ScheduledAt   string `json:"scheduled_at"`
}

type FeaturedPitchResponse struct {
	ID         string  `json:"id"`
	PitchID    string  `json:"pitch_id"`
	PitchName  string  `json:"pitch_name"`
	Position   int     `json:"position"`
	StartsAt   string  `json:"starts_at"`
	EndsAt     string  `json:"ends_at"`
	AmountPaid float64 `json:"amount_paid"`
}

type CreateFeaturedPitchRequest struct {
	PitchID    string  `json:"pitch_id" validate:"required"`
	Position   int     `json:"position" validate:"required,min=1,max=10"`
	StartsAt   string  `json:"starts_at" validate:"required"`
	EndsAt     string  `json:"ends_at" validate:"required"`
	AmountPaid float64 `json:"amount_paid"`
}

type ReferralStatsResponse struct {
	TotalReferrals    int64 `json:"total_referrals"`
	TotalRewarded     int64 `json:"total_rewarded"`
	TotalRewardsPaisa int64 `json:"total_rewards_paisa"`
	ConversionRate    float64 `json:"conversion_rate"`
}

type BannerResponse struct {
	ID           string `json:"id"`
	ImageURL     string `json:"image_url"`
	Title        string `json:"title"`
	CtaURL       string `json:"cta_url"`
	DisplayOrder int    `json:"display_order"`
	StartsAt     string `json:"starts_at,omitempty"`
	EndsAt       string `json:"ends_at,omitempty"`
	IsActive     bool   `json:"is_active"`
}

type CreateBannerRequest struct {
	ImageURL     string `json:"image_url" validate:"required"`
	Title        string `json:"title"`
	CtaURL       string `json:"cta_url"`
	DisplayOrder int    `json:"display_order"`
	StartsAt     string `json:"starts_at"`
	EndsAt       string `json:"ends_at"`
}
