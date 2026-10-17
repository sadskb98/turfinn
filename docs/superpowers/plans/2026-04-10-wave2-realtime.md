# Wave 2: FCM + WebSocket Real-time Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Firebase Cloud Messaging push notifications and WebSocket real-time communication (team chat + live status updates) to Turfinn.

**Architecture:** Two independent chains (F: FCM, G: WebSocket) that can run in parallel. Both require Chain E (Asynq workers) from Wave 1 to be complete first. FCM dispatches through Asynq. WebSocket uses Redis pub/sub for fan-out.

**Prerequisites:** Wave 1 complete (git tag `wave1-complete` exists). Asynq server is running. `fcm_worker.go` stub is in place.

**Tech Stack:** Go 1.25 + Echo + Asynq + FCM HTTP v1 API; Flutter + `firebase_messaging ^14.x` + `firebase_core ^2.x` + `web_socket_channel ^2.x`

---

## Parallel Execution Map

| Chain | Tasks | Start |
|---|---|---|
| F — FCM Push Notifications | F1 → F2 | After Wave 1 |
| G — WebSocket Real-time | G1 → G2 | After Wave 1 |

---

## File Map

**Backend — new files:**
- `backend/migrations/006_fcm_tokens.sql`
- `backend/internal/infrastructure/realtime/hub.go`
- `backend/internal/interfaces/http/handler/ws_handler.go`

**Backend — modified files:**
- `backend/internal/domain/entity/user.go` — add FCMToken field
- `backend/internal/domain/repository/user_repository.go` — add UpdateFCMToken
- `backend/internal/infrastructure/repository/user_repository.go` — implement UpdateFCMToken
- `backend/internal/infrastructure/worker/fcm_worker.go` — full implementation
- `backend/internal/interfaces/http/handler/user_handler.go` — add UpdateFCMToken endpoint
- `backend/internal/interfaces/http/router.go` — add FCM token route + WS route
- `backend/cmd/api/main.go` — wire hub + WS handler

**Backend — new migration:**
- `backend/migrations/007_chat_messages.sql`

**Flutter — new files:**
- `lib/core/notifications/fcm_service.dart`
- `lib/core/realtime/realtime_service.dart`
- `lib/data/sources/remote/ws_remote_source.dart`
- `lib/presentation/providers/chat_provider.dart`

**Flutter — modified files:**
- `pubspec.yaml` — add firebase_messaging, firebase_core, web_socket_channel
- `lib/main.dart` — init FCM
- `lib/presentation/screens/teams/team_management_screen.dart` — add chat tab
- `android/app/google-services.json` — Firebase config (add manually)
- `android/app/build.gradle` — apply google-services plugin

---

## Chain F: FCM Push Notifications

### Task F1: FCM — Backend

**Files:**
- Create: `backend/migrations/006_fcm_tokens.sql`
- Modify: `backend/internal/domain/entity/user.go`
- Modify: `backend/internal/domain/repository/user_repository.go`
- Modify: `backend/internal/infrastructure/repository/user_repository.go`
- Modify: `backend/internal/interfaces/http/handler/user_handler.go`
- Modify: `backend/internal/interfaces/http/router.go`
- Modify: `backend/internal/infrastructure/worker/fcm_worker.go`

- [ ] **Step 1: Create migration**

Create `backend/migrations/006_fcm_tokens.sql`:

```sql
-- +migrate Up
ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token            VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token_updated_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_users_fcm_token ON users(fcm_token) WHERE fcm_token IS NOT NULL;

-- +migrate Down
ALTER TABLE users DROP COLUMN IF EXISTS fcm_token;
ALTER TABLE users DROP COLUMN IF EXISTS fcm_token_updated_at;
```

Apply:

```bash
docker exec -i turfinn-postgres-1 psql -U $DB_USER -d $DB_NAME < backend/migrations/006_fcm_tokens.sql
```

- [ ] **Step 2: Add FCMToken fields to User entity**

In `backend/internal/domain/entity/user.go`, add after `ReferralCode`:

```go
FCMToken           *string    `gorm:"column:fcm_token"`
FCMTokenUpdatedAt  *time.Time `gorm:"column:fcm_token_updated_at"`
```

- [ ] **Step 3: Add UpdateFCMToken to UserRepository interface**

In `backend/internal/domain/repository/user_repository.go`, add:

```go
UpdateFCMToken(ctx context.Context, userID uuid.UUID, token string) error
```

- [ ] **Step 4: Implement UpdateFCMToken in infra repo**

In `backend/internal/infrastructure/repository/user_repository.go`, add:

```go
func (r *userRepository) UpdateFCMToken(ctx context.Context, userID uuid.UUID, token string) error {
	now := time.Now()
	err := r.db.WithContext(ctx).Model(&entity.User{}).
		Where("id = ?", userID).
		Updates(map[string]any{
			"fcm_token":            token,
			"fcm_token_updated_at": now,
		}).Error
	if err != nil {
		return err
	}
	// Invalidate user cache so next FindByID returns fresh FCM token
	r.redis.Del(ctx, fmt.Sprintf("user:%s", userID))
	return nil
}
```

- [ ] **Step 5: Add PUT /users/me/fcm-token endpoint**

In `backend/internal/interfaces/http/handler/user_handler.go`, add:

```go
type updateFCMTokenReq struct {
	Token string `json:"token" validate:"required,min=10"`
}

// PUT /api/v1/users/me/fcm-token
func (h *UserHandler) UpdateFCMToken(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	var req updateFCMTokenReq
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	if err := h.userSvc.UpdateFCMToken(c.Request().Context(), userID, req.Token); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"message": "fcm token updated"})
}
```

Add `UpdateFCMToken` to `UserService`:

In `backend/internal/application/service/user_service.go`, add:

```go
func (s *UserService) UpdateFCMToken(ctx context.Context, userID uuid.UUID, token string) error {
	return s.userRepo.UpdateFCMToken(ctx, userID, token)
}
```

In `backend/internal/interfaces/http/router.go`, add inside the users group:

```go
users.PUT("/me/fcm-token", userH.UpdateFCMToken)
```

- [ ] **Step 6: Implement full FCM worker**

Replace the stub in `backend/internal/infrastructure/worker/fcm_worker.go` with:

```go
package worker

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/rs/zerolog/log"
	"github.com/spf13/viper"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"gorm.io/gorm"
	"github.com/turfinn/backend/internal/domain/entity"
)

const TypeFCMSend = "fcm:send"

type FCMPayload struct {
	UserID uuid.UUID         `json:"user_id"`
	Title  string            `json:"title"`
	Body   string            `json:"body"`
	Data   map[string]string `json:"data"`
}

func EnqueueFCM(client *asynq.Client, p FCMPayload) error {
	data, err := json.Marshal(p)
	if err != nil {
		return err
	}
	task := asynq.NewTask(TypeFCMSend, data,
		asynq.MaxRetry(3),
		asynq.Timeout(10*time.Second),
		asynq.Queue("critical"),
	)
	_, err = client.Enqueue(task)
	return err
}

type FCMWorker struct{ db *gorm.DB }

func NewFCMWorker(db *gorm.DB) *FCMWorker { return &FCMWorker{db: db} }

func (w *FCMWorker) Handle(ctx context.Context, t *asynq.Task) error {
	var p FCMPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("decode payload: %w", err)
	}

	// Fetch user's FCM token from DB
	var user entity.User
	if err := w.db.WithContext(ctx).Select("fcm_token").
		Where("id = ?", p.UserID).First(&user).Error; err != nil {
		return fmt.Errorf("find user: %w", err)
	}
	if user.FCMToken == nil || *user.FCMToken == "" {
		log.Debug().Str("user_id", p.UserID.String()).Msg("no FCM token, skipping")
		return nil
	}

	// Build FCM HTTP v1 request
	projectID, accessToken, err := w.fcmAuth(ctx)
	if err != nil {
		return fmt.Errorf("fcm auth: %w", err)
	}

	msg := map[string]any{
		"message": map[string]any{
			"token": *user.FCMToken,
			"notification": map[string]string{
				"title": p.Title,
				"body":  p.Body,
			},
			"data": p.Data,
		},
	}
	body, _ := json.Marshal(msg)

	url := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", projectID)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("fcm send: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("fcm returned status %d", resp.StatusCode)
	}

	log.Info().Str("user_id", p.UserID.String()).Str("title", p.Title).Msg("FCM notification sent")
	return nil
}

// fcmAuth returns the Firebase project ID and a short-lived OAuth2 access token.
func (w *FCMWorker) fcmAuth(ctx context.Context) (projectID, accessToken string, err error) {
	saJSON := viper.GetString("FIREBASE_SERVICE_ACCOUNT_JSON")
	if saJSON == "" {
		return "", "", fmt.Errorf("FIREBASE_SERVICE_ACCOUNT_JSON not set")
	}

	cfg, err := google.CredentialsFromJSON(ctx, []byte(saJSON),
		"https://www.googleapis.com/auth/firebase.messaging")
	if err != nil {
		return "", "", fmt.Errorf("parse service account: %w", err)
	}

	token, err := cfg.TokenSource.Token()
	if err != nil {
		return "", "", fmt.Errorf("get token: %w", err)
	}

	// Extract project_id from the service account JSON
	var sa struct {
		ProjectID string `json:"project_id"`
	}
	_ = json.NewDecoder(strings.NewReader(saJSON)).Decode(&sa)

	return sa.ProjectID, token.AccessToken, nil
}
```

Add required imports. Add `golang.org/x/oauth2` dependency:

```bash
cd backend && go get golang.org/x/oauth2@latest
```

Update `worker.go` to pass `db` to `NewFCMWorker`:

```go
// In worker.go New() function:
mux.HandleFunc(TypeFCMSend, NewFCMWorker(db).Handle)
```

- [ ] **Step 7: Build check**

```bash
cd backend && go build ./...
```

Expected: clean build.

- [ ] **Step 8: Enqueue FCM from booking handler**

`BookingHandler` already has `asynqClient *asynq.Client` added in Wave 1 (Task E1 Step 7). If not done, add it now:

```go
type BookingHandler struct {
	bookingSvc  *service.BookingService
	asynqClient *asynq.Client
}
func NewBookingHandler(svc *service.BookingService, client *asynq.Client) *BookingHandler {
	return &BookingHandler{bookingSvc: svc, asynqClient: client}
}
```

In the `UpdateBookingStatus` handler (admin route `PUT /admin/bookings/:id/status`), after the status update succeeds:

```go
if req.Status == "confirmed" {
    _ = worker.EnqueueFCM(h.asynqClient, worker.FCMPayload{
        UserID: booking.UserID,
        Title:  "Booking Confirmed",
        Body:   fmt.Sprintf("Your slot is confirmed. See you on the pitch!"),
        Data: map[string]string{
            "screen":     "/bookings/me",
            "booking_id": booking.ID.String(),
        },
    })
}
```

In `main.go`, pass `asynqClient` to `NewBookingHandler`:

```go
bookingH := handler.NewBookingHandler(bookingSvc, asynqClient)
```

- [ ] **Step 9: Commit**

```bash
cd backend && git add \
  migrations/006_fcm_tokens.sql \
  internal/domain/entity/user.go \
  internal/domain/repository/user_repository.go \
  internal/infrastructure/repository/user_repository.go \
  internal/infrastructure/worker/fcm_worker.go \
  internal/infrastructure/worker/worker.go \
  internal/application/service/user_service.go \
  internal/interfaces/http/handler/user_handler.go \
  internal/interfaces/http/handler/booking_handler.go \
  internal/interfaces/http/router.go \
  cmd/api/main.go \
  go.mod go.sum
git commit -m "feat(fcm): full FCM push notification worker + token management"
```

---

### Task F2: FCM — Flutter

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/core/notifications/fcm_service.dart`
- Modify: `lib/main.dart`
- Modify: `android/app/google-services.json` (manually add Firebase config file)
- Modify: `android/app/build.gradle`
- Modify: `android/build.gradle`

- [ ] **Step 1: Add Firebase packages to pubspec.yaml**

In `pubspec.yaml`, add under `dependencies:`:

```yaml
  firebase_core: ^3.6.0
  firebase_messaging: ^15.1.3
```

Run:

```bash
flutter pub get
```

- [ ] **Step 2: Configure Firebase for Android**

Download `google-services.json` from the Firebase console (Project Settings → Your app → Android). Place at `android/app/google-services.json`.

In `android/build.gradle`, add to `buildscript.dependencies`:

```groovy
classpath 'com.google.gms:google-services:4.4.2'
```

In `android/app/build.gradle`, add at the bottom:

```groovy
apply plugin: 'com.google.gms.google-services'
```

- [ ] **Step 3: Create FCM service**

Create `lib/core/notifications/fcm_service.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/sources/remote/dio_client.dart';

part 'fcm_service.g.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background messages are handled silently; the user tap is handled via
  // getInitialMessage / onMessageOpenedApp.
}

@Riverpod(keepAlive: true)
FcmService fcmService(Ref ref) => FcmService(ref.watch(dioProvider));

class FcmService {
  final Dio _dio;
  FcmService(this._dio);

  Future<void> init(BuildContext context) async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request permission
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    // Get token and register with backend
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _sendTokenToBackend(token);

    // Refresh token listener
    FirebaseMessaging.instance.onTokenRefresh.listen(_sendTokenToBackend);

    // Foreground messages — show a SnackBar
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${notification.title}: ${notification.body}'),
          action: message.data['screen'] != null
              ? SnackBarAction(
                  label: 'View',
                  onPressed: () => context.go(message.data['screen'] as String),
                )
              : null,
        ));
      }
    });

    // App opened from background notification tap
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _navigate(context, message.data);
    });

    // App opened from terminated state
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _navigate(context, initial.data);
    }
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      await _dio.put<void>('/users/me/fcm-token', data: {'token': token});
    } on DioException catch (_) {
      // Non-critical — will retry on next app start
    }
  }

  void _navigate(BuildContext context, Map<String, dynamic> data) {
    final screen = data['screen'] as String?;
    if (screen != null && context.mounted) {
      context.go(screen);
    }
  }
}
```

- [ ] **Step 4: Run build_runner**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 5: Initialize Firebase and FCM in main.dart**

In `lib/main.dart`, add Firebase init before `runApp`:

```dart
import 'package:firebase_core/firebase_core.dart';
// ... other imports

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const ProviderScope(child: TurfinnApp()));
}
```

In the root widget's `build` or `onReady` (after the user is logged in), call:

```dart
// Inside a ConsumerWidget where BuildContext is available post-login:
ref.read(fcmServiceProvider).init(context);
```

Best place: inside `AppShell` init or the home screen's `initState`.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock \
  lib/core/notifications/fcm_service.dart \
  lib/core/notifications/fcm_service.g.dart \
  lib/main.dart \
  android/app/build.gradle \
  android/build.gradle
# Note: google-services.json contains no secrets itself (project config only)
git add android/app/google-services.json
git commit -m "feat(fcm): Firebase push notifications Flutter integration"
```

---

## Chain G: WebSocket Real-time

### Task G1: WebSocket — Backend

**Files:**
- Create: `backend/migrations/007_chat_messages.sql`
- Create: `backend/internal/infrastructure/realtime/hub.go`
- Create: `backend/internal/interfaces/http/handler/ws_handler.go`
- Modify: `backend/internal/interfaces/http/router.go`
- Modify: `backend/cmd/api/main.go`

- [ ] **Step 1: Create chat messages migration**

Create `backend/migrations/007_chat_messages.sql`:

```sql
-- +migrate Up
CREATE TABLE IF NOT EXISTS chat_messages (
    id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id   UUID        NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    sender_id UUID        NOT NULL REFERENCES users(id),
    content   TEXT        NOT NULL,
    sent_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_team_time
    ON chat_messages(team_id, sent_at DESC);

-- +migrate Down
DROP TABLE IF EXISTS chat_messages;
```

Apply:

```bash
docker exec -i turfinn-postgres-1 psql -U $DB_USER -d $DB_NAME < backend/migrations/007_chat_messages.sql
```

- [ ] **Step 2: Add ChatMessage entity**

In `backend/internal/domain/entity/team.go`, add at the bottom:

```go
type ChatMessage struct {
	ID       uuid.UUID `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	TeamID   uuid.UUID `gorm:"column:team_id;index"`
	SenderID uuid.UUID `gorm:"column:sender_id"`
	Content  string    `gorm:"column:content"`
	SentAt   time.Time `gorm:"column:sent_at"`

	Sender *User `gorm:"foreignKey:SenderID"`
}

func (ChatMessage) TableName() string { return "chat_messages" }
```

- [ ] **Step 3: Create WebSocket hub**

Create `backend/internal/infrastructure/realtime/hub.go`:

```go
package realtime

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"
	"github.com/rs/zerolog/log"
)

// Message is the envelope sent over the WebSocket.
type Message struct {
	Type    string          `json:"type"`    // chat_message | status_update | notification
	Channel string          `json:"channel"` // team:id | match:id | user:id
	Payload json.RawMessage `json:"payload"`
	SentAt  time.Time       `json:"sent_at"`
}

// Hub manages WebSocket connections and Redis pub/sub fan-out.
type Hub struct {
	redis *redis.Client
	conns sync.Map // map[userID string]*websocket.Conn
}

func NewHub(redis *redis.Client) *Hub {
	return &Hub{redis: redis}
}

// Register adds a connection for a user and subscribes to their personal channel.
func (h *Hub) Register(userID string, conn *websocket.Conn) {
	h.conns.Store(userID, conn)
	go h.subscribe(userID, conn)
}

// Unregister removes a connection.
func (h *Hub) Unregister(userID string) {
	h.conns.Delete(userID)
}

// Publish sends a message to a Redis channel (fan-out to all subscribers).
func (h *Hub) Publish(ctx context.Context, channel string, msg Message) error {
	msg.SentAt = time.Now()
	data, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	return h.redis.Publish(ctx, channel, data).Err()
}

// SendToUser sends a message directly to a connected user (bypasses Redis).
func (h *Hub) SendToUser(userID string, msg Message) {
	if raw, ok := h.conns.Load(userID); ok {
		conn := raw.(*websocket.Conn)
		data, _ := json.Marshal(msg)
		conn.WriteMessage(websocket.TextMessage, data) //nolint:errcheck
	}
}

// subscribe listens to the Redis channel for this user and writes messages to their WS conn.
func (h *Hub) subscribe(userID string, conn *websocket.Conn) {
	ctx := context.Background()
	channel := fmt.Sprintf("user:%s", userID)
	sub := h.redis.Subscribe(ctx, channel)
	defer sub.Close()

	ch := sub.Channel()
	for msg := range ch {
		if _, ok := h.conns.Load(userID); !ok {
			return // connection gone
		}
		if err := conn.WriteMessage(websocket.TextMessage, []byte(msg.Payload)); err != nil {
			log.Debug().Str("user", userID).Err(err).Msg("ws write error")
			return
		}
	}
}

// SubscribeChannel subscribes a user's connection to an additional Redis channel (team, match).
func (h *Hub) SubscribeChannel(ctx context.Context, userID, channel string, conn *websocket.Conn) {
	sub := h.redis.Subscribe(ctx, channel)
	go func() {
		defer sub.Close()
		ch := sub.Channel()
		for msg := range ch {
			if _, ok := h.conns.Load(userID); !ok {
				return
			}
			conn.WriteMessage(websocket.TextMessage, []byte(msg.Payload)) //nolint:errcheck
		}
	}()
}
```

Add `gorilla/websocket` dependency:

```bash
cd backend && go get github.com/gorilla/websocket@latest
```

- [ ] **Step 4: Create WebSocket handler**

Create `backend/internal/interfaces/http/handler/ws_handler.go`:

```go
package handler

import (
	"encoding/json"
	"net/http"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/labstack/echo/v4"
	"github.com/rs/zerolog/log"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/infrastructure/realtime"
	jwtpkg "github.com/turfinn/backend/internal/pkg/jwt"
	"gorm.io/gorm"
)

var upgrader = websocket.Upgrader{
	CheckOrigin:     func(r *http.Request) bool { return true }, // CORS handled at echo level
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
}

type clientMessage struct {
	Type    string          `json:"type"`    // join_channel | leave_channel | chat_message
	Channel string          `json:"channel"` // team:id | match:id
	Payload json.RawMessage `json:"payload"`
}

type chatPayload struct {
	Content string `json:"content"`
}

type WSHandler struct {
	hub *realtime.Hub
	db  *gorm.DB
}

func NewWSHandler(hub *realtime.Hub, db *gorm.DB) *WSHandler {
	return &WSHandler{hub: hub, db: db}
}

// GET /ws?token=<jwt>
func (h *WSHandler) Connect(c echo.Context) error {
	// Authenticate via query param (WS handshake can't set Authorization header)
	token := c.QueryParam("token")
	claims, err := jwtpkg.Parse(token)
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
	}
	userID := claims.UserID

	conn, err := upgrader.Upgrade(c.Response(), c.Request(), nil)
	if err != nil {
		return err
	}
	defer func() {
		h.hub.Unregister(userID.String())
		conn.Close()
	}()

	h.hub.Register(userID.String(), conn)
	log.Debug().Str("user", userID.String()).Msg("ws connected")

	// Read loop — handle client → server messages
	for {
		_, raw, err := conn.ReadMessage()
		if err != nil {
			break
		}
		var msg clientMessage
		if err := json.Unmarshal(raw, &msg); err != nil {
			continue
		}

		switch msg.Type {
		case "join_channel":
			h.hub.SubscribeChannel(c.Request().Context(), userID.String(), msg.Channel, conn)

		case "chat_message":
			var p chatPayload
			if err := json.Unmarshal(msg.Payload, &p); err != nil || p.Content == "" {
				continue
			}
			if err := h.handleChat(c.Request().Context(), conn, userID, msg.Channel, p.Content); err != nil {
				log.Warn().Err(err).Msg("chat message error")
			}
		}
	}
	return nil
}

func (h *WSHandler) handleChat(ctx context.Context, _ *websocket.Conn, senderID uuid.UUID, channel, content string) error {
	// Parse team ID from channel name "team:<uuid>"
	if len(channel) < 6 || channel[:5] != "team:" {
		return nil
	}
	teamID, err := uuid.Parse(channel[5:])
	if err != nil {
		return nil
	}

	// Persist message
	msg := entity.ChatMessage{
		TeamID:   teamID,
		SenderID: senderID,
		Content:  content,
	}
	if err := h.db.Create(&msg).Error; err != nil {
		return err
	}

	// Broadcast to all team channel subscribers
	payload, _ := json.Marshal(map[string]any{
		"id":         msg.ID.String(),
		"sender_id":  senderID.String(),
		"content":    content,
		"sent_at":    msg.SentAt,
	})
	return h.hub.Publish(context.Background(), channel, realtime.Message{
		Type:    "chat_message",
		Channel: channel,
		Payload: payload,
	})
}
```

Add `"context"` to imports in ws_handler.go. Pass `c.Request().Context()` when calling `handleChat` in the read loop.

- [ ] **Step 5: Add chat history endpoint**

In `backend/internal/interfaces/http/handler/ws_handler.go`, add:

```go
// GET /api/v1/teams/:id/messages?before=<sent_at>&limit=50
func (h *WSHandler) ListMessages(c echo.Context) error {
	teamID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid team id")
	}
	limit := 50
	query := h.db.WithContext(c.Request().Context()).
		Where("team_id = ?", teamID).
		Order("sent_at DESC").
		Limit(limit)

	if before := c.QueryParam("before"); before != "" {
		query = query.Where("sent_at < ?", before)
	}

	var msgs []entity.ChatMessage
	if err := query.Preload("Sender").Find(&msgs).Error; err != nil {
		return response.InternalError(c)
	}

	type msgResponse struct {
		ID         string `json:"id"`
		SenderID   string `json:"sender_id"`
		SenderName string `json:"sender_name"`
		Content    string `json:"content"`
		SentAt     string `json:"sent_at"`
	}
	out := make([]msgResponse, 0, len(msgs))
	for _, m := range msgs {
		name := ""
		if m.Sender != nil {
			name = m.Sender.Name
		}
		out = append(out, msgResponse{
			ID:         m.ID.String(),
			SenderID:   m.SenderID.String(),
			SenderName: name,
			Content:    m.Content,
			SentAt:     m.SentAt.Format("2006-01-02T15:04:05Z"),
		})
	}
	return response.OK(c, out)
}
```

Add `response` import at top.

- [ ] **Step 6: Wire hub and WS handler in router + main.go**

In `backend/internal/interfaces/http/router.go`, add parameters `wsH *handler.WSHandler`. Add routes:

```go
// WebSocket endpoint (auth via query param)
e.GET("/ws", wsH.Connect)

// Chat history
teams.GET("/:id/messages", wsH.ListMessages)
```

In `backend/cmd/api/main.go`:

```go
import "github.com/turfinn/backend/internal/infrastructure/realtime"

// after redisClient init:
hub := realtime.NewHub(redisClient)

// in Handlers section:
wsH := handler.NewWSHandler(hub, db)
```

Pass `wsH` to `NewRouter`.

- [ ] **Step 7: Publish match status updates from TeamHandler**

When matchmaking transitions to `matched`, publish a `status_update` to the `match:{id}` Redis channel so Flutter clients subscribed via WS receive live updates.

Add `hub *realtime.Hub` to `TeamHandler` struct. Update `NewTeamHandler` to accept it:

```go
type TeamHandler struct {
	teamSvc *service.TeamService
	hub     *realtime.Hub
}

func NewTeamHandler(teamSvc *service.TeamService, hub *realtime.Hub) *TeamHandler {
	return &TeamHandler{teamSvc: teamSvc, hub: hub}
}
```

In `FindMatch` handler, after successful match creation:

```go
if match != nil && match.Status == "matched" {
	payload, _ := json.Marshal(map[string]any{
		"match_id": match.ID.String(),
		"status":   "matched",
	})
	_ = h.hub.Publish(c.Request().Context(), fmt.Sprintf("match:%s", match.ID), realtime.Message{
		Type:    "status_update",
		Channel: fmt.Sprintf("match:%s", match.ID),
		Payload: payload,
	})
}
```

Add imports: `"encoding/json"`, `"fmt"`, `"github.com/turfinn/backend/internal/infrastructure/realtime"`.

Wire in `main.go`:

```go
teamH := handler.NewTeamHandler(teamSvc, hub)
```

- [ ] **Step 8: Build check**

```bash
cd backend && go build ./...
```

Expected: clean build.

- [ ] **Step 9: Commit**

```bash
cd backend && git add \
  migrations/007_chat_messages.sql \
  internal/domain/entity/team.go \
  internal/infrastructure/realtime/hub.go \
  internal/interfaces/http/handler/ws_handler.go \
  internal/interfaces/http/router.go \
  cmd/api/main.go \
  go.mod go.sum
git commit -m "feat(realtime): WebSocket hub + team chat + Redis pub/sub + match status updates"
```

---

### Task G2: WebSocket — Flutter

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/core/realtime/realtime_service.dart`
- Create: `lib/presentation/providers/chat_provider.dart`
- Modify: `lib/presentation/screens/teams/team_management_screen.dart`

- [ ] **Step 1: Add web_socket_channel to pubspec.yaml**

In `pubspec.yaml`, add under `dependencies:`:

```yaml
  web_socket_channel: ^3.0.1
```

Run:

```bash
flutter pub get
```

- [ ] **Step 2: Create realtime service**

Create `lib/core/realtime/realtime_service.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

part 'realtime_service.g.dart';

const _wsBaseUrl = String.fromEnvironment(
  'WS_BASE_URL',
  defaultValue: 'ws://localhost:8080',
);

@Riverpod(keepAlive: true)
RealtimeService realtimeService(Ref ref) {
  final service = RealtimeService();
  ref.onDispose(service.dispose);
  return service;
}

class WsMessage {
  final String type;
  final String channel;
  final Map<String, dynamic> payload;
  final String sentAt;

  const WsMessage({
    required this.type,
    required this.channel,
    required this.payload,
    required this.sentAt,
  });

  factory WsMessage.fromJson(Map<String, dynamic> json) => WsMessage(
        type: json['type'] as String? ?? '',
        channel: json['channel'] as String? ?? '',
        payload: json['payload'] as Map<String, dynamic>? ?? {},
        sentAt: json['sent_at'] as String? ?? '',
      );
}

class RealtimeService {
  WebSocketChannel? _channel;
  final _controller = StreamController<WsMessage>.broadcast();
  bool _disposed = false;
  int _retryDelay = 1;

  Stream<WsMessage> get messages => _controller.stream;

  Future<void> connect() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) return;

    final uri = Uri.parse('$_wsBaseUrl/ws?token=$token');
    try {
      _channel = WebSocketChannel.connect(uri);
      _retryDelay = 1;
      _channel!.stream.listen(
        (data) {
          final json = jsonDecode(data as String) as Map<String, dynamic>;
          _controller.add(WsMessage.fromJson(json));
        },
        onDone: _reconnect,
        onError: (_) => _reconnect(),
      );
    } catch (_) {
      _reconnect();
    }
  }

  void joinChannel(String channel) {
    _send({'type': 'join_channel', 'channel': channel, 'payload': {}});
  }

  void sendChatMessage(String teamId, String content) {
    _send({
      'type': 'chat_message',
      'channel': 'team:$teamId',
      'payload': {'content': content},
    });
  }

  void _send(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void _reconnect() {
    if (_disposed) return;
    Future.delayed(Duration(seconds: _retryDelay), () {
      if (!_disposed) {
        _retryDelay = (_retryDelay * 2).clamp(1, 30);
        connect();
      }
    });
  }

  void dispose() {
    _disposed = true;
    _channel?.sink.close();
    _controller.close();
  }
}
```

- [ ] **Step 3: Run build_runner**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 4: Connect realtime service after login**

In `lib/presentation/providers/auth_provider.dart`, after a successful login (OTP verify or Google OAuth), add:

```dart
// After storing auth_token:
ref.read(realtimeServiceProvider).connect();
```

Add import:

```dart
import '../../core/realtime/realtime_service.dart';
```

- [ ] **Step 5: Create chat provider**

Create `lib/presentation/providers/chat_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/realtime/realtime_service.dart';
import '../../data/sources/remote/dio_client.dart';
import 'package:dio/dio.dart';

part 'chat_provider.g.dart';

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String content;
  final String sentAt;
  final bool isOwn;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.sentAt,
    required this.isOwn,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, String myId) =>
      ChatMessage(
        id: json['id'] as String,
        senderId: json['sender_id'] as String,
        senderName: json['sender_name'] as String? ?? '',
        content: json['content'] as String,
        sentAt: json['sent_at'] as String,
        isOwn: json['sender_id'] == myId,
      );
}

@riverpod
class TeamChatNotifier extends _$TeamChatNotifier {
  @override
  List<ChatMessage> build(String teamId) {
    _loadHistory();
    _listenLive();
    return [];
  }

  Future<void> _loadHistory() async {
    final dio = ref.read(dioProvider);
    try {
      final res = await dio.get<Map<String, dynamic>>(
        '/teams/$teamId/messages',
        queryParameters: {'limit': 50},
      );
      final data = (res.data!['data'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      // History comes newest-first; reverse for display
      state = data.reversed
          .map((m) => ChatMessage.fromJson(m, ''))
          .toList();
    } on DioException catch (_) {
      // Non-critical if history fails
    }
  }

  void _listenLive() {
    final service = ref.read(realtimeServiceProvider);
    service.joinChannel('team:$teamId');
    service.messages
        .where((m) => m.type == 'chat_message' && m.channel == 'team:$teamId')
        .listen((m) {
      final msg = ChatMessage(
        id: m.payload['id'] as String? ?? '',
        senderId: m.payload['sender_id'] as String? ?? '',
        senderName: '',
        content: m.payload['content'] as String? ?? '',
        sentAt: m.payload['sent_at'] as String? ?? '',
        isOwn: false,
      );
      state = [...state, msg];
    });
  }

  void send(String content) {
    ref.read(realtimeServiceProvider).sendChatMessage(teamId, content);
  }
}
```

- [ ] **Step 6: Run build_runner**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 7: Add chat tab to TeamManagementScreen**

In `lib/presentation/screens/teams/team_management_screen.dart`, wrap the existing content in a `DefaultTabController` with two tabs: "Team" (existing) and "Chat" (new).

Add the Chat tab widget:

```dart
// Chat tab body
Consumer(builder: (context, ref, _) {
  final messages = ref.watch(teamChatNotifierProvider(teamId));
  final controller = TextEditingController();
  return Column(
    children: [
      Expanded(
        child: ListView.builder(
          reverse: false,
          itemCount: messages.length,
          itemBuilder: (ctx, i) {
            final msg = messages[i];
            return Align(
              alignment: msg.isOwn
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: msg.isOwn
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: msg.isOwn
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (!msg.isOwn)
                      Text(msg.senderName,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    Text(msg.content),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                  hintText: 'Type a message...'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                ref
                    .read(teamChatNotifierProvider(teamId).notifier)
                    .send(text);
                controller.clear();
              }
            },
          ),
        ]),
      ),
    ],
  );
}),
```

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock \
  lib/core/realtime/realtime_service.dart \
  lib/core/realtime/realtime_service.g.dart \
  lib/presentation/providers/chat_provider.dart \
  lib/presentation/providers/chat_provider.g.dart \
  lib/presentation/providers/auth_provider.dart \
  lib/presentation/screens/teams/team_management_screen.dart
git commit -m "feat(realtime): WebSocket team chat + live status updates Flutter"
```

---

## Final Wave 2 Verification

- [ ] **Run all Go tests**

```bash
cd backend && go test ./... -v 2>&1 | tail -30
```

Expected: all PASS.

- [ ] **Full Go build**

```bash
cd backend && go build -o api ./cmd/api/
```

Expected: clean.

- [ ] **Flutter analyze**

```bash
flutter analyze
```

Expected: no errors.

- [ ] **Flutter debug build**

```bash
flutter build apk --debug \
  --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1 \
  --dart-define=WS_BASE_URL=ws://10.0.2.2:8080
```

Expected: APK produced.

- [ ] **Tag Wave 2 complete**

```bash
git tag wave2-complete
```
