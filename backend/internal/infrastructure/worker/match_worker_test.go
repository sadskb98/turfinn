package worker_test

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/hibiken/asynq"
	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/infrastructure/worker"
)

func TestHandleMatchFound_EmptyCaptain(t *testing.T) {
	w := worker.NewMatchWorker(nil, nil)
	p, _ := json.Marshal(service.MatchFoundPayload{
		MatchID:       "00000000-0000-0000-0000-000000000001",
		HomeCaptainID: "",
	})
	task := asynq.NewTask(service.TypeMatchFound, p)
	err := w.HandleMatchFound(context.Background(), task)
	if err != nil {
		t.Errorf("expected nil for empty captain, got: %v", err)
	}
}

func TestHandleVenueSet_EmptyCaptain(t *testing.T) {
	w := worker.NewMatchWorker(nil, nil)
	p, _ := json.Marshal(service.VenueSetPayload{
		MatchID:        "00000000-0000-0000-0000-000000000002",
		OtherCaptainID: "",
		ScheduledAt:    "2026-04-20T19:00:00Z",
	})
	task := asynq.NewTask(service.TypeVenueSet, p)
	err := w.HandleVenueSet(context.Background(), task)
	if err != nil {
		t.Errorf("expected nil for empty captain, got: %v", err)
	}
}

func TestHandleMatchFound_InvalidPayload(t *testing.T) {
	w := worker.NewMatchWorker(nil, nil)
	task := asynq.NewTask(service.TypeMatchFound, []byte("not-json"))
	err := w.HandleMatchFound(context.Background(), task)
	if err == nil {
		t.Error("expected error for invalid JSON payload")
	}
}

func TestHandleVenueSet_InvalidPayload(t *testing.T) {
	w := worker.NewMatchWorker(nil, nil)
	task := asynq.NewTask(service.TypeVenueSet, []byte("not-json"))
	err := w.HandleVenueSet(context.Background(), task)
	if err == nil {
		t.Error("expected error for invalid JSON payload")
	}
}
