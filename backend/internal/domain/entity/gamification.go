package entity

import (
	"time"

	"github.com/google/uuid"
)

type XPEvent struct {
	ID        uuid.UUID  `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	UserID    uuid.UUID  `gorm:"type:uuid;index;not null"`
	Source    string     `gorm:"not null"`
	SourceID  *uuid.UUID `gorm:"type:uuid"`
	Amount    int        `gorm:"not null"`
	CreatedAt time.Time
}

type UserStreak struct {
	ID                     uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	UserID                 uuid.UUID `gorm:"type:uuid;uniqueIndex;not null"`
	CurrentStreak          int       `gorm:"default:0"`
	LongestStreak          int       `gorm:"default:0"`
	LastBookingWeek        int       `gorm:"not null;default:0"`
	LastBookingYear        int       `gorm:"not null;default:0"`
	StreakFreezesRemaining int       `gorm:"default:0"`
	UpdatedAt              time.Time
}

type DailyCheckin struct {
	ID          uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	UserID      uuid.UUID `gorm:"type:uuid;not null"`
	CheckedInAt time.Time `gorm:"type:date;not null"`
	DayInCycle  int       `gorm:"not null"`
	CoinsEarned int       `gorm:"not null"`
}

func (DailyCheckin) TableName() string { return "daily_checkins" }

type ChallengeTemplate struct {
	ID          uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	Slug        string    `gorm:"uniqueIndex;not null"`
	Title       string    `gorm:"not null"`
	Description string
	Type        string `gorm:"not null"`
	Target      int    `gorm:"not null"`
	Difficulty  string `gorm:"not null"`
	CoinReward  int    `gorm:"not null"`
	XPReward    int    `gorm:"not null"`
	Active      bool   `gorm:"default:true"`
}

type WeeklyChallenge struct {
	ID                  uuid.UUID         `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	WeekStart           time.Time         `gorm:"type:date;not null"`
	ChallengeTemplateID uuid.UUID         `gorm:"type:uuid;not null"`
	Template            ChallengeTemplate `gorm:"foreignKey:ChallengeTemplateID"`
}

type UserChallengeProgress struct {
	ID                uuid.UUID  `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	UserID            uuid.UUID  `gorm:"type:uuid;not null"`
	WeeklyChallengeID uuid.UUID  `gorm:"type:uuid;not null"`
	Progress          int        `gorm:"default:0"`
	Completed         bool       `gorm:"default:false"`
	CompletedAt       *time.Time
}

func (UserChallengeProgress) TableName() string { return "user_challenge_progress" }

type LeaderboardEntry struct {
	ID          uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	UserID      uuid.UUID `gorm:"type:uuid;not null"`
	WeekStart   time.Time `gorm:"type:date;not null"`
	Tier        string    `gorm:"not null"`
	XPEarned    int       `gorm:"default:0"`
	Rank        *int
	RewardCoins int `gorm:"default:0"`
}

type ReferralCode struct {
	ID               uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	UserID           uuid.UUID `gorm:"type:uuid;uniqueIndex;not null"`
	Code             string    `gorm:"uniqueIndex;not null"`
	TotalReferrals   int       `gorm:"default:0"`
	TotalCoinsEarned int       `gorm:"default:0"`
	CreatedAt        time.Time
}

type GamificationReferral struct {
	ID            uuid.UUID  `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	ReferrerID    uuid.UUID  `gorm:"type:uuid;not null"`
	ReferredID    uuid.UUID  `gorm:"type:uuid;not null;uniqueIndex"`
	Status        string     `gorm:"default:pending"`
	ReferrerCoins int        `gorm:"default:0"`
	ReferredCoins int        `gorm:"default:0"`
	CompletedAt   *time.Time
	CreatedAt     time.Time
}

func (GamificationReferral) TableName() string { return "referrals" }

var LevelThresholds = []struct {
	Title      string
	XPRequired int
	CoinReward int
}{
	{"Rookie", 0, 0},
	{"Beginner", 200, 50},
	{"Regular", 500, 75},
	{"Enthusiast", 1000, 100},
	{"Veteran", 2000, 150},
	{"Pro", 4000, 200},
	{"Elite", 7500, 300},
	{"Champion", 12000, 500},
	{"Legend", 20000, 750},
	{"GOAT", 35000, 1000},
}
