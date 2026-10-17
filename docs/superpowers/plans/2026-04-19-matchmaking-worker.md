# Matchmaking Worker Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace inline FCM goroutines in `TeamService` with proper Asynq worker tasks, following the gamification pattern already in the codebase.

**Architecture:** DB state changes in `FindMatch` and `SetVenue` stay synchronous. After each DB commit, the service enqueues a typed Asynq task. A new `MatchWorker` in the `worker` package handles those tasks and calls `EnqueueFCM`.

**Tech Stack:** Go, Asynq (`github.com/hibiken/asynq`), GORM, zerolog

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `backend/internal/application/service/team_service.go` | Modify | Remove `fcmTaskPayload` + `enqueueFCM`; add `TypeMatchFound`, `TypeVenueSet`, `MatchFoundPayload`, `VenueSetPayload`; enqueue tasks after DB updates |
| `backend/internal/infrastructure/worker/match_worker.go` | Create | `MatchWorker` struct + `HandleMatchFound` + `HandleVenueSet` |
| `backend/internal/infrastructure/worker/match_worker_test.go` | Create | Unit tests for both handlers (no-op path + decode path) |
| `backend/internal/infrastructure/worker/worker.go` | Modify | Add `RegisterMatchHandlers` |
| `backend/cmd/api/main.go` | Modify | Call `worker.RegisterMatchHandlers(mux, db, asynqClient)` |

---

### Task 1: Add task type constants and payload structs to `team_service.go`

**Files:**
- Modify: `backend/internal/application/service/team_service.go`

- [ ] **Step 1: Remove the inline FCM helpers**

In `team_service.go`, delete the `fcmTaskPayload` struct and the `enqueueFCM` method entirely. These are the lines to remove:

```go
// DELETE this entire block:
type fcmTaskPayload struct {
    UserID string            `json:"user_id"`
    Title  string            `json:"title"`
    Body   string            `json:"body"`
    Data   map[string]string `json:"data,omitempty"`
}

// DELETE this entire method:
func (s *TeamService) enqueueFCM(userID uuid.UUID, title, body string, data map[string]string) {
    if s.asynqClient == nil {
        return
    }
    p, err := json.Marshal(fcmTaskPayload{UserID: userID.String(), Title: title, Body: body, Data: data})
    if err != nil {
        return
    }
    task := asynq.NewTask("fcm:send", p, asynq.MaxRetry(3), asynq.Queue("critical"))
    _, _ = s.asynqClient.Enqueue(task)
}
```

- [ ] **Step 2: Add task type constants and payload structs**

Add these directly after the `var (...)` error block (before `type TeamService struct`):

```go
const (
    TypeMatchFound = "match:found"
    TypeVenueSet   = "match:venue_set"
)

type MatchFoundPayload struct {
    MatchID       string `json:"match_id"`
    HomeCaptainID string `json:"home_captain_id"`
}

type VenueSetPayload struct {
    MatchID        string `json:"match_id"`
    OtherCaptainID string `json:"other_captain_id"`
    ScheduledAt    string `json:"scheduled_at"` // RFC3339 UTC
}
```

- [ ] **Step 3: Verify build (expected: compile error — enqueueFCM calls still exist)**

```bash
cd backend && go build ./...
```

Expected: errors referencing `s.enqueueFCM` — confirms the helpers are gone and callers need updating.

---

### Task 2: Replace `enqueueFCM` call in `FindMatch`

**Files:**
- Modify: `backend/internal/application/service/team_service.go`

- [ ] **Step 1: Replace the goroutine in `FindMatch`**

Find this block inside `FindMatch` (the goroutine that fires FCM to the home team captain):

```go
// FCM to home team captain: they've been waiting, prompt them to set the venue
if existing.HomeTeam != nil {
    go s.enqueueFCM(existing.HomeTeam.CaptainID,
        "Match Found!",
        "An opponent has been matched. Open the app to set the venue.",
        map[string]string{"type": "match_found", "match_id": existing.ID.String()},
    )
}
```

Replace with:

```go
if existing.HomeTeam != nil {
    p, _ := json.Marshal(MatchFoundPayload{
        MatchID:       existing.ID.String(),
        HomeCaptainID: existing.HomeTeam.CaptainID.String(),
    })
    task := asynq.NewTask(TypeMatchFound, p, asynq.MaxRetry(3), asynq.Queue("critical"))
    _, _ = s.asynqClient.Enqueue(task)
}
```

- [ ] **Step 2: Verify build (expected: one remaining error in `SetVenue`)**

```bash
cd backend && go build ./...
```

Expected: one compile error about `enqueueFCM` or `go s.enqueueFCM` still in `SetVenue`.

---

### Task 3: Replace `enqueueFCM` call in `SetVenue`

**Files:**
- Modify: `backend/internal/application/service/team_service.go`

- [ ] **Step 1: Replace the goroutine in `SetVenue`**

Find this block inside `SetVenue`:

```go
if otherCaptainID != uuid.Nil {
    go s.enqueueFCM(otherCaptainID,
        "Venue Confirmed!",
        fmt.Sprintf("Match set for %s. Open the app for details.", scheduledStr),
        map[string]string{"type": "venue_set", "match_id": matchID.String()},
    )
}
```

Replace with:

```go
if otherCaptainID != uuid.Nil {
    p, _ := json.Marshal(VenueSetPayload{
        MatchID:        matchID.String(),
        OtherCaptainID: otherCaptainID.String(),
        ScheduledAt:    scheduledAt.UTC().Format(time.RFC3339),
    })
    task := asynq.NewTask(TypeVenueSet, p, asynq.MaxRetry(3), asynq.Queue("critical"))
    _, _ = s.asynqClient.Enqueue(task)
}
```

- [ ] **Step 2: Remove now-unused `fmt` import if needed**

Check if `fmt` is still used elsewhere in `team_service.go`. The `scheduledStr` variable used `fmt.Sprintf` — that line is now gone. If `fmt` is the only usage, remove it from the import block.

Run:
```bash
cd backend && go build ./...
```

Expected: clean build, zero errors.

- [ ] **Step 3: Commit**

```bash
cd backend && git add internal/application/service/team_service.go
git commit -m "refactor: replace inline FCM goroutines with typed Asynq tasks in TeamService"
```

---

### Task 4: Create `match_worker.go`

**Files:**
- Create: `backend/internal/infrastructure/worker/match_worker.go`

- [ ] **Step 1: Write the failing test first**

Create `backend/internal/infrastructure/worker/match_worker_test.go`:

```go
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
```

- [ ] **Step 2: Run tests — expect compile failure (MatchWorker not defined yet)**

```bash
cd backend && go test ./internal/infrastructure/worker/...
```

Expected: compile error — `worker.NewMatchWorker undefined`.

- [ ] **Step 3: Create `match_worker.go`**

Create `backend/internal/infrastructure/worker/match_worker.go`:

```go
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

type MatchWorker struct {
	db          *gorm.DB
	asynqClient *asynq.Client
}

func NewMatchWorker(db *gorm.DB, asynqClient *asynq.Client) *MatchWorker {
	return &MatchWorker{db: db, asynqClient: asynqClient}
}

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
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd backend && go test ./internal/infrastructure/worker/... -v -run TestHandle
```

Expected output:
```
--- PASS: TestHandleMatchFound_EmptyCaptain (0.00s)
--- PASS: TestHandleVenueSet_EmptyCaptain (0.00s)
--- PASS: TestHandleMatchFound_InvalidPayload (0.00s)
--- PASS: TestHandleVenueSet_InvalidPayload (0.00s)
PASS
```

- [ ] **Step 5: Commit**

```bash
cd backend && git add internal/infrastructure/worker/match_worker.go internal/infrastructure/worker/match_worker_test.go
git commit -m "feat: add MatchWorker handling match:found and match:venue_set tasks"
```

---

### Task 5: Register handlers in `worker.go`

**Files:**
- Modify: `backend/internal/infrastructure/worker/worker.go`

- [ ] **Step 1: Add `RegisterMatchHandlers`**

Open `backend/internal/infrastructure/worker/worker.go`. After the existing `RegisterHandlers` function, add:

```go
// RegisterMatchHandlers wires match:found and match:venue_set handlers onto the mux.
func RegisterMatchHandlers(mux *asynq.ServeMux, db *gorm.DB, asynqClient *asynq.Client) {
	w := NewMatchWorker(db, asynqClient)
	mux.HandleFunc(service.TypeMatchFound, w.HandleMatchFound)
	mux.HandleFunc(service.TypeVenueSet, w.HandleVenueSet)
}
```

The existing import block already has `gorm.io/gorm` and `github.com/hibiken/asynq`. Add the `service` import:

```go
import (
    "github.com/hibiken/asynq"
    "github.com/rs/zerolog/log"
    "github.com/spf13/viper"
    "gorm.io/gorm"

    "github.com/turfinn/backend/internal/application/service"
)
```

- [ ] **Step 2: Build check**

```bash
cd backend && go build ./...
```

Expected: clean build.

---

### Task 6: Wire up in `main.go`

**Files:**
- Modify: `backend/cmd/api/main.go`

- [ ] **Step 1: Add `RegisterMatchHandlers` call**

In `main.go`, find the block where other handlers are registered on the mux. It looks like:

```go
mux := asynq.NewServeMux()
worker.RegisterGamificationHandlers(mux, gamificationSvc, walletSvc)
```

Add the match handler registration immediately after:

```go
worker.RegisterMatchHandlers(mux, db, asynqClient)
```

- [ ] **Step 2: Final build check**

```bash
cd backend && go build ./...
```

Expected: clean build, zero errors or warnings.

- [ ] **Step 3: Run all tests**

```bash
cd backend && go test ./...
```

Expected: all tests pass (or pre-existing failures only — none introduced by this change).

- [ ] **Step 4: Commit**

```bash
cd backend && git add internal/infrastructure/worker/worker.go cmd/api/main.go
git commit -m "feat: register MatchWorker handlers and wire into main"
```

---

### Task 7: Smoke test via Docker

- [ ] **Step 1: Rebuild and restart API + worker containers**

```bash
docker compose build api worker && docker compose restart api worker
```

- [ ] **Step 2: Tail logs and verify no startup errors**

```bash
docker compose logs api worker --tail 30 -f
```

Expected: both containers start cleanly. Watch for any `asynq` handler registration log lines confirming `match:found` and `match:venue_set` are registered.

- [ ] **Step 3: Trigger matchmaking end-to-end**

Using two authenticated sessions (or the mobile APK with two accounts):
1. Team A calls `POST /api/v1/matchmaking/find` — gets `status: searching`
2. Team B calls `POST /api/v1/matchmaking/find` — gets `status: matched`
3. Check `docker compose logs worker --tail 20` — should show the `match:found` task being processed
4. Team B calls `PUT /api/v1/matchmaking/:id/venue` with a pitch ID and future `scheduled_at`
5. Check worker logs again — should show `match:venue_set` task processed

Expected worker log lines:
```
INF FCM notification sent user_id=<home-captain-id> title="Match Found!"
INF FCM notification sent user_id=<away-captain-id> title="Venue Confirmed!"
```

(FCM will only actually deliver if `FIREBASE_SERVICE_ACCOUNT_JSON` is set. The worker will log "no FCM token, skipping" otherwise — which is still a successful task execution.)
