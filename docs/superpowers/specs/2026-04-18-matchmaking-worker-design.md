# Matchmaking Worker Refactor — Design Spec

**Date:** 2026-04-18
**Status:** Approved

---

## Problem

The current matchmaking implementation enqueues FCM notifications via an inline `enqueueFCM` helper defined directly on `TeamService`. This is:
- Not retryable (fire-and-forget goroutine, no Asynq queue backing)
- Inconsistent with how every other side effect in the codebase works (gamification, referrals all use proper workers)
- Coupled: FCM payload construction lives inside the service layer

## Approach

Follow the gamification pattern exactly:
- `service` defines task type constants + payload structs
- After each synchronous DB update, service enqueues a typed Asynq task
- A new `MatchWorker` in the `worker` package handles those tasks and calls `EnqueueFCM`

DB state transitions (`FindMatch`, `SetVenue`) remain synchronous — they must return a result to the caller and must be atomic. Only the side effects (FCM notifications) move into workers.

---

## Task Definitions (`team_service.go`)

Remove: `fcmTaskPayload` local struct, `enqueueFCM` helper, `go s.enqueueFCM(...)` calls.

Add:

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

**`FindMatch`** — after `UpdateMatch` sets `AwayTeamID` + `Status = matched`:
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

**`SetVenue`** — after `UpdateMatch` sets pitch + scheduled_at + `Status = confirmed`:
```go
p, _ := json.Marshal(VenueSetPayload{
    MatchID:        matchID.String(),
    OtherCaptainID: otherCaptainID.String(),
    ScheduledAt:    scheduledAt.UTC().Format(time.RFC3339),
})
task := asynq.NewTask(TypeVenueSet, p, asynq.MaxRetry(3), asynq.Queue("critical"))
_, _ = s.asynqClient.Enqueue(task)
```

---

## MatchWorker (`worker/match_worker.go`)

```go
type MatchWorker struct {
    db          *gorm.DB
    asynqClient *asynq.Client
}

func NewMatchWorker(db *gorm.DB, asynqClient *asynq.Client) *MatchWorker
```

### HandleMatchFound

Decodes `MatchFoundPayload`. Calls `EnqueueFCM(w.asynqClient, FCMPayload{...})` to notify the home team captain:
- Title: `"Match Found!"`
- Body: `"An opponent has been matched. Open the app to set the venue."`
- Data: `{"type": "match_found", "match_id": "<id>"}`

### HandleVenueSet

Decodes `VenueSetPayload`. Parses `ScheduledAt`. Calls `EnqueueFCM` to notify the other captain:
- Title: `"Venue Confirmed!"`
- Body: `"Match set for <date>. Open the app for details."`
- Data: `{"type": "venue_set", "match_id": "<id>"}`

Both handlers return `nil` (success) if the captain ID is empty/zero — graceful no-op.

---

## Registration (`worker/worker.go`)

Add:

```go
func RegisterMatchHandlers(mux *asynq.ServeMux, db *gorm.DB, asynqClient *asynq.Client) {
    w := NewMatchWorker(db, asynqClient)
    mux.HandleFunc(service.TypeMatchFound, w.HandleMatchFound)
    mux.HandleFunc(service.TypeVenueSet, w.HandleVenueSet)
}
```

---

## Wire-up (`main.go`)

After existing handler registrations:

```go
worker.RegisterMatchHandlers(mux, db, asynqClient)
```

---

## What Does NOT Change

- `FindMatch` and `SetVenue` DB logic — unchanged, stays synchronous
- `SetVenue` permission check (either captain, first wins)
- `GetActiveMatch` endpoint
- All Flutter code
- FCMWorker — match worker calls `EnqueueFCM`, not the HTTP layer directly

---

## Files Touched

| File | Change |
|------|--------|
| `internal/application/service/team_service.go` | Remove `fcmTaskPayload`, `enqueueFCM`; add `TypeMatchFound`, `TypeVenueSet`, payload structs; enqueue tasks |
| `internal/infrastructure/worker/match_worker.go` | New file — `MatchWorker` with two handlers |
| `internal/infrastructure/worker/worker.go` | Add `RegisterMatchHandlers` |
| `cmd/api/main.go` | Call `RegisterMatchHandlers` |
