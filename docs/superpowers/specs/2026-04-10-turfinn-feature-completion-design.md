# Turfinn Feature Completion Design
**Date:** 2026-04-10  
**Status:** Approved  
**Scope:** Wave 1 + Wave 2 feature implementation

---

## Overview

Turfinn is ~70% feature-complete. This spec covers the 7 remaining feature sub-systems needed before beta launch, organized into two sequential build waves.

**Out of scope (later):** SMS OTP delivery, bKash/Nagad payment gateway, Apple OAuth, offline mode, in-app receipt PDF, map view.

---

## Build Waves

```
Wave 1 (parallel, no interdependencies)
├── MinIO image uploads
├── Google OAuth
├── Analytics instrumentation
├── Reviews & ratings
└── Background workers (Asynq)  ← Wave 2 depends on this

Wave 2 (after Wave 1 lands)
├── FCM push notifications       (needs Asynq from Wave 1)
└── WebSocket real-time          (team chat + live status updates)
```

---

## Infrastructure Changes

### docker-compose.yml additions
- **MinIO** container with `minio_data` volume, ports `9000` (API) + `9001` (console)
- No new containers for Wave 2 — FCM and WebSocket run inside the existing `app` service

### New environment variables
```
# MinIO
MINIO_ENDPOINT=minio:9000
MINIO_ACCESS_KEY=...
MINIO_SECRET_KEY=...
MINIO_USE_SSL=false

# Google OAuth
GOOGLE_CLIENT_ID=...

# Firebase FCM (Wave 2)
FIREBASE_SERVICE_ACCOUNT_JSON=...
```

---

## Wave 1

### 1. MinIO Image Uploads

**Goal:** Replace placeholder image URL strings with real file uploads stored in self-hosted MinIO.

**Backend:**
- Add MinIO Go client (`github.com/minio/minio-go/v7`) to `go.mod`
- `internal/infrastructure/storage/minio.go` — MinIO client factory, `GeneratePresignedPutURL(bucket, key string, ttl time.Duration) (string, error)`
- Buckets: `avatars`, `pitch-images`, `kyc-documents` (auto-created on startup if missing)
- New endpoint: `POST /api/v1/upload/presign?bucket=avatars&filename=photo.jpg`
  - Auth required
  - Validates bucket name against allowed list
  - Returns `{ url: "<presigned PUT URL>", key: "<object key>", expires_at: "..." }`
- Helper `storage.PublicURL(bucket, key string) string` builds the full MinIO URL for read responses
- No schema migrations needed — `avatar_url`, `image_urls` (JSONB), `nid_photo_url`, `selfie_url` columns already exist

**Flutter:**
- Add `image_picker: ^1.x` to `pubspec.yaml`
- `lib/data/sources/remote/upload_remote_source.dart` — `getPresignedUrl(bucket, filename)`, `uploadFile(presignedUrl, file)`
- `lib/presentation/providers/upload_provider.dart` — `uploadImage(bucket, file)` returns final object key
- Integrated into: avatar field (ProfileSetupScreen, PersonalInfoScreen), pitch photos (ManagePanelScreen CreatePitch form), KYC documents (FinancialInfoScreen)

---

### 2. Google OAuth

**Goal:** Allow users to sign in with Google as an alternative to phone OTP.

**Backend:**
- New migration `005_google_oauth.sql`:
  ```sql
  ALTER TABLE users ADD COLUMN google_id VARCHAR(255) UNIQUE NULL;
  ```
- New endpoint: `POST /api/v1/auth/google`
  - Body: `{ id_token: string }`
  - Verifies ID token via `https://oauth2.googleapis.com/tokeninfo?id_token=<token>`
  - Upsert logic: find by `google_id` → fallback find by email → create new user
  - Returns same JWT response shape as `/auth/verify-otp`
- `internal/application/service/auth_service.go` — add `GoogleSignIn(ctx, idToken string) (*entity.User, string, error)`
- `internal/interfaces/dto/auth_dto.go` — add `GoogleSignInRequest { IDToken string }`

**Flutter:**
- Add `google_sign_in: ^6.x` to `pubspec.yaml`
- `lib/data/sources/remote/auth_remote_source.dart` — add `googleSignIn(idToken)`
- `lib/presentation/providers/auth_provider.dart` — add `signInWithGoogle()` method
- Add "Continue with Google" button to `WelcomeScreen`, `SignInScreen`, `SignUpScreen`
- On success: same JWT storage + navigation path as OTP verify success

---

### 3. Analytics Instrumentation

**Goal:** Fire structured events from the Flutter client to the existing `booking_events` backend table.

**Backend:**
- `POST /api/v1/events` endpoint already in router — wire handler to insert into `booking_events` table (batch insert for efficiency)
- `internal/interfaces/dto/superadmin_dto.go` — add `TrackEventsRequest { Events []EventPayload }`
- `EventPayload { EventName string, Properties map[string]any, OccurredAt time.Time }`
- User ID extracted from JWT if authenticated; `NULL` allowed for anonymous events (app_open before login)

**Flutter:**
- `lib/data/sources/remote/analytics_remote_source.dart` — `trackEvents(events [])`
- `lib/core/analytics/analytics_client.dart` — singleton:
  - In-memory queue (max 50 events)
  - Auto-flush: every 30 seconds OR when queue reaches 10 events
  - Flush runs via `Timer.periodic` in a background isolate
  - Events persisted to SharedPreferences on app pause (survive crashes)
- Events fired:
  | Event | Where fired |
  |---|---|
  | `app_open` | `main.dart` on startup |
  | `screen_view` | GoRouter `redirect` observer |
  | `pitch_view` | `TurfDetailScreen` init |
  | `checkout_started` | `CheckoutScreen` init |
  | `booking_confirmed` | After successful booking creation |
  | `team_created` | After `CreateTeam` success |
  | `match_found` | When matchmaking status → matched |
  | `google_sign_in` | After Google OAuth success |

---

### 4. Reviews & Ratings

**Goal:** Players can rate and review pitches post-booking; avg rating displayed on pitch detail.

**Backend:**
- `reviews` table already in migration 004. Schema: `id, pitch_id, user_id, booking_id, rating (1-5), comment, is_flagged, created_at`
- `internal/domain/repository/pitch_repository.go` — add to interface:
  - `CreateReview(ctx, review *entity.Review) error`
  - `ListReviews(ctx, pitchID uuid.UUID, page, limit int) ([]entity.Review, int64, error)`
  - `GetAverageRating(ctx, pitchID uuid.UUID) (float64, int64, error)`
- `internal/infrastructure/repository/pitch_repository.go` — implement above; `GetAverageRating` uses `SELECT AVG(rating), COUNT(*) FROM reviews WHERE pitch_id = ?` cached in Redis key `pitch:rating:{id}` with 10-min TTL; invalidated on `CreateReview`
- `internal/application/service/pitch_service.go` — add `SubmitReview`, `GetReviews`; enforce one-review-per-booking constraint
- New endpoints:
  - `POST /api/v1/pitches/:id/reviews` (auth required) — body: `{ booking_id, rating, comment }`
  - `GET /api/v1/pitches/:id/reviews?page=1&limit=10` (public)
- `GetPitch` response extended with `avg_rating float64`, `review_count int`

**Flutter:**
- `lib/data/models/review_model.dart` — `ReviewModel` (freezed)
- `lib/data/sources/remote/pitch_remote_source.dart` — add `submitReview(pitchId, bookingId, rating, comment)`, `getReviews(pitchId, page, limit)`
- `lib/presentation/providers/review_provider.dart` — `reviewsProvider(pitchId)`, `submitReviewProvider`
- `TurfDetailScreen` additions:
  - Avg rating display (stars + number) below pitch name
  - Scrollable review list (max 5 shown, "see all" expands)
  - "Leave a review" button — visible only if user has a completed booking for this pitch and hasn't reviewed yet

---

### 5. Background Workers (Asynq)

**Goal:** Async job processing infrastructure for referral rewards (Wave 1) and as foundation for FCM dispatch (Wave 2).

**Backend:**
- `internal/infrastructure/worker/` — new package
- `worker.go` — `NewWorker(redisOpt asynq.RedisClientOpt) *asynq.ServeMux` registers all task handlers
- `referral_worker.go` — `TypeReferralReward = "referral:reward"`:
  - Payload: `{ referrer_id, referred_id, booking_id }`
  - Checks booking is `completed`, referral not yet `rewarded`
  - Credits wallet balance to referrer (debit ledger entry)
  - Updates referral status → `rewarded`
- `fcm_worker.go` — `TypeFCMSend = "fcm:send"` — stub in Wave 1, full implementation in Wave 2
- `main.go` additions:
  - Start `asynq.Server` on separate goroutine alongside Echo
  - Enqueue `referral:reward` task in `booking_service.go` when booking status → `completed`

---

## Wave 2

### 6. FCM Push Notifications

**Goal:** Send push notifications to users for key events using Firebase Cloud Messaging.

**Backend:**
- New migration `006_fcm_tokens.sql`:
  ```sql
  ALTER TABLE users ADD COLUMN fcm_token VARCHAR(255) NULL;
  ALTER TABLE users ADD COLUMN fcm_token_updated_at TIMESTAMPTZ NULL;
  ```
- New endpoint: `PUT /api/v1/users/me/fcm-token` — body: `{ token: string }` — upserts token on user record
- `internal/infrastructure/worker/fcm_worker.go` — full implementation:
  - Payload: `{ user_id, title, body, data: map[string]string }`
  - Looks up user's `fcm_token`; no-ops if NULL
  - Calls FCM HTTP v1 API: `POST https://fcm.googleapis.com/v1/projects/{project_id}/messages:send`
  - Auth: service account JWT (parsed from `FIREBASE_SERVICE_ACCOUNT_JSON` env var)
  - Retries: Asynq `MaxRetry(3)` with `Timeout(10s)`
- `fcm:send` tasks enqueued from:

  | Trigger | Handler |
  |---|---|
  | Booking confirmed | `booking_handler.go` UpdateBookingStatus |
  | Booking cancelled | `booking_handler.go` Cancel |
  | Match found | `team_service.go` FindMatch |
  | Team member joined | `team_service.go` JoinTeam |
  | Dispute resolved | `dispute_handler.go` ResolveDispute |
  | KYC approved/rejected | `dispute_handler.go` ReviewKYC |

**Flutter:**
- Add `firebase_messaging: ^14.x`, `firebase_core: ^2.x` to `pubspec.yaml`
- `google-services.json` / `GoogleService-Info.plist` added to Android/iOS native dirs
- `lib/core/notifications/fcm_service.dart`:
  - `init()` — called in `main.dart` after login; requests permission; gets token; PUTs to backend; sets up `onTokenRefresh` listener
  - Foreground: `FirebaseMessaging.onMessage` → show `SnackBar` with action
  - Background tap: `FirebaseMessaging.onMessageOpenedApp` → parse `data.screen` → `context.go(route)`
  - Background/terminated: `getInitialMessage()` on startup handles cold-start taps

---

### 7. WebSocket Real-time

**Goal:** Live team chat + real-time status updates (matchmaking, booking) via WebSocket with Redis pub/sub fan-out.

**Backend:**
- New endpoint: `GET /ws?token=<jwt>` — Echo WebSocket upgrade; authenticates via query-param JWT
- `internal/interfaces/http/handler/ws_handler.go`:
  - On connect: subscribe to `user:{id}` Redis channel
  - On join_channel message from client: subscribe to `team:{id}` or `match:{id}`
  - On chat_message from client: publish to `team:{id}` Redis channel (all subscribers receive it, persisted to `chat_messages` table)
  - On disconnect: unsubscribe all, remove from connection registry
- `internal/infrastructure/realtime/hub.go` — connection registry (`sync.Map` of userID → `*websocket.Conn`) + Redis pub/sub listener that writes to registered connections
- New migration `007_chat_messages.sql`:
  ```sql
  CREATE TABLE chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id),
    content TEXT NOT NULL,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );
  CREATE INDEX ON chat_messages(team_id, sent_at DESC);
  ```
- New endpoint: `GET /api/v1/teams/:id/messages?before=<cursor>&limit=50` — paginated chat history (cursor-based for real-time UX)

**Message envelope:**
```json
{
  "type": "chat_message | status_update | notification",
  "channel": "team:abc123 | match:xyz | user:me",
  "payload": {},
  "sent_at": "2026-04-10T12:00:00Z"
}
```

**Flutter:**
- Add `web_socket_channel: ^2.x` to `pubspec.yaml`
- `lib/core/realtime/realtime_service.dart` — singleton Riverpod provider:
  - Connects to `ws://<host>/ws?token=<jwt>` after login
  - Reconnects with exponential backoff (1s → 2s → 4s → ... max 30s)
  - Exposes `Stream<WsMessage>` that providers can listen to
  - `joinChannel(channel)` / `leaveChannel(channel)` for team/match subscriptions
- `lib/presentation/providers/chat_provider.dart`:
  - `chatMessagesProvider(teamId)` — loads history via REST, then appends live WS messages
  - `sendMessageProvider` — sends via WS
- `TeamManagementScreen` — add chat tab:
  - Message bubble list (own messages right-aligned, others left-aligned)
  - Text input + send button at bottom
  - "Online members" indicator
- `FindMatchScreen` — replace polling with WS `match:{id}` channel subscription; status card animates transitions

---

## Summary Table

| Feature | New migrations | New Go files | New Flutter files |
|---|---|---|---|
| MinIO uploads | none | `storage/minio.go`, `handler/upload_handler.go` | `upload_remote_source.dart`, `upload_provider.dart` |
| Google OAuth | `005_google_oauth.sql` | `auth_service.go` (extended) | `auth_remote_source.dart` (extended), `auth_provider.dart` (extended) |
| Analytics | none | `handler/events_handler.go` (wire existing) | `analytics_client.dart`, `analytics_remote_source.dart` |
| Reviews & ratings | none | `pitch_repository.go` (extended), `pitch_service.go` (extended), `handler/review_handler.go` | `review_model.dart`, `review_provider.dart` |
| Asynq workers | none | `worker/worker.go`, `worker/referral_worker.go`, `worker/fcm_worker.go` (stub) | none |
| FCM notifications | `006_fcm_tokens.sql` | `worker/fcm_worker.go` (full) | `fcm_service.dart` |
| WebSocket real-time | `007_chat_messages.sql` | `handler/ws_handler.go`, `realtime/hub.go` | `realtime_service.dart`, `chat_provider.dart` |
