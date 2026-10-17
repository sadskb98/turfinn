package dto

import "time"

// TrackEventRequest is one analytics event from the Flutter client.
type TrackEventRequest struct {
	EventType  string         `json:"event_type"  validate:"required,max=50"`
	SessionID  string         `json:"session_id"  validate:"required,max=100"`
	Metadata   map[string]any `json:"metadata"`
	OccurredAt *time.Time     `json:"occurred_at"` // optional; defaults to server time
}

// TrackEventsRequest is a batch of events (max 50 per call).
type TrackEventsRequest struct {
	Events []TrackEventRequest `json:"events" validate:"required,min=1,max=50,dive"`
}
