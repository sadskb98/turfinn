package entity

import (
	"time"

	"github.com/google/uuid"
)

type MatchReport struct {
	ID          uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	ReporterID  uuid.UUID `gorm:"type:uuid;not null;column:reporter_id"`
	MatchPostID uuid.UUID `gorm:"type:uuid;not null;column:match_post_id;index"`
	TargetKind  string    `gorm:"size:20;not null;column:target_kind"` // 'post','venue','host'
	Reason      string    `gorm:"size:40;not null"`                    // 'unsafe_location','no_show','fake','spam','other'
	Note        string    `gorm:"type:text"`
	CreatedAt   time.Time
}

func (MatchReport) TableName() string { return "match_reports" }

type MatchCancellation struct {
	ID            uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	UserID        uuid.UUID `gorm:"type:uuid;not null;column:user_id;index"`
	MatchPostID   uuid.UUID `gorm:"type:uuid;not null;column:match_post_id"`
	Role          string    `gorm:"size:10;not null"` // 'host','joiner'
	CancelledAt   time.Time `gorm:"column:cancelled_at"`
	HoursBefore   int       `gorm:"not null;column:hours_before"`
	FeeForfeited  bool      `gorm:"not null;default:false;column:fee_forfeited"`
}

func (MatchCancellation) TableName() string { return "match_cancellations" }
