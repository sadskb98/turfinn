package entity

import (
	"time"

	"github.com/google/uuid"
)

type MatchPost struct {
	ID              uuid.UUID      `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	AuthorID        uuid.UUID      `gorm:"type:uuid;not null;index"`
	Author          User           `gorm:"foreignKey:AuthorID"`
	PitchID         *uuid.UUID     `gorm:"type:uuid;index"`
	Pitch           *Pitch         `gorm:"foreignKey:PitchID"`
	ExternalPitchID *uuid.UUID     `gorm:"type:uuid;column:external_pitch_id;index"`
	ExternalPitch   *ExternalPitch `gorm:"foreignKey:ExternalPitchID"`
	Title           string         `gorm:"not null"`
	Description     string
	MatchDate       time.Time `gorm:"not null"`
	DurationMinutes int       `gorm:"not null;default:90"`
	Format          string    `gorm:"size:10"` // '5v5','6v6','7v7','11v11' — nullable
	SpotsTotal      int       `gorm:"not null;default:10"`
	SpotsFilled     int       `gorm:"not null;default:1"`
	JoinFeeBDT      int       `gorm:"not null;default:20;column:join_fee_bdt"`
	PerHeadCostBDT  *int      `gorm:"column:per_head_cost_bdt"` // null = unspecified / non-Turfinn
	ExpiresAt       *time.Time `gorm:"column:expires_at"`
	Status          string    `gorm:"not null;default:'open'"` // open, full, cancelled, completed
	PostType        string    `gorm:"not null;default:'open_match'"`
	Latitude        float64   `gorm:"not null;default:0"`
	Longitude       float64   `gorm:"not null;default:0"`

	// Quorum-first booking link. When the match hits its quorum, the system
	// auto-creates a Booking row on the pitch and stores its ID here.
	// Subsequent quorum-check passes use this to skip duplicate creation.
	BookingID    *uuid.UUID `gorm:"column:booking_id"`
	QuorumMinPct int        `gorm:"column:quorum_min_pct;not null;default:50"`

	CreatedAt time.Time
	UpdatedAt time.Time
}

type MatchPostJoin struct {
	ID       uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	PostID   uuid.UUID `gorm:"type:uuid;not null;index"`
	UserID   uuid.UUID `gorm:"type:uuid;not null;index"`
	JoinedAt time.Time `gorm:"default:now()"`
}
