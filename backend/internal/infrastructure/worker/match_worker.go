package worker

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/rs/zerolog/log"
	"gorm.io/gorm"

	"github.com/turfinn/backend/internal/application/service"
)

// MatchWorker handles async tasks produced by the matchmaking service.
// The db field is available for future handlers that need to load match data.
type MatchWorker struct {
	db          *gorm.DB
	asynqClient *asynq.Client
}

func NewMatchWorker(db *gorm.DB, asynqClient *asynq.Client) *MatchWorker {
	return &MatchWorker{db: db, asynqClient: asynqClient}
}

// HandleMatchFound processes a match:found task and sends an FCM notification
// to the home team's captain informing them that an opponent has been matched.
func (w *MatchWorker) HandleMatchFound(ctx context.Context, t *asynq.Task) error {
	var p service.MatchFoundPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("match_worker: decode match_found payload: %w", err)
	}
	if p.HomeCaptainID == "" {
		log.Debug().Msg("match_worker: match_found — empty home captain ID, skipping FCM")
		return nil
	}
	captainID, err := uuid.Parse(p.HomeCaptainID)
	if err != nil {
		return fmt.Errorf("match_worker: parse home_captain_id: %w", err)
	}
	return EnqueueFCM(w.asynqClient, FCMPayload{
		UserID: captainID,
		Title:  "Match Found!",
		Body:   "An opponent has been matched. Open the app to set the venue.",
		Data: map[string]string{
			"type":     "match_found",
			"match_id": p.MatchID,
		},
	})
}

// HandleVenueSet processes a match:venue_set task and sends an FCM notification
// to the other team's captain informing them that the venue has been confirmed.
func (w *MatchWorker) HandleVenueSet(ctx context.Context, t *asynq.Task) error {
	var p service.VenueSetPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("match_worker: decode venue_set payload: %w", err)
	}
	if p.OtherCaptainID == "" {
		log.Debug().Msg("match_worker: venue_set — empty captain ID, skipping FCM")
		return nil
	}
	captainID, err := uuid.Parse(p.OtherCaptainID)
	if err != nil {
		return fmt.Errorf("match_worker: parse other_captain_id: %w", err)
	}
	scheduledAt, err := time.Parse(time.RFC3339, p.ScheduledAt)
	if err != nil {
		return fmt.Errorf("match_worker: parse scheduled_at: %w", err)
	}
	body := fmt.Sprintf("Match set for %s. Open the app for details.",
		scheduledAt.Local().Format("Jan 2, 3:04 PM"))
	return EnqueueFCM(w.asynqClient, FCMPayload{
		UserID: captainID,
		Title:  "Venue Confirmed!",
		Body:   body,
		Data: map[string]string{
			"type":     "venue_set",
			"match_id": p.MatchID,
		},
	})
}
