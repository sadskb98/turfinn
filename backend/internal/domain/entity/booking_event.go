package entity

import (
	"time"

	"github.com/google/uuid"
)

// BookingEvent stores a single client-side analytics event.
type BookingEvent struct {
	ID        uuid.UUID `gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	UserID    *uuid.UUID `gorm:"type:uuid;null"`
	SessionID string    `gorm:"column:session_id"`
	EventType string    `gorm:"column:event_type"`
	Metadata  string    `gorm:"column:metadata;type:jsonb"`
	CreatedAt time.Time `gorm:"column:created_at"`
}
