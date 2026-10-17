package entity

import (
	"time"

	"github.com/google/uuid"
)

type User struct {
	ID                uuid.UUID  `gorm:"type:uuid;primaryKey"`
	Phone             *string    `gorm:"uniqueIndex"`
	Name              string
	AvatarURL         string
	Email             string     `gorm:"column:email"`
	GoogleID          *string    `gorm:"column:google_id;uniqueIndex"`
	Position          string     // Goalkeeper, Defender, Midfielder, Winger, Striker, Flexible
	SkillLevel        string     // Beginner, Intermediate, Advanced, Pro
	Role              UserRole   `gorm:"type:varchar(20);default:'player'"`
	WalletBalancePaisa int64     `gorm:"column:wallet_balance_paisa;default:0"`
	ReferralCode       string    `gorm:"column:referral_code"`
	XP    int `gorm:"column:xp;default:0"`
	Level int `gorm:"column:level;default:1"`
	FCMToken           *string   `gorm:"column:fcm_token"`
	FCMTokenUpdatedAt  *time.Time `gorm:"column:fcm_token_updated_at"`
	LastLat            *float64   `gorm:"column:last_lat"`
	LastLng            *float64   `gorm:"column:last_lng"`
	LocationUpdatedAt  *time.Time `gorm:"column:location_updated_at"`
	// Deactivated users can't authenticate — auth middleware rejects their
	// JWT on the next request. Replaces "demote to player" as the
	// operator's moderation lever.
	IsActive          bool       `gorm:"column:is_active;not null;default:true"`
	CreatedAt          time.Time
	UpdatedAt          time.Time
	DeletedAt          *time.Time `gorm:"index"`
}

type UserRole string

const (
	RolePlayer      UserRole = "player"
	RoleManager     UserRole = "manager"
	RoleAdmin       UserRole = "admin"
	RoleSuperAdmin  UserRole = "super_admin"
	RoleZoneManager UserRole = "zone_manager"
)

func NewUser(phone string) *User {
	return &User{
		ID:    uuid.New(),
		Phone: &phone,
		Role:  RolePlayer,
	}
}
