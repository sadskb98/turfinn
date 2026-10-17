// Package service — BookingEventService records analytics events into
// booking_events. Drives the super-admin BI Funnel + cohort views.
//
// The funnel query expects these event_types in order:
//
//	app_open → pitch_search → pitch_view → slot_selected →
//	checkout_started → payment_initiated → booking_confirmed
//
// Plus match-side events:
//
//	match_paid, match_left, match_host_cancelled
package service

import (
	"context"
	"encoding/json"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/turfinn/backend/internal/domain/entity"
)

const (
	EventBookingConfirmed   = "booking_confirmed"
	EventBookingCancelled   = "booking_cancelled"
	EventPaymentInitiated   = "payment_initiated"
	EventMatchPaid          = "match_paid"
	EventMatchLeft          = "match_left"
	EventMatchHostCancelled = "match_host_cancelled"
)

type BookingEventService struct {
	db *gorm.DB
}

func NewBookingEventService(db *gorm.DB) *BookingEventService {
	return &BookingEventService{db: db}
}

// Record inserts a booking event row. Use a nil userID for anonymous
// (pre-login) events. Errors are returned but never panic — callers
// should fire-and-forget (a failed event must not block the user flow).
func (s *BookingEventService) Record(
	ctx context.Context,
	eventType string,
	userID *uuid.UUID,
	sessionID string,
	metadata map[string]any,
) error {
	if eventType == "" {
		return nil
	}
	var meta string
	if len(metadata) > 0 {
		b, _ := json.Marshal(metadata)
		meta = string(b)
	}
	row := entity.BookingEvent{
		UserID:    userID,
		SessionID: sessionID,
		EventType: eventType,
		Metadata:  meta,
		CreatedAt: time.Now(),
	}
	return s.db.WithContext(ctx).Create(&row).Error
}
