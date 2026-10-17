package entity

import (
	"time"

	"github.com/google/uuid"
)

type NewsItem struct {
	ID          uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	Source      string    `gorm:"size:20;not null;uniqueIndex:uq_news_source_id"`
	SourceID    string    `gorm:"size:255;not null;uniqueIndex:uq_news_source_id;column:source_id"`
	Category    string    `gorm:"size:50;index"`
	LeagueID    *int      `gorm:"column:league_id;index"` // nil = not league-tagged
	Title       string    `gorm:"not null"`
	Summary     string
	URL         string `gorm:"not null;column:url"`
	ImageURL    string `gorm:"column:image_url"`
	SourceName  string `gorm:"size:120;column:source_name"`
	PublishedAt time.Time `gorm:"not null;index:idx_news_published_at,sort:desc;column:published_at"`
	Payload     []byte    `gorm:"type:jsonb"`
	CreatedAt   time.Time
}

func (NewsItem) TableName() string { return "news_items" }
