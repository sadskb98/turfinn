package handler

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/interfaces/dto"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
	"gorm.io/gorm"
)

type EventsHandler struct {
	db *gorm.DB
}

func NewEventsHandler(db *gorm.DB) *EventsHandler {
	return &EventsHandler{db: db}
}

// POST /api/v1/events — batch event ingestion (auth optional)
func (h *EventsHandler) Track(c echo.Context) error {
	var req dto.TrackEventsRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	// Extract optional user ID (OptionalAuth middleware sets it only if JWT is valid)
	var userID *uuid.UUID
	if raw := c.Get(authmw.UserIDKey); raw != nil {
		if id, ok := raw.(uuid.UUID); ok && id != uuid.Nil {
			userID = &id
		}
	}

	events := make([]entity.BookingEvent, 0, len(req.Events))
	for _, e := range req.Events {
		meta, err := json.Marshal(e.Metadata)
		if err != nil {
			return response.BadRequest(c, "invalid metadata")
		}
		ts := time.Now()
		if e.OccurredAt != nil {
			ts = *e.OccurredAt
		}
		ev := entity.BookingEvent{
			SessionID: e.SessionID,
			EventType: e.EventType,
			Metadata:  string(meta),
			CreatedAt: ts,
		}
		if userID != nil {
			ev.UserID = userID
		}
		events = append(events, ev)
	}

	if err := h.db.WithContext(c.Request().Context()).Create(&events).Error; err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]int{"ingested": len(events)})
}
