package entity

import (
	"time"

	"github.com/google/uuid"
)

// Review represents a pitch review. Used by both player-facing and admin handlers.
type Review struct {
	ID            uuid.UUID  `gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	PitchID       uuid.UUID  `gorm:"type:uuid;not null"`
	UserID        uuid.UUID  `gorm:"type:uuid;not null"`
	BookingID     *uuid.UUID `gorm:"type:uuid"`
	Rating        int16      `gorm:"not null"`
	Comment       string     `gorm:"type:text"`
	Status        string     `gorm:"column:status;default:'active'"` // active, flagged, removed
	FlaggedReason string     `gorm:"column:flagged_reason"`
	ModeratedBy   *uuid.UUID `gorm:"column:moderated_by"`
	CreatedAt     time.Time  `gorm:"autoCreateTime"`
	UpdatedAt     time.Time  `gorm:"autoUpdateTime"`

	User  *User  `gorm:"foreignKey:UserID"`
	Pitch *Pitch `gorm:"foreignKey:PitchID"`
}

func (Review) TableName() string { return "reviews" }
