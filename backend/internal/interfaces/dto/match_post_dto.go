package dto

import "time"

// CreateMatchPostRequest — every match must be at a vetted Turfinn pitch.
// per_head_cost is computed server-side from the pitch rate × duration ÷ spots
// so callers can't set it. join_fee_bdt is also server-side (Consul-tunable).
type CreateMatchPostRequest struct {
	PitchID         string    `json:"pitch_id" validate:"required,uuid"`
	Title           string    `json:"title" validate:"required,max=200"`
	Description     string    `json:"description"`
	MatchDate       time.Time `json:"match_date" validate:"required"`
	DurationMinutes int       `json:"duration_minutes" validate:"min=0,max=480"`
	Format          string    `json:"format" validate:"omitempty,oneof=5v5 6v6 7v7 11v11"`
	SpotsTotal      int       `json:"spots_total" validate:"required,min=2,max=30"`
	PostType        string    `json:"post_type"` // open_match | need_teammates
}

type ReportMatchPostRequest struct {
	TargetKind string `json:"target_kind" validate:"omitempty,oneof=post venue host"`
	Reason     string `json:"reason" validate:"required,oneof=unsafe_location no_show fake spam other"`
	Note       string `json:"note" validate:"max=500"`
}

type ExternalPitchResponse struct {
	ID        string  `json:"id"`
	Name      string  `json:"name"`
	Address   string  `json:"address,omitempty"`
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
	RefCount  int     `json:"ref_count"`
	Verified  bool    `json:"verified"`
}

type CreateExternalPitchRequest struct {
	Name      string  `json:"name" validate:"required,min=2,max=160"`
	Address   string  `json:"address" validate:"max=300"`
	Latitude  float64 `json:"latitude" validate:"required"`
	Longitude float64 `json:"longitude" validate:"required"`
}

type MatchPostResponse struct {
	ID              string                 `json:"id"`
	AuthorID        string                 `json:"author_id"`
	AuthorName      string                 `json:"author_name"`
	PitchID         *string                `json:"pitch_id,omitempty"`
	PitchName       *string                `json:"pitch_name,omitempty"`
	ExternalPitch   *ExternalPitchResponse `json:"external_pitch,omitempty"`
	VenueKind       string                 `json:"venue_kind"` // 'turfinn'|'external'|'custom'
	Title           string                 `json:"title"`
	Description     string                 `json:"description"`
	MatchDate       string                 `json:"match_date"`
	DurationMinutes int                    `json:"duration_minutes"`
	Format          string                 `json:"format,omitempty"`
	SpotsTotal      int                    `json:"spots_total"`
	SpotsFilled     int                    `json:"spots_filled"`
	JoinFeeBDT      int                    `json:"join_fee_bdt"`
	PerHeadCostBDT  *int                   `json:"per_head_cost_bdt,omitempty"`
	Status          string                 `json:"status"`
	PostType        string                 `json:"post_type"`
	Latitude        float64                `json:"latitude"`
	Longitude       float64                `json:"longitude"`
	DistanceKm      *float64               `json:"distance_km,omitempty"`
	IsHost          bool                   `json:"is_host"`
	IsJoined        bool                   `json:"is_joined"`
	// MyPaymentStatus / MyRefundStatus surface the caller's own payment row
	// for this match. Only set on /feed/mine and /feed/:id when the caller
	// has paid. Empty string / nil otherwise.
	MyPaymentStatus string  `json:"my_payment_status,omitempty"`
	MyRefundStatus  *string `json:"my_refund_status,omitempty"`
	CreatedAt       string  `json:"created_at"`
}
