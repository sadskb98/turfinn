package entity

import (
	"time"

	"github.com/google/uuid"
)

type ExternalPitch struct {
	ID             uuid.UUID  `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	Name           string     `gorm:"size:160;not null"`
	NormalizedName string     `gorm:"size:160;not null;column:normalized_name;index"`
	Address        string     `gorm:"type:text"`
	Latitude       float64    `gorm:"not null"`
	Longitude      float64    `gorm:"not null"`
	CreatedBy      *uuid.UUID `gorm:"type:uuid;column:created_by"`
	RefCount       int        `gorm:"not null;default:1;column:ref_count"`
	Verified       bool       `gorm:"not null;default:false"`
	ClaimedAt      *time.Time `gorm:"column:claimed_at"`
	CreatedAt      time.Time
	UpdatedAt      time.Time
}

func (ExternalPitch) TableName() string { return "external_pitches" }
