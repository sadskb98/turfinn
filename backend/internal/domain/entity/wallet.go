package entity

import (
	"time"

	"github.com/google/uuid"
)

type Wallet struct {
	ID        uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	UserID    uuid.UUID `gorm:"type:uuid;uniqueIndex;not null"`
	Balance   int       `gorm:"not null;default:0"` // in coins (1 coin = 1 BDT)
	CreatedAt time.Time
	UpdatedAt time.Time
}

type WalletTransaction struct {
	ID        uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	WalletID  uuid.UUID `gorm:"type:uuid;index;not null"`
	Amount    int       `gorm:"not null"` // positive = credit, negative = debit
	Type      string    `gorm:"not null"` // topup, booking_payment, reward, refund
	Reference string    // booking ID or badge ID
	CreatedAt time.Time
}

type Badge struct {
	ID          uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	Key         string    `gorm:"uniqueIndex;not null"` // early_bird, regular_player, etc.
	Name        string    `gorm:"not null"`
	Description string
	IconURL     string
	CoinsReward int `gorm:"default:0"`
}

type UserBadge struct {
	ID       uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	UserID   uuid.UUID `gorm:"type:uuid;index;not null"`
	BadgeID  uuid.UUID `gorm:"type:uuid;index;not null"`
	Badge    Badge     `gorm:"foreignKey:BadgeID"`
	EarnedAt time.Time `gorm:"default:now()"`
}
