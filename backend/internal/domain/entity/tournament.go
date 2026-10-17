package entity

import (
	"time"

	"github.com/google/uuid"
)

type Tournament struct {
	ID          uuid.UUID        `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	CreatorID   uuid.UUID        `gorm:"type:uuid;not null"`
	Creator     *User            `gorm:"foreignKey:CreatorID"`
	Name        string           `gorm:"not null"`
	Description string
	Format      string           `gorm:"not null"`
	MaxTeams    int              `gorm:"not null;default:8"`
	EntryFee    int              `gorm:"default:0"`
	MinCoins    int              `gorm:"default:0"`
	PrizePool   int              `gorm:"default:0"`
	Visibility  string           `gorm:"not null;default:public"`
	InviteCode  *string          `gorm:"uniqueIndex"`
	Status      TournamentStatus `gorm:"type:varchar(20);default:draft"`
	StartsAt    *time.Time
	CreatedAt   time.Time
	UpdatedAt   time.Time

	Teams   []TournamentTeam  `gorm:"foreignKey:TournamentID"`
	Matches []TournamentMatch `gorm:"foreignKey:TournamentID"`
}

func (Tournament) TableName() string { return "tournaments" }

type TournamentStatus string

const (
	TournamentDraft        TournamentStatus = "draft"
	TournamentRegistration TournamentStatus = "registration_open"
	TournamentInProgress   TournamentStatus = "in_progress"
	TournamentCompleted    TournamentStatus = "completed"
	TournamentCancelled    TournamentStatus = "cancelled"
)

type TournamentTeam struct {
	ID           uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TournamentID uuid.UUID `gorm:"type:uuid;not null"`
	TeamID       uuid.UUID `gorm:"type:uuid;not null"`
	Team         *Team     `gorm:"foreignKey:TeamID"`
	Seed         *int
	Eliminated   bool      `gorm:"default:false"`
	RegisteredAt time.Time
}

func (TournamentTeam) TableName() string { return "tournament_teams" }

type TournamentMatch struct {
	ID           uuid.UUID             `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TournamentID uuid.UUID             `gorm:"type:uuid;not null"`
	Round        int                   `gorm:"not null"`
	MatchOrder   int                   `gorm:"not null"`
	HomeTeamID   *uuid.UUID            `gorm:"type:uuid"`
	HomeTeam     *Team                 `gorm:"foreignKey:HomeTeamID"`
	AwayTeamID   *uuid.UUID            `gorm:"type:uuid"`
	AwayTeam     *Team                 `gorm:"foreignKey:AwayTeamID"`
	HomeScore    *int
	AwayScore    *int
	WinnerID     *uuid.UUID            `gorm:"type:uuid"`
	Winner       *Team                 `gorm:"foreignKey:WinnerID"`
	Status       TournamentMatchStatus `gorm:"type:varchar(20);default:pending"`
	ReportedBy   *uuid.UUID            `gorm:"type:uuid"`
	ConfirmedBy  *uuid.UUID            `gorm:"type:uuid"`
	ReportedAt   *time.Time
	ConfirmedAt  *time.Time
	ScheduledAt  *time.Time
	CreatedAt    time.Time
}

func (TournamentMatch) TableName() string { return "tournament_matches" }

type TournamentMatchStatus string

const (
	TMatchPending   TournamentMatchStatus = "pending"
	TMatchReady     TournamentMatchStatus = "ready"
	TMatchReported  TournamentMatchStatus = "reported"
	TMatchConfirmed TournamentMatchStatus = "confirmed"
	TMatchDisputed  TournamentMatchStatus = "disputed"
	TMatchBye       TournamentMatchStatus = "bye"
)

type TournamentDispute struct {
	ID                uuid.UUID  `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TournamentMatchID uuid.UUID  `gorm:"type:uuid;not null"`
	DisputerID        uuid.UUID  `gorm:"type:uuid;not null"`
	Reason            string
	Status            string     `gorm:"default:open"`
	ResolvedBy        *uuid.UUID `gorm:"type:uuid"`
	ResolvedAt        *time.Time
	CreatedAt         time.Time
}

func (TournamentDispute) TableName() string { return "tournament_disputes" }
