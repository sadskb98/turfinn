// Package entity contains pure domain structs for turf onboarding & verification.
package entity

import (
	"time"

	"github.com/google/uuid"
)

type ManagerKYC struct {
	ID               uuid.UUID  `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	UserID           uuid.UUID  `gorm:"column:user_id;uniqueIndex"`
	NIDNumber        string     `gorm:"column:nid_number"`
	NIDPhotoFrontURL string     `gorm:"column:nid_photo_front_url"`
	NIDPhotoBackURL  string     `gorm:"column:nid_photo_back_url"`
	SelfieURL        string     `gorm:"column:selfie_url"`
	BusinessName     string     `gorm:"column:business_name"`
	PayoutAccount    string     `gorm:"column:payout_account"`
	Status           string     `gorm:"column:status"` // draft, submitted, under_review, approved, rejected
	ReviewedBy       *uuid.UUID `gorm:"column:reviewed_by"`
	ReviewNote       string     `gorm:"column:review_note"`
	SubmittedAt      *time.Time `gorm:"column:submitted_at"`
	ReviewedAt       *time.Time `gorm:"column:reviewed_at"`
	CreatedAt        time.Time  `gorm:"column:created_at"`
	UpdatedAt        time.Time  `gorm:"column:updated_at"`

	User *User `gorm:"foreignKey:UserID"`
}

func (ManagerKYC) TableName() string { return "manager_kyc" }

// Review is defined in review.go
