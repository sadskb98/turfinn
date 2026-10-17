package entity

import (
	"time"

	"github.com/google/uuid"
)

type MatchEvent struct {
	ID           uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	Source       string    `gorm:"size:20;not null;uniqueIndex:uq_match_events_source_id"`
	SourceID     string    `gorm:"size:50;not null;uniqueIndex:uq_match_events_source_id;column:source_id"`
	LeagueID     *int      `gorm:"column:league_id;index"`
	League       string    `gorm:"size:120"`
	LeagueLogo   string    `gorm:"column:league_logo"`
	HomeTeam     string    `gorm:"size:120;not null;column:home_team"`
	HomeLogo     string    `gorm:"column:home_logo"`
	AwayTeam     string    `gorm:"size:120;not null;column:away_team"`
	AwayLogo     string    `gorm:"column:away_logo"`
	HomeScore    *int      `gorm:"column:home_score"`
	AwayScore    *int      `gorm:"column:away_score"`
	KickoffAt    time.Time `gorm:"not null;index:idx_match_events_kickoff_at,sort:desc;column:kickoff_at"`
	Status       string    `gorm:"size:20;not null;index"` // 'live','scheduled','finished'
	MinutePlayed *int      `gorm:"column:minute_played"`
	Payload      []byte    `gorm:"type:jsonb"`
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

func (MatchEvent) TableName() string { return "match_events" }
