package entity

import (
	"time"

	"github.com/google/uuid"
)

type MatchStanding struct {
	ID         uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	LeagueID   int       `gorm:"not null;uniqueIndex:uq_standings_league_season;column:league_id"`
	Season     int       `gorm:"not null;uniqueIndex:uq_standings_league_season"`
	LeagueName string    `gorm:"size:120;column:league_name"`
	LeagueLogo string    `gorm:"column:league_logo"`
	Payload    []byte    `gorm:"type:jsonb;not null"`
	FetchedAt  time.Time `gorm:"column:fetched_at"`
	UpdatedAt  time.Time
}

func (MatchStanding) TableName() string { return "match_standings" }
