# Wave 1: Foundation Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add MinIO image uploads, Google OAuth, analytics event tracking, pitch reviews & ratings, and Asynq background workers to the Turfinn Go backend and Flutter app.

**Architecture:** Five independent chains (A–E). All chains start simultaneously. Within each chain tasks are sequential. Wave 2 (FCM + WebSocket) must wait for Chain E to complete before starting.

**Tech Stack:** Go 1.25 + Echo v4 + GORM + Redis + `github.com/minio/minio-go/v7` + `github.com/hibiken/asynq`; Flutter 3.x + Riverpod + `image_picker ^1.x` + `google_sign_in ^6.x`

---

## Parallel Execution Map

| Chain | Tasks | Start |
|---|---|---|
| A — MinIO uploads | A1 → A2 → A3 | Immediately |
| B — Google OAuth | B1 → B2 | Immediately |
| C — Analytics | C1 → C2 | Immediately |
| D — Reviews & Ratings | D1 → D2 | Immediately |
| E — Asynq Workers | E1 | Immediately |

---

## File Map

**Backend — new files:**
- `backend/internal/infrastructure/storage/minio.go`
- `backend/internal/infrastructure/storage/minio_test.go`
- `backend/internal/interfaces/dto/upload_dto.go`
- `backend/internal/interfaces/http/handler/upload_handler.go`
- `backend/migrations/005_google_oauth.sql`
- `backend/internal/interfaces/dto/events_dto.go`
- `backend/internal/interfaces/http/handler/events_handler.go`
- `backend/internal/interfaces/http/handler/review_handler.go`
- `backend/internal/application/service/auth_service_test.go`
- `backend/internal/infrastructure/worker/worker.go`
- `backend/internal/infrastructure/worker/referral_worker.go`
- `backend/internal/infrastructure/worker/fcm_worker.go`

**Backend — modified files:**
- `backend/docker-compose.yml` — add MinIO service + volume
- `backend/go.mod` / `go.sum` — add minio-go/v7, asynq
- `backend/internal/domain/entity/user.go` — add GoogleID, Email fields
- `backend/internal/domain/repository/user_repository.go` — add FindByEmail, FindByGoogleID
- `backend/internal/infrastructure/repository/user_repository.go` — implement FindByEmail, FindByGoogleID
- `backend/internal/domain/repository/pitch_repository.go` — add review methods
- `backend/internal/infrastructure/repository/pitch_repository.go` — implement review methods
- `backend/internal/application/service/auth_service.go` — add GoogleSignIn
- `backend/internal/application/service/pitch_service.go` — add SubmitReview, GetReviews
- `backend/internal/interfaces/dto/auth_dto.go` — add GoogleSignInRequest
- `backend/internal/interfaces/http/handler/auth_handler.go` — add GoogleSignIn handler
- `backend/internal/interfaces/http/router.go` — wire all new routes
- `backend/cmd/api/main.go` — wire MinIO, events handler, review handler, asynq worker

**Flutter — new files:**
- `lib/data/sources/remote/upload_remote_source.dart`
- `lib/presentation/providers/upload_provider.dart`
- `lib/data/sources/remote/analytics_remote_source.dart`
- `lib/core/analytics/analytics_client.dart`
- `lib/data/models/review_model.dart`
- `lib/presentation/providers/review_provider.dart`

**Flutter — modified files:**
- `pubspec.yaml` — add image_picker, google_sign_in
- `lib/data/sources/remote/auth_remote_source.dart` — add googleSignIn
- `lib/presentation/providers/auth_provider.dart` — add signInWithGoogle
- `lib/data/sources/remote/pitch_remote_source.dart` — add submitReview, getReviews
- `lib/presentation/screens/welcome/welcome_screen.dart` — Google button
- `lib/main.dart` — init analytics

---

## Chain A: MinIO Image Uploads

### Task A1: MinIO Docker + Storage Package

**Files:**
- Modify: `backend/docker-compose.yml`
- Create: `backend/internal/infrastructure/storage/minio.go`
- Create: `backend/internal/infrastructure/storage/minio_test.go`

- [ ] **Step 1: Add MinIO to go.mod**

```bash
cd backend && go get github.com/minio/minio-go/v7@latest
```

Expected: `go.mod` updated with `github.com/minio/minio-go/v7`

- [ ] **Step 2: Add MinIO service to docker-compose.yml**

Replace the full `backend/docker-compose.yml` content with:

```yaml
services:
  app:
    build: .
    ports: ["8080:8080"]
    env_file: .env
    depends_on: [postgres, redis, minio]
    restart: unless-stopped

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: ${DB_NAME}
    ports: ["5432:5432"]
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./migrations:/docker-entrypoint-initdb.d
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]
    restart: unless-stopped

  minio:
    image: minio/minio:latest
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ACCESS_KEY}
      MINIO_ROOT_PASSWORD: ${MINIO_SECRET_KEY}
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - minio_data:/data
    restart: unless-stopped

volumes:
  postgres_data:
  minio_data:
```

- [ ] **Step 3: Write the storage package test**

Create `backend/internal/infrastructure/storage/minio_test.go`:

```go
package storage_test

import (
	"strings"
	"testing"

	"github.com/turfinn/backend/internal/infrastructure/storage"
)

func TestPublicURL(t *testing.T) {
	tests := []struct {
		endpoint string
		bucket   string
		key      string
		useSSL   bool
		want     string
	}{
		{
			endpoint: "localhost:9000",
			bucket:   "avatars",
			key:      "user-123.jpg",
			useSSL:   false,
			want:     "http://localhost:9000/avatars/user-123.jpg",
		},
		{
			endpoint: "minio.example.com",
			bucket:   "pitch-images",
			key:      "abc/photo.png",
			useSSL:   true,
			want:     "https://minio.example.com/pitch-images/abc/photo.png",
		},
	}
	for _, tt := range tests {
		got := storage.PublicURL(tt.endpoint, tt.bucket, tt.key, tt.useSSL)
		if got != tt.want {
			t.Errorf("PublicURL(%q, %q, %q, %v) = %q, want %q",
				tt.endpoint, tt.bucket, tt.key, tt.useSSL, got, tt.want)
		}
	}
}

func TestAllowedBuckets(t *testing.T) {
	allowed := []string{"avatars", "pitch-images", "kyc-documents"}
	notAllowed := []string{"../etc", "admin", ""}
	for _, b := range allowed {
		if !storage.IsAllowedBucket(b) {
			t.Errorf("expected %q to be allowed", b)
		}
	}
	for _, b := range notAllowed {
		if storage.IsAllowedBucket(b) {
			t.Errorf("expected %q to be denied", b)
		}
	}
	_ = strings.Contains // suppress unused import warning
}
```

- [ ] **Step 4: Run test — expect FAIL (package not created yet)**

```bash
cd backend && go test ./internal/infrastructure/storage/... -v
```

Expected: `no Go files in .../storage`

- [ ] **Step 5: Create the storage package**

Create `backend/internal/infrastructure/storage/minio.go`:

```go
package storage

import (
	"context"
	"fmt"
	"net/url"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"github.com/spf13/viper"
)

var allowedBuckets = map[string]bool{
	"avatars":       true,
	"pitch-images":  true,
	"kyc-documents": true,
}

// IsAllowedBucket returns true if the bucket name is on the allow-list.
func IsAllowedBucket(bucket string) bool {
	return allowedBuckets[bucket]
}

// PublicURL builds the public-read URL for a stored object.
func PublicURL(endpoint, bucket, key string, useSSL bool) string {
	scheme := "http"
	if useSSL {
		scheme = "https"
	}
	return fmt.Sprintf("%s://%s/%s/%s", scheme, endpoint, bucket, key)
}

// Client wraps the MinIO SDK client with bucket auto-creation.
type Client struct {
	mc       *minio.Client
	endpoint string
	useSSL   bool
}

// NewClient creates a MinIO client and ensures all required buckets exist.
func NewClient(ctx context.Context) (*Client, error) {
	endpoint := viper.GetString("MINIO_ENDPOINT")
	accessKey := viper.GetString("MINIO_ACCESS_KEY")
	secretKey := viper.GetString("MINIO_SECRET_KEY")
	useSSL := viper.GetBool("MINIO_USE_SSL")

	mc, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKey, secretKey, ""),
		Secure: useSSL,
	})
	if err != nil {
		return nil, fmt.Errorf("minio client: %w", err)
	}

	c := &Client{mc: mc, endpoint: endpoint, useSSL: useSSL}
	if err := c.ensureBuckets(ctx); err != nil {
		return nil, err
	}
	return c, nil
}

func (c *Client) ensureBuckets(ctx context.Context) error {
	for bucket := range allowedBuckets {
		exists, err := c.mc.BucketExists(ctx, bucket)
		if err != nil {
			return fmt.Errorf("check bucket %q: %w", bucket, err)
		}
		if !exists {
			if err := c.mc.MakeBucket(ctx, bucket, minio.MakeBucketOptions{}); err != nil {
				return fmt.Errorf("create bucket %q: %w", bucket, err)
			}
		}
	}
	return nil
}

// PresignPutURL returns a presigned PUT URL valid for ttl duration.
func (c *Client) PresignPutURL(ctx context.Context, bucket, key string, ttl time.Duration) (string, error) {
	u, err := c.mc.PresignedPutObject(ctx, bucket, key, ttl)
	if err != nil {
		return "", fmt.Errorf("presign: %w", err)
	}
	return u.String(), nil
}

// ObjectURL returns the public URL for a stored object.
func (c *Client) ObjectURL(bucket, key string) string {
	return PublicURL(c.endpoint, bucket, key, c.useSSL)
}

// GenerateKey builds a unique storage key from a user ID prefix and filename.
func GenerateKey(prefix, filename string) string {
	// Use url.PathEscape to keep the filename clean.
	return fmt.Sprintf("%s/%d-%s", prefix, time.Now().UnixNano(), url.PathEscape(filename))
}
```

- [ ] **Step 6: Run tests — expect PASS**

```bash
cd backend && go test ./internal/infrastructure/storage/... -v
```

Expected:
```
--- PASS: TestPublicURL (0.00s)
--- PASS: TestAllowedBuckets (0.00s)
PASS
```

- [ ] **Step 7: Commit**

```bash
cd backend && git add docker-compose.yml go.mod go.sum internal/infrastructure/storage/
git commit -m "feat(storage): add MinIO client + docker-compose service"
```

---

### Task A2: Upload Presign Endpoint

**Files:**
- Create: `backend/internal/interfaces/dto/upload_dto.go`
- Create: `backend/internal/interfaces/http/handler/upload_handler.go`
- Modify: `backend/internal/interfaces/http/router.go`
- Modify: `backend/cmd/api/main.go`

- [ ] **Step 1: Create upload DTO**

Create `backend/internal/interfaces/dto/upload_dto.go`:

```go
package dto

// PresignRequest is sent to POST /api/v1/upload/presign
type PresignRequest struct {
	Bucket   string `json:"bucket"   validate:"required"`
	Filename string `json:"filename" validate:"required,min=1,max=255"`
}

// PresignResponse is returned with the presigned PUT URL.
type PresignResponse struct {
	URL       string `json:"url"`
	Key       string `json:"key"`
	ExpiresIn int    `json:"expires_in"` // seconds
}
```

- [ ] **Step 2: Create upload handler**

Create `backend/internal/interfaces/http/handler/upload_handler.go`:

```go
package handler

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/infrastructure/storage"
	"github.com/turfinn/backend/internal/interfaces/dto"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

const presignTTL = 15 * time.Minute

type UploadHandler struct {
	store *storage.Client
}

func NewUploadHandler(store *storage.Client) *UploadHandler {
	return &UploadHandler{store: store}
}

// POST /api/v1/upload/presign
func (h *UploadHandler) Presign(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)

	var req dto.PresignRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	if !storage.IsAllowedBucket(req.Bucket) {
		return response.BadRequest(c, fmt.Sprintf("bucket %q not allowed", req.Bucket))
	}

	key := storage.GenerateKey(userID.String(), req.Filename)
	presignedURL, err := h.store.PresignPutURL(context.Background(), req.Bucket, key, presignTTL)
	if err != nil {
		return response.InternalError(c)
	}

	return response.OK(c, dto.PresignResponse{
		URL:       presignedURL,
		Key:       key,
		ExpiresIn: int(presignTTL.Seconds()),
	})
}
```

- [ ] **Step 3: Add storage client to main.go and wire UploadHandler**

In `backend/cmd/api/main.go`, add after the Redis init block:

```go
import (
    // existing imports ...
    "github.com/turfinn/backend/internal/infrastructure/storage"
)

// after redisClient init:
storageClient, err := storage.NewClient(context.Background())
if err != nil {
    log.Fatal().Err(err).Msg("minio connection failed")
}

// in Handlers section:
uploadH := handler.NewUploadHandler(storageClient)
```

Pass `uploadH` to `NewRouter`.

- [ ] **Step 4: Add route + update router signature**

In `backend/internal/interfaces/http/router.go`:

Add `uploadH *handler.UploadHandler` as the last parameter to `NewRouter`. Add the route inside the function before `return e`:

```go
// Image upload (auth required)
upload := v1.Group("/upload", authmw.Auth())
upload.POST("/presign", uploadH.Presign)
```

Update the `NewRouter` call in `main.go` to include `uploadH` as the last argument.

- [ ] **Step 5: Build to verify no compile errors**

```bash
cd backend && go build ./...
```

Expected: no output (clean build)

- [ ] **Step 6: Commit**

```bash
cd backend && git add internal/interfaces/dto/upload_dto.go \
  internal/interfaces/http/handler/upload_handler.go \
  internal/interfaces/http/router.go \
  cmd/api/main.go
git commit -m "feat(upload): presigned PUT URL endpoint for MinIO"
```

---

### Task A3: Flutter Image Upload

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/data/sources/remote/upload_remote_source.dart`
- Create: `lib/presentation/providers/upload_provider.dart`

- [ ] **Step 1: Add image_picker to pubspec.yaml**

In `pubspec.yaml` under `dependencies:`, add after `share_plus`:

```yaml
  image_picker: ^1.1.2
```

Run:

```bash
flutter pub get
```

Expected: `image_picker 1.x.x` resolved in pubspec.lock.

- [ ] **Step 2: Create upload remote source**

Create `lib/data/sources/remote/upload_remote_source.dart`:

```dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dio_client.dart';

part 'upload_remote_source.g.dart';

class PresignResponse {
  final String url;
  final String key;
  final int expiresIn;

  const PresignResponse({
    required this.url,
    required this.key,
    required this.expiresIn,
  });

  factory PresignResponse.fromJson(Map<String, dynamic> json) {
    return PresignResponse(
      url: json['url'] as String,
      key: json['key'] as String,
      expiresIn: json['expires_in'] as int,
    );
  }
}

@riverpod
UploadRemoteSource uploadRemoteSource(Ref ref) {
  return UploadRemoteSource(ref.watch(dioProvider));
}

class UploadRemoteSource {
  final Dio _dio;
  const UploadRemoteSource(this._dio);

  Future<PresignResponse> getPresignedUrl({
    required String bucket,
    required String filename,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/upload/presign',
      data: {'bucket': bucket, 'filename': filename},
    );
    return PresignResponse.fromJson(res.data!['data'] as Map<String, dynamic>);
  }

  Future<void> uploadFile(String presignedUrl, File file) async {
    final bytes = await file.readAsBytes();
    // Use a plain Dio without auth interceptor for presigned PUT
    final plain = Dio();
    await plain.put<void>(
      presignedUrl,
      data: Stream.fromIterable(bytes.map((b) => [b])),
      options: Options(
        headers: {
          'Content-Length': bytes.length,
          'Content-Type': _contentType(file.path),
        },
        followRedirects: false,
        validateStatus: (s) => s != null && s < 400,
      ),
    );
  }

  String _contentType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }
}
```

- [ ] **Step 3: Run build_runner to generate .g.dart**

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: `upload_remote_source.g.dart` generated.

- [ ] **Step 4: Create upload provider**

Create `lib/presentation/providers/upload_provider.dart`:

```dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/sources/remote/upload_remote_source.dart';

part 'upload_provider.g.dart';

@riverpod
class UploadNotifier extends _$UploadNotifier {
  @override
  AsyncValue<String?> build() => const AsyncData(null);

  /// Uploads [file] to [bucket] and returns the stored object key.
  Future<String?> uploadImage({
    required String bucket,
    required File file,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final source = ref.read(uploadRemoteSourceProvider);
      final filename = file.path.split('/').last;
      final presign = await source.getPresignedUrl(
        bucket: bucket,
        filename: filename,
      );
      await source.uploadFile(presign.url, file);
      return presign.key;
    });
    return state.valueOrNull;
  }
}
```

- [ ] **Step 5: Run build_runner again**

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: `upload_provider.g.dart` generated.

- [ ] **Step 6: Wire into ProfileSetupScreen avatar field**

In `lib/presentation/screens/profile/profile_setup_screen.dart` (or equivalent), find the avatar tap handler. Import and call:

```dart
import 'package:image_picker/image_picker.dart';
import '../../providers/upload_provider.dart';

// Inside the avatar tap handler (onTap of avatar widget):
final picker = ImagePicker();
final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
if (picked == null) return;
final file = File(picked.path);
final key = await ref.read(uploadNotifierProvider.notifier).uploadImage(
  bucket: 'avatars',
  file: file,
);
if (key != null) {
  // Update profile with the key — handled by profileNotifier.updateMe(avatarUrl: key)
  await ref.read(profileNotifierProvider.notifier).updateMe(avatarURL: key);
}
```

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock \
  lib/data/sources/remote/upload_remote_source.dart \
  lib/data/sources/remote/upload_remote_source.g.dart \
  lib/presentation/providers/upload_provider.dart \
  lib/presentation/providers/upload_provider.g.dart \
  lib/presentation/screens/profile/profile_setup_screen.dart
git commit -m "feat(upload): Flutter image picker + presigned PUT upload"
```

---

## Chain B: Google OAuth

### Task B1: Google OAuth — Backend

**Files:**
- Create: `backend/migrations/005_google_oauth.sql`
- Modify: `backend/internal/domain/entity/user.go`
- Modify: `backend/internal/domain/repository/user_repository.go`
- Modify: `backend/internal/infrastructure/repository/user_repository.go`
- Modify: `backend/internal/application/service/auth_service.go`
- Create: `backend/internal/application/service/auth_service_test.go`
- Modify: `backend/internal/interfaces/dto/auth_dto.go`
- Modify: `backend/internal/interfaces/http/handler/auth_handler.go`
- Modify: `backend/internal/interfaces/http/router.go`
- Modify: `backend/cmd/api/main.go`

- [ ] **Step 1: Create migration**

Create `backend/migrations/005_google_oauth.sql`:

```sql
-- +migrate Up
ALTER TABLE users ADD COLUMN IF NOT EXISTS google_id VARCHAR(255) UNIQUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS email    VARCHAR(255);

CREATE INDEX IF NOT EXISTS idx_users_google_id ON users(google_id) WHERE google_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_email     ON users(email)     WHERE email IS NOT NULL;

-- +migrate Down
ALTER TABLE users DROP COLUMN IF EXISTS google_id;
ALTER TABLE users DROP COLUMN IF EXISTS email;
```

Apply manually when running locally:

```bash
docker exec -i turfinn-postgres-1 psql -U $DB_USER -d $DB_NAME < backend/migrations/005_google_oauth.sql
```

- [ ] **Step 2: Extend User entity**

In `backend/internal/domain/entity/user.go`, add two fields after `ReferralCode`:

```go
GoogleID *string    `gorm:"column:google_id;uniqueIndex"`
Email    string     `gorm:"column:email"`
```

- [ ] **Step 3: Extend UserRepository interface**

In `backend/internal/domain/repository/user_repository.go`, add two methods to the interface:

```go
FindByEmail(ctx context.Context, email string) (*entity.User, error)
FindByGoogleID(ctx context.Context, googleID string) (*entity.User, error)
```

- [ ] **Step 4: Implement new methods in infra repository**

In `backend/internal/infrastructure/repository/user_repository.go`, add after `FindByPhone`:

```go
func (r *userRepository) FindByEmail(ctx context.Context, email string) (*entity.User, error) {
	var user entity.User
	if err := r.db.WithContext(ctx).Where("email = ?", email).First(&user).Error; err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *userRepository) FindByGoogleID(ctx context.Context, googleID string) (*entity.User, error) {
	var user entity.User
	if err := r.db.WithContext(ctx).Where("google_id = ?", googleID).First(&user).Error; err != nil {
		return nil, err
	}
	return &user, nil
}
```

- [ ] **Step 5: Write auth service tests (run before implementing GoogleSignIn)**

Create `backend/internal/application/service/auth_service_test.go`:

```go
package service_test

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
)

// mockUserRepo is a minimal in-memory mock satisfying domain.UserRepository.
type mockUserRepo struct {
	byGoogleID map[string]*entity.User
	byEmail    map[string]*entity.User
	created    []*entity.User
}

func newMockUserRepo() *mockUserRepo {
	return &mockUserRepo{
		byGoogleID: map[string]*entity.User{},
		byEmail:    map[string]*entity.User{},
	}
}

func (m *mockUserRepo) Create(ctx context.Context, u *entity.User) error {
	m.created = append(m.created, u)
	return nil
}
func (m *mockUserRepo) FindByID(ctx context.Context, id uuid.UUID) (*entity.User, error) {
	return nil, errors.New("not found")
}
func (m *mockUserRepo) FindByPhone(ctx context.Context, phone string) (*entity.User, error) {
	return nil, errors.New("not found")
}
func (m *mockUserRepo) FindByEmail(ctx context.Context, email string) (*entity.User, error) {
	u, ok := m.byEmail[email]
	if !ok {
		return nil, errors.New("not found")
	}
	return u, nil
}
func (m *mockUserRepo) FindByGoogleID(ctx context.Context, gid string) (*entity.User, error) {
	u, ok := m.byGoogleID[gid]
	if !ok {
		return nil, errors.New("not found")
	}
	return u, nil
}
func (m *mockUserRepo) Update(_ context.Context, _ *entity.User) error  { return nil }
func (m *mockUserRepo) Delete(_ context.Context, _ uuid.UUID) error     { return nil }
func (m *mockUserRepo) List(_ context.Context, _ domain.UserFilter) ([]*entity.User, int64, error) {
	return nil, 0, nil
}
func (m *mockUserRepo) Count(_ context.Context) (int64, error) { return 0, nil }

// fakeVerifier replaces the real Google token verifier in tests.
type fakeVerifier struct {
	googleID string
	email    string
	name     string
	err      error
}

func (f *fakeVerifier) Verify(_ context.Context, _ string) (service.GoogleClaims, error) {
	if f.err != nil {
		return service.GoogleClaims{}, f.err
	}
	return service.GoogleClaims{Sub: f.googleID, Email: f.email, Name: f.name}, nil
}

func TestGoogleSignIn_NewUser(t *testing.T) {
	repo := newMockUserRepo()
	svc := service.NewAuthServiceWithVerifier(repo, nil, &fakeVerifier{
		googleID: "google-abc",
		email:    "new@example.com",
		name:     "New User",
	})

	token, user, err := svc.GoogleSignIn(context.Background(), "fake-id-token")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if token == "" {
		t.Fatal("expected JWT token, got empty string")
	}
	if user.Email != "new@example.com" {
		t.Errorf("expected email new@example.com, got %q", user.Email)
	}
	if len(repo.created) != 1 {
		t.Errorf("expected 1 user created, got %d", len(repo.created))
	}
}

func TestGoogleSignIn_ExistingByGoogleID(t *testing.T) {
	existing := &entity.User{ID: uuid.New(), Email: "old@example.com", Role: entity.RolePlayer}
	repo := newMockUserRepo()
	repo.byGoogleID["google-xyz"] = existing

	svc := service.NewAuthServiceWithVerifier(repo, nil, &fakeVerifier{
		googleID: "google-xyz",
		email:    "old@example.com",
	})

	_, user, err := svc.GoogleSignIn(context.Background(), "fake-id-token")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if user.ID != existing.ID {
		t.Errorf("expected same user ID, got different")
	}
	if len(repo.created) != 0 {
		t.Errorf("expected no new user created, got %d", len(repo.created))
	}
}

func TestGoogleSignIn_ExistingByEmail(t *testing.T) {
	existing := &entity.User{ID: uuid.New(), Email: "match@example.com", Role: entity.RolePlayer}
	repo := newMockUserRepo()
	repo.byEmail["match@example.com"] = existing

	svc := service.NewAuthServiceWithVerifier(repo, nil, &fakeVerifier{
		googleID: "new-google-id",
		email:    "match@example.com",
	})

	_, user, err := svc.GoogleSignIn(context.Background(), "fake-id-token")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if user.ID != existing.ID {
		t.Errorf("expected same user from email match")
	}
}

func TestGoogleSignIn_InvalidToken(t *testing.T) {
	repo := newMockUserRepo()
	svc := service.NewAuthServiceWithVerifier(repo, nil, &fakeVerifier{
		err: errors.New("invalid token"),
	})
	_, _, err := svc.GoogleSignIn(context.Background(), "bad-token")
	if err == nil {
		t.Fatal("expected error for invalid token")
	}
}
```

- [ ] **Step 6: Run tests — expect FAIL (GoogleSignIn not implemented)**

```bash
cd backend && go test ./internal/application/service/... -run TestGoogleSignIn -v
```

Expected: compile error — `service.GoogleClaims`, `NewAuthServiceWithVerifier` undefined.

- [ ] **Step 7: Implement GoogleSignIn in auth_service.go**

Add to `backend/internal/application/service/auth_service.go`:

```go
// GoogleClaims holds the verified fields from a Google ID token.
type GoogleClaims struct {
	Sub   string // Google user ID
	Email string
	Name  string
}

// GoogleVerifier is the interface for verifying Google ID tokens.
// Allows swapping in a fake during tests.
type GoogleVerifier interface {
	Verify(ctx context.Context, idToken string) (GoogleClaims, error)
}

// httpGoogleVerifier calls the Google tokeninfo endpoint.
type httpGoogleVerifier struct{}

func (httpGoogleVerifier) Verify(ctx context.Context, idToken string) (GoogleClaims, error) {
	url := "https://oauth2.googleapis.com/tokeninfo?id_token=" + idToken
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return GoogleClaims{}, fmt.Errorf("google verify request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return GoogleClaims{}, fmt.Errorf("google token invalid: status %d", resp.StatusCode)
	}
	var body struct {
		Sub   string `json:"sub"`
		Email string `json:"email"`
		Name  string `json:"name"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return GoogleClaims{}, fmt.Errorf("decode google response: %w", err)
	}
	return GoogleClaims{Sub: body.Sub, Email: body.Email, Name: body.Name}, nil
}

// NewAuthServiceWithVerifier creates an AuthService with a custom verifier (for testing).
func NewAuthServiceWithVerifier(userRepo domain.UserRepository, redis *redis.Client, verifier GoogleVerifier) *AuthService {
	return &AuthService{userRepo: userRepo, redis: redis, googleVerifier: verifier}
}
```

Add `googleVerifier GoogleVerifier` field to `AuthService` struct.

Update `NewAuthService` to set `googleVerifier: httpGoogleVerifier{}`.

Add required imports to auth_service.go:
```go
"encoding/json"
"net/http"
```

Add `GoogleSignIn` method:

```go
// GoogleSignIn verifies a Google ID token, upserts the user, and returns a JWT.
func (s *AuthService) GoogleSignIn(ctx context.Context, idToken string) (string, *entity.User, error) {
	claims, err := s.googleVerifier.Verify(ctx, idToken)
	if err != nil {
		return "", nil, fmt.Errorf("google verify: %w", err)
	}

	// 1. Try find by GoogleID
	user, err := s.userRepo.FindByGoogleID(ctx, claims.Sub)
	if err != nil {
		// 2. Try find by email
		user, err = s.userRepo.FindByEmail(ctx, claims.Email)
		if err != nil {
			// 3. Create new user
			g := claims.Sub
			user = &entity.User{
				ID:       uuid.New(),
				Name:     claims.Name,
				Email:    claims.Email,
				GoogleID: &g,
				Role:     entity.RolePlayer,
			}
			if err := s.userRepo.Create(ctx, user); err != nil {
				return "", nil, fmt.Errorf("create user: %w", err)
			}
		} else {
			// Link google_id to existing email-matched user
			g := claims.Sub
			user.GoogleID = &g
			_ = s.userRepo.Update(ctx, user)
		}
	}

	token, err := jwtpkg.Generate(user.ID, string(user.Role))
	if err != nil {
		return "", nil, fmt.Errorf("generate token: %w", err)
	}
	return token, user, nil
}
```

- [ ] **Step 8: Run tests — expect PASS**

```bash
cd backend && go test ./internal/application/service/... -run TestGoogleSignIn -v
```

Expected:
```
--- PASS: TestGoogleSignIn_NewUser (0.00s)
--- PASS: TestGoogleSignIn_ExistingByGoogleID (0.00s)
--- PASS: TestGoogleSignIn_ExistingByEmail (0.00s)
--- PASS: TestGoogleSignIn_InvalidToken (0.00s)
PASS
```

- [ ] **Step 9: Add DTO + handler + route**

In `backend/internal/interfaces/dto/auth_dto.go`, add:

```go
type GoogleSignInRequest struct {
	IDToken string `json:"id_token" validate:"required"`
}
```

In `backend/internal/interfaces/http/handler/auth_handler.go`, add:

```go
// POST /api/v1/auth/google
func (h *AuthHandler) GoogleSignIn(c echo.Context) error {
	var req dto.GoogleSignInRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	token, user, err := h.authSvc.GoogleSignIn(c.Request().Context(), req.IDToken)
	if err != nil {
		return response.BadRequest(c, "google sign-in failed")
	}
	return response.OK(c, dto.AuthResponse{
		Token: token,
		User: dto.UserResponse{
			ID:        user.ID.String(),
			Phone:     user.Phone,
			Name:      user.Name,
			AvatarURL: user.AvatarURL,
			Role:      string(user.Role),
		},
	})
}
```

In `backend/internal/interfaces/http/router.go`, add after existing auth routes:

```go
auth.POST("/google", authH.GoogleSignIn)
```

- [ ] **Step 10: Build to verify**

```bash
cd backend && go build ./...
```

Expected: clean build.

- [ ] **Step 11: Commit**

```bash
cd backend && git add migrations/005_google_oauth.sql \
  internal/domain/entity/user.go \
  internal/domain/repository/user_repository.go \
  internal/infrastructure/repository/user_repository.go \
  internal/application/service/auth_service.go \
  internal/application/service/auth_service_test.go \
  internal/interfaces/dto/auth_dto.go \
  internal/interfaces/http/handler/auth_handler.go \
  internal/interfaces/http/router.go
git commit -m "feat(auth): Google OAuth sign-in with upsert logic"
```

---

### Task B2: Google OAuth — Flutter

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/data/sources/remote/auth_remote_source.dart`
- Modify: `lib/presentation/providers/auth_provider.dart`
- Modify: `lib/presentation/screens/welcome/welcome_screen.dart`

- [ ] **Step 1: Add google_sign_in to pubspec.yaml**

In `pubspec.yaml` under `dependencies:`, add:

```yaml
  google_sign_in: ^6.2.2
```

Run:

```bash
flutter pub get
```

- [ ] **Step 2: Extend auth remote source**

In `lib/data/sources/remote/auth_remote_source.dart`, add the `googleSignIn` method to the `AuthRemoteSource` class:

```dart
Future<Map<String, dynamic>> googleSignIn(String idToken) async {
  final res = await _dio.post<Map<String, dynamic>>(
    '/auth/google',
    data: {'id_token': idToken},
  );
  return res.data!['data'] as Map<String, dynamic>;
}
```

- [ ] **Step 3: Extend auth provider**

In `lib/presentation/providers/auth_provider.dart`, add the `signInWithGoogle` method to `AuthNotifier`:

```dart
Future<void> signInWithGoogle() async {
  state = const AsyncLoading();
  state = await AsyncValue.guard(() async {
    final googleSignIn = GoogleSignIn(
      scopes: ['email', 'profile'],
    );
    final account = await googleSignIn.signIn();
    if (account == null) throw Exception('Google sign-in cancelled');
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) throw Exception('No ID token from Google');

    final source = ref.read(authRemoteSourceProvider);
    final data = await source.googleSignIn(idToken);
    final token = data['token'] as String;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    return token;
  });
}
```

Add import at top of file:

```dart
import 'package:google_sign_in/google_sign_in.dart';
```

- [ ] **Step 4: Add Google sign-in button to WelcomeScreen**

In `lib/presentation/screens/welcome/welcome_screen.dart`, add a "Continue with Google" `OutlinedButton` below the existing sign-in button:

```dart
OutlinedButton.icon(
  onPressed: () async {
    await ref.read(authNotifierProvider.notifier).signInWithGoogle();
    if (ref.read(authNotifierProvider).hasValue) {
      context.go(AppRoutes.home);
    }
  },
  icon: const Icon(Icons.g_mobiledata, size: 24),
  label: const Text('Continue with Google'),
  style: OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(52),
    side: BorderSide(color: AppColors.primary.first),
  ),
),
```

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock \
  lib/data/sources/remote/auth_remote_source.dart \
  lib/presentation/providers/auth_provider.dart \
  lib/presentation/screens/welcome/welcome_screen.dart
git commit -m "feat(auth): Google OAuth Flutter integration"
```

---

## Chain C: Analytics Instrumentation

### Task C1: Analytics — Backend

**Files:**
- Create: `backend/internal/interfaces/dto/events_dto.go`
- Create: `backend/internal/interfaces/http/handler/events_handler.go`
- Modify: `backend/internal/interfaces/http/router.go`
- Modify: `backend/cmd/api/main.go`

- [ ] **Step 1: Create events DTO**

Create `backend/internal/interfaces/dto/events_dto.go`:

```go
package dto

import "time"

// TrackEventRequest is one analytics event from the Flutter client.
type TrackEventRequest struct {
	EventType string         `json:"event_type" validate:"required,max=50"`
	SessionID string         `json:"session_id" validate:"required,max=100"`
	Metadata  map[string]any `json:"metadata"`
	OccurredAt *time.Time    `json:"occurred_at"` // optional; defaults to server time
}

// TrackEventsRequest is a batch of events (max 50 per call).
type TrackEventsRequest struct {
	Events []TrackEventRequest `json:"events" validate:"required,min=1,max=50,dive"`
}
```

- [ ] **Step 2: Create events handler**

Create `backend/internal/interfaces/http/handler/events_handler.go`:

```go
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

	// Extract optional user ID from context (middleware sets it only if token is valid)
	var userID *uuid.UUID
	if raw := c.Get(authmw.UserIDKey); raw != nil {
		if id, ok := raw.(uuid.UUID); ok && id != uuid.Nil {
			userID = &id
		}
	}

	events := make([]entity.BookingEvent, 0, len(req.Events))
	for _, e := range req.Events {
		meta, _ := json.Marshal(e.Metadata)
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
			ev.UserID = *userID
		}
		events = append(events, ev)
	}

	if err := h.db.Create(&events).Error; err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]int{"ingested": len(events)})
}
```

- [ ] **Step 3: Add route + wire handler in router and main.go**

In `backend/internal/interfaces/http/router.go`, add `eventsH *handler.EventsHandler` parameter to `NewRouter`. Add route before `return e`:

```go
// Analytics events — auth optional (user_id populated if JWT present)
v1.POST("/events", eventsH.Track, authmw.OptionalAuth())
```

In `backend/internal/interfaces/http/middleware/auth.go`, add `OptionalAuth`:

```go
// OptionalAuth populates user_id/role in context if a valid Bearer token is present,
// but does NOT reject requests without a token.
func OptionalAuth() echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			header := c.Request().Header.Get("Authorization")
			if strings.HasPrefix(header, "Bearer ") {
				token := strings.TrimPrefix(header, "Bearer ")
				if claims, err := jwtpkg.Parse(token); err == nil {
					c.Set(UserIDKey, claims.UserID)
					c.Set(UserRoleKey, claims.Role)
				}
			}
			return next(c)
		}
	}
}
```

In `backend/cmd/api/main.go`:

```go
// in Handlers section — pass db directly:
eventsH := handler.NewEventsHandler(db)
```

Pass `eventsH` to `NewRouter`.

- [ ] **Step 4: Build check**

```bash
cd backend && go build ./...
```

Expected: clean build.

- [ ] **Step 5: Commit**

```bash
cd backend && git add \
  internal/interfaces/dto/events_dto.go \
  internal/interfaces/http/handler/events_handler.go \
  internal/interfaces/http/middleware/auth.go \
  internal/interfaces/http/router.go \
  cmd/api/main.go
git commit -m "feat(analytics): batch event ingestion endpoint with optional auth"
```

---

### Task C2: Analytics — Flutter Client

**Files:**
- Create: `lib/data/sources/remote/analytics_remote_source.dart`
- Create: `lib/core/analytics/analytics_client.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Create analytics remote source**

Create `lib/data/sources/remote/analytics_remote_source.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dio_client.dart';

part 'analytics_remote_source.g.dart';

@riverpod
AnalyticsRemoteSource analyticsRemoteSource(Ref ref) {
  return AnalyticsRemoteSource(ref.watch(dioProvider));
}

class AnalyticsRemoteSource {
  final Dio _dio;
  const AnalyticsRemoteSource(this._dio);

  Future<void> trackBatch(List<Map<String, dynamic>> events) async {
    await _dio.post<void>('/events', data: {'events': events});
  }
}
```

- [ ] **Step 2: Run build_runner**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 3: Create analytics client singleton**

Create `lib/core/analytics/analytics_client.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../data/sources/remote/analytics_remote_source.dart';

part 'analytics_client.g.dart';

const _queueKey = 'analytics_queue';
const _sessionKey = 'analytics_session_id';
const _maxQueueSize = 50;
const _flushThreshold = 10;
const _flushInterval = Duration(seconds: 30);

@Riverpod(keepAlive: true)
AnalyticsClient analyticsClient(Ref ref) {
  final client = AnalyticsClient(ref);
  ref.onDispose(client.dispose);
  return client;
}

class AnalyticsClient {
  final Ref _ref;
  final List<Map<String, dynamic>> _queue = [];
  Timer? _timer;
  late String _sessionId;

  AnalyticsClient(this._ref) {
    _initSession();
    _timer = Timer.periodic(_flushInterval, (_) => flush());
  }

  Future<void> _initSession() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionId = prefs.getString(_sessionKey) ?? const Uuid().v4();
    await prefs.setString(_sessionKey, _sessionId);
    // Restore any events that survived a previous crash
    final saved = prefs.getString(_queueKey);
    if (saved != null) {
      final list = jsonDecode(saved) as List<dynamic>;
      _queue.addAll(list.cast<Map<String, dynamic>>());
    }
  }

  void track(String eventType, {Map<String, dynamic>? metadata}) {
    if (_queue.length >= _maxQueueSize) return; // drop if full
    _queue.add({
      'event_type': eventType,
      'session_id': _sessionId,
      'metadata': metadata ?? {},
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    });
    if (_queue.length >= _flushThreshold) {
      flush();
    }
  }

  Future<void> flush() async {
    if (_queue.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_queue);
    _queue.clear();
    await _persist([]); // clear persisted queue
    try {
      await _ref.read(analyticsRemoteSourceProvider).trackBatch(batch);
    } catch (_) {
      // On failure, re-queue (up to max)
      final remaining = [...batch, ..._queue].take(_maxQueueSize).toList();
      _queue
        ..clear()
        ..addAll(remaining);
      await _persist(_queue);
    }
  }

  Future<void> onPause() async => _persist(_queue);

  Future<void> _persist(List<Map<String, dynamic>> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_queueKey, jsonEncode(events));
  }

  void dispose() {
    _timer?.cancel();
    flush();
  }
}
```

Add `uuid: ^4.4.0` to `pubspec.yaml` dependencies, then run `flutter pub get`.

- [ ] **Step 4: Run build_runner**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 5: Wire into main.dart**

In `lib/main.dart`, inside `build()` of the root widget (after `ProviderScope`), add a `WidgetsBindingObserver` that calls `flush` on pause:

```dart
// In the root StatefulWidget's State, add WidgetsBindingObserver:
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  // Fire app_open event
  WidgetsBinding.instance.addPostFrameCallback((_) {
    container.read(analyticsClientProvider).track('app_open');
  });
}

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    container.read(analyticsClientProvider).onPause();
  }
}
```

Add `pitch_view` event in `TurfDetailScreen` init:

```dart
@override
void initState() {
  super.initState();
  ref.read(analyticsClientProvider).track('pitch_view', metadata: {'pitch_id': widget.pitchId});
}
```

Add `checkout_started` event in `CheckoutScreen` init similarly.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock \
  lib/data/sources/remote/analytics_remote_source.dart \
  lib/data/sources/remote/analytics_remote_source.g.dart \
  lib/core/analytics/analytics_client.dart \
  lib/core/analytics/analytics_client.g.dart \
  lib/main.dart
git commit -m "feat(analytics): client-side event queue with auto-flush"
```

---

## Chain D: Reviews & Ratings

### Task D1: Reviews — Backend

**Files:**
- Modify: `backend/internal/domain/repository/pitch_repository.go`
- Modify: `backend/internal/infrastructure/repository/pitch_repository.go`
- Modify: `backend/internal/application/service/pitch_service.go`
- Create: `backend/internal/interfaces/http/handler/review_handler.go`
- Modify: `backend/internal/interfaces/http/router.go`
- Modify: `backend/cmd/api/main.go`

- [ ] **Step 1: Extend PitchRepository interface**

In `backend/internal/domain/repository/pitch_repository.go`, add three methods:

```go
CreateReview(ctx context.Context, review *entity.Review) error
ListReviews(ctx context.Context, pitchID uuid.UUID, page, limit int) ([]*entity.Review, int64, error)
GetAverageRating(ctx context.Context, pitchID uuid.UUID) (float64, int64, error)
```

- [ ] **Step 2: Implement in infra pitch repository**

In `backend/internal/infrastructure/repository/pitch_repository.go`, add after `Count`:

```go
func (r *pitchRepository) CreateReview(ctx context.Context, review *entity.Review) error {
	if err := r.db.WithContext(ctx).Create(review).Error; err != nil {
		return err
	}
	// Invalidate cached avg rating
	r.redis.Del(ctx, fmt.Sprintf("pitch:rating:%s", review.PitchID))
	return nil
}

func (r *pitchRepository) ListReviews(ctx context.Context, pitchID uuid.UUID, page, limit int) ([]*entity.Review, int64, error) {
	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 50 {
		limit = 10
	}
	var total int64
	r.db.WithContext(ctx).Model(&entity.Review{}).Where("pitch_id = ? AND status = 'active'", pitchID).Count(&total)
	var reviews []*entity.Review
	err := r.db.WithContext(ctx).
		Where("pitch_id = ? AND status = 'active'", pitchID).
		Order("created_at DESC").
		Offset((page - 1) * limit).Limit(limit).
		Preload("User").
		Find(&reviews).Error
	return reviews, total, err
}

const ratingCacheTTL = 10 * time.Minute

func (r *pitchRepository) GetAverageRating(ctx context.Context, pitchID uuid.UUID) (float64, int64, error) {
	cacheKey := fmt.Sprintf("pitch:rating:%s", pitchID)
	type cached struct {
		Avg   float64 `json:"avg"`
		Count int64   `json:"count"`
	}

	raw, err := r.redis.Get(ctx, cacheKey).Result()
	if err == nil {
		var c cached
		if json.Unmarshal([]byte(raw), &c) == nil {
			return c.Avg, c.Count, nil
		}
	}

	type result struct {
		Avg   float64
		Count int64
	}
	var res result
	r.db.WithContext(ctx).
		Model(&entity.Review{}).
		Select("COALESCE(AVG(rating), 0) as avg, COUNT(*) as count").
		Where("pitch_id = ? AND status = 'active'", pitchID).
		Scan(&res)

	data, _ := json.Marshal(cached{Avg: res.Avg, Count: res.Count})
	r.redis.Set(ctx, cacheKey, data, ratingCacheTTL)
	return res.Avg, res.Count, nil
}
```

- [ ] **Step 3: Extend PitchService**

In `backend/internal/application/service/pitch_service.go`, add:

```go
func (s *PitchService) SubmitReview(ctx context.Context, userID, pitchID, bookingID uuid.UUID, rating int, comment string) (*entity.Review, error) {
	if rating < 1 || rating > 5 {
		return nil, fmt.Errorf("rating must be between 1 and 5")
	}
	review := &entity.Review{
		ID:        uuid.New(),
		PitchID:   pitchID,
		UserID:    userID,
		BookingID: bookingID,
		Rating:    rating,
		Comment:   comment,
		Status:    "active",
	}
	if err := s.pitchRepo.CreateReview(ctx, review); err != nil {
		if strings.Contains(err.Error(), "unique") {
			return nil, fmt.Errorf("you have already reviewed this booking")
		}
		return nil, fmt.Errorf("create review: %w", err)
	}
	return review, nil
}

func (s *PitchService) GetReviews(ctx context.Context, pitchID uuid.UUID, page, limit int) ([]*entity.Review, int64, float64, int64, error) {
	reviews, total, err := s.pitchRepo.ListReviews(ctx, pitchID, page, limit)
	if err != nil {
		return nil, 0, 0, 0, err
	}
	avg, count, err := s.pitchRepo.GetAverageRating(ctx, pitchID)
	if err != nil {
		return nil, 0, 0, 0, err
	}
	return reviews, total, avg, count, nil
}
```

Add `"strings"` to imports.

- [ ] **Step 4: Create review handler**

Create `backend/internal/interfaces/http/handler/review_handler.go`:

```go
package handler

import (
	"strconv"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/application/service"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type ReviewHandler struct {
	pitchSvc *service.PitchService
}

func NewReviewHandler(pitchSvc *service.PitchService) *ReviewHandler {
	return &ReviewHandler{pitchSvc: pitchSvc}
}

type submitReviewReq struct {
	BookingID string `json:"booking_id" validate:"required,uuid"`
	Rating    int    `json:"rating"     validate:"required,min=1,max=5"`
	Comment   string `json:"comment"    validate:"max=500"`
}

type reviewResponse struct {
	ID        string  `json:"id"`
	UserName  string  `json:"user_name"`
	Rating    int     `json:"rating"`
	Comment   string  `json:"comment"`
	CreatedAt string  `json:"created_at"`
}

// POST /api/v1/pitches/:id/reviews
func (h *ReviewHandler) Submit(c echo.Context) error {
	pitchID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid pitch id")
	}
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)

	var req submitReviewReq
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	bookingID, err := uuid.Parse(req.BookingID)
	if err != nil {
		return response.BadRequest(c, "invalid booking id")
	}

	review, err := h.pitchSvc.SubmitReview(c.Request().Context(), userID, pitchID, bookingID, req.Rating, req.Comment)
	if err != nil {
		return response.BadRequest(c, err.Error())
	}
	return response.Created(c, reviewResponse{
		ID:        review.ID.String(),
		Rating:    review.Rating,
		Comment:   review.Comment,
		CreatedAt: review.CreatedAt.Format("2006-01-02T15:04:05Z"),
	})
}

// GET /api/v1/pitches/:id/reviews
func (h *ReviewHandler) List(c echo.Context) error {
	pitchID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid pitch id")
	}
	page, _ := strconv.Atoi(c.QueryParam("page"))
	limit, _ := strconv.Atoi(c.QueryParam("limit"))
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = 10
	}

	reviews, total, avg, count, err := h.pitchSvc.GetReviews(c.Request().Context(), pitchID, page, limit)
	if err != nil {
		return response.InternalError(c)
	}

	items := make([]reviewResponse, 0, len(reviews))
	for _, r := range reviews {
		name := ""
		if r.User != nil {
			name = r.User.Name
		}
		items = append(items, reviewResponse{
			ID:        r.ID.String(),
			UserName:  name,
			Rating:    r.Rating,
			Comment:   r.Comment,
			CreatedAt: r.CreatedAt.Format("2006-01-02T15:04:05Z"),
		})
	}

	return response.OKPaginated(c, map[string]any{
		"reviews":       items,
		"average_rating": avg,
		"review_count":   count,
	}, response.Meta{Page: page, Limit: limit, Total: total})
}
```

- [ ] **Step 5: Wire routes and handler**

In `backend/internal/interfaces/http/router.go`, add `reviewH *handler.ReviewHandler` parameter. Add routes inside the pitches group:

```go
pitches.POST("/:id/reviews", reviewH.Submit, authmw.Auth())
pitches.GET("/:id/reviews", reviewH.List)
```

In `backend/cmd/api/main.go`:

```go
reviewH := handler.NewReviewHandler(pitchSvc)
```

Pass `reviewH` to `NewRouter`.

- [ ] **Step 6: Build check**

```bash
cd backend && go build ./...
```

Expected: clean build.

- [ ] **Step 7: Commit**

```bash
cd backend && git add \
  internal/domain/repository/pitch_repository.go \
  internal/infrastructure/repository/pitch_repository.go \
  internal/application/service/pitch_service.go \
  internal/interfaces/http/handler/review_handler.go \
  internal/interfaces/http/router.go \
  cmd/api/main.go
git commit -m "feat(reviews): pitch rating & review endpoints with Redis caching"
```

---

### Task D2: Reviews — Flutter

**Files:**
- Create: `lib/data/models/review_model.dart`
- Modify: `lib/data/sources/remote/pitch_remote_source.dart`
- Create: `lib/presentation/providers/review_provider.dart`

- [ ] **Step 1: Create review model**

Create `lib/data/models/review_model.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'review_model.freezed.dart';
part 'review_model.g.dart';

@freezed
class ReviewModel with _$ReviewModel {
  const factory ReviewModel({
    required String id,
    @JsonKey(name: 'user_name') required String userName,
    required int rating,
    required String comment,
    @JsonKey(name: 'created_at') required String createdAt,
  }) = _ReviewModel;

  factory ReviewModel.fromJson(Map<String, dynamic> json) =>
      _$ReviewModelFromJson(json);
}

@freezed
class ReviewsResponse with _$ReviewsResponse {
  const factory ReviewsResponse({
    required List<ReviewModel> reviews,
    @JsonKey(name: 'average_rating') required double averageRating,
    @JsonKey(name: 'review_count') required int reviewCount,
  }) = _ReviewsResponse;

  factory ReviewsResponse.fromJson(Map<String, dynamic> json) =>
      _$ReviewsResponseFromJson(json);
}
```

- [ ] **Step 2: Run build_runner**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 3: Extend pitch remote source**

In `lib/data/sources/remote/pitch_remote_source.dart`, add two methods to `PitchRemoteSource`:

```dart
Future<ReviewsResponse> getReviews(String pitchId, {int page = 1, int limit = 10}) async {
  final res = await _dio.get<Map<String, dynamic>>(
    '/pitches/$pitchId/reviews',
    queryParameters: {'page': page, 'limit': limit},
  );
  final data = res.data!['data'] as Map<String, dynamic>;
  return ReviewsResponse.fromJson(data);
}

Future<ReviewModel> submitReview({
  required String pitchId,
  required String bookingId,
  required int rating,
  required String comment,
}) async {
  final res = await _dio.post<Map<String, dynamic>>(
    '/pitches/$pitchId/reviews',
    data: {
      'booking_id': bookingId,
      'rating': rating,
      'comment': comment,
    },
  );
  return ReviewModel.fromJson(res.data!['data'] as Map<String, dynamic>);
}
```

Add import at top:

```dart
import '../models/review_model.dart';
```

- [ ] **Step 4: Create review provider**

Create `lib/presentation/providers/review_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/review_model.dart';
import '../../data/sources/remote/pitch_remote_source.dart';

part 'review_provider.g.dart';

@riverpod
Future<ReviewsResponse> pitchReviews(Ref ref, String pitchId) async {
  final source = ref.watch(pitchRemoteSourceProvider);
  return source.getReviews(pitchId);
}

@riverpod
class SubmitReviewNotifier extends _$SubmitReviewNotifier {
  @override
  AsyncValue<ReviewModel?> build() => const AsyncData(null);

  Future<void> submit({
    required String pitchId,
    required String bookingId,
    required int rating,
    required String comment,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref
        .read(pitchRemoteSourceProvider)
        .submitReview(
          pitchId: pitchId,
          bookingId: bookingId,
          rating: rating,
          comment: comment,
        ));
  }
}
```

- [ ] **Step 5: Run build_runner**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 6: Add reviews section to TurfDetailScreen**

In `lib/presentation/screens/booking/turf_detail_screen.dart`, add a reviews section below the pitch info. Use `ref.watch(pitchReviewsProvider(pitchId))` to load reviews and display:

```dart
Consumer(builder: (context, ref, _) {
  final reviewsAsync = ref.watch(pitchReviewsProvider(pitchId));
  return reviewsAsync.when(
    loading: () => const CircularProgressIndicator(),
    error: (e, _) => const SizedBox.shrink(),
    data: (data) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.star, color: Colors.amber, size: 18),
          const SizedBox(width: 4),
          Text(
            data.averageRating.toStringAsFixed(1),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(width: 4),
          Text('(${data.reviewCount} reviews)',
              style: const TextStyle(color: Colors.grey)),
        ]),
        const SizedBox(height: 8),
        ...data.reviews.take(5).map((r) => ListTile(
          leading: CircleAvatar(child: Text(r.userName.isNotEmpty ? r.userName[0] : '?')),
          title: Text(r.userName),
          subtitle: Text(r.comment),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.star, color: Colors.amber, size: 14),
            Text(r.rating.toString()),
          ]),
        )),
      ],
    ),
  );
}),
```

- [ ] **Step 7: Commit**

```bash
git add \
  lib/data/models/review_model.dart \
  lib/data/models/review_model.freezed.dart \
  lib/data/models/review_model.g.dart \
  lib/data/sources/remote/pitch_remote_source.dart \
  lib/presentation/providers/review_provider.dart \
  lib/presentation/providers/review_provider.g.dart \
  lib/presentation/screens/booking/turf_detail_screen.dart
git commit -m "feat(reviews): pitch ratings display + review submission UI"
```

---

## Chain E: Asynq Background Workers

### Task E1: Asynq Worker Package

**Files:**
- Create: `backend/internal/infrastructure/worker/worker.go`
- Create: `backend/internal/infrastructure/worker/referral_worker.go`
- Create: `backend/internal/infrastructure/worker/fcm_worker.go`
- Modify: `backend/cmd/api/main.go`

- [ ] **Step 1: Add asynq to go.mod**

```bash
cd backend && go get github.com/hibiken/asynq@latest
```

Expected: `go.mod` updated with `github.com/hibiken/asynq`.

- [ ] **Step 2: Create worker.go (ServeMux factory)**

Create `backend/internal/infrastructure/worker/worker.go`:

```go
package worker

import (
	"github.com/hibiken/asynq"
	"github.com/redis/go-redis/v9"
	"gorm.io/gorm"
)

// New creates an Asynq server and returns the ServeMux with all handlers registered.
func New(db *gorm.DB, redisClient *redis.Client) (*asynq.Server, *asynq.ServeMux) {
	redisAddr := redisClient.Options().Addr

	srv := asynq.NewServer(
		asynq.RedisClientOpt{Addr: redisAddr},
		asynq.Config{
			Concurrency: 10,
			Queues: map[string]int{
				"critical": 6,
				"default":  3,
				"low":      1,
			},
		},
	)

	mux := asynq.NewServeMux()
	mux.HandleFunc(TypeReferralReward, NewReferralWorker(db).Handle)
	mux.HandleFunc(TypeFCMSend, NewFCMWorker().Handle) // stub in Wave 1

	return srv, mux
}
```

- [ ] **Step 3: Create referral_worker.go**

Create `backend/internal/infrastructure/worker/referral_worker.go`:

```go
package worker

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/rs/zerolog/log"
	"gorm.io/gorm"
	"github.com/turfinn/backend/internal/domain/entity"
)

const TypeReferralReward = "referral:reward"

type ReferralPayload struct {
	ReferrerID uuid.UUID `json:"referrer_id"`
	ReferredID uuid.UUID `json:"referred_id"`
	BookingID  uuid.UUID `json:"booking_id"`
}

// EnqueueReferralReward creates and enqueues a referral reward task.
func EnqueueReferralReward(client *asynq.Client, p ReferralPayload) error {
	data, err := json.Marshal(p)
	if err != nil {
		return err
	}
	task := asynq.NewTask(TypeReferralReward, data,
		asynq.MaxRetry(3),
		asynq.Queue("default"),
	)
	_, err = client.Enqueue(task)
	return err
}

type ReferralWorker struct{ db *gorm.DB }

func NewReferralWorker(db *gorm.DB) *ReferralWorker {
	return &ReferralWorker{db: db}
}

func (w *ReferralWorker) Handle(ctx context.Context, t *asynq.Task) error {
	var p ReferralPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("decode payload: %w", err)
	}

	// Find the referral record
	var referral entity.Referral
	if err := w.db.WithContext(ctx).
		Where("referrer_id = ? AND referred_id = ? AND status = 'pending'", p.ReferrerID, p.ReferredID).
		First(&referral).Error; err != nil {
		log.Warn().Str("referrer", p.ReferrerID.String()).Msg("referral not found or already rewarded")
		return nil // idempotent — do not retry
	}

	// Credit referrer wallet (100 BDT = 10000 paisa as example — read from platform settings ideally)
	const rewardPaisa = 10_000
	if err := w.db.WithContext(ctx).Exec(
		"UPDATE users SET wallet_balance_paisa = wallet_balance_paisa + ? WHERE id = ?",
		rewardPaisa, p.ReferrerID,
	).Error; err != nil {
		return fmt.Errorf("credit wallet: %w", err)
	}

	// Mark referral rewarded
	if err := w.db.WithContext(ctx).Model(&referral).
		Updates(map[string]any{"status": "rewarded"}).Error; err != nil {
		return fmt.Errorf("update referral status: %w", err)
	}

	log.Info().Str("referrer", p.ReferrerID.String()).Int64("paisa", rewardPaisa).Msg("referral reward credited")
	return nil
}
```

- [ ] **Step 4: Create fcm_worker.go (stub for Wave 2)**

Create `backend/internal/infrastructure/worker/fcm_worker.go`:

```go
package worker

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/rs/zerolog/log"
)

const TypeFCMSend = "fcm:send"

type FCMPayload struct {
	UserID uuid.UUID         `json:"user_id"`
	Title  string            `json:"title"`
	Body   string            `json:"body"`
	Data   map[string]string `json:"data"`
}

// EnqueueFCM creates and enqueues an FCM notification task.
func EnqueueFCM(client *asynq.Client, p FCMPayload) error {
	data, err := json.Marshal(p)
	if err != nil {
		return err
	}
	task := asynq.NewTask(TypeFCMSend, data,
		asynq.MaxRetry(3),
		asynq.Queue("critical"),
	)
	_, err = client.Enqueue(task)
	return err
}

type FCMWorker struct{}

func NewFCMWorker() *FCMWorker { return &FCMWorker{} }

// Handle is a stub in Wave 1. Full implementation added in Wave 2.
func (w *FCMWorker) Handle(ctx context.Context, t *asynq.Task) error {
	var p FCMPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("decode payload: %w", err)
	}
	log.Info().Str("user_id", p.UserID.String()).Str("title", p.Title).
		Msg("fcm:send stub — implement in Wave 2")
	return nil
}
```

- [ ] **Step 5: Wire Asynq into main.go**

In `backend/cmd/api/main.go`, add after Redis init:

```go
import (
    // existing imports ...
    "github.com/hibiken/asynq"
    "github.com/turfinn/backend/internal/infrastructure/worker"
)

// after redisClient init:
asynqClient := asynq.NewClient(asynq.RedisClientOpt{Addr: redisClient.Options().Addr})
defer asynqClient.Close()

workerSrv, workerMux := worker.New(db, redisClient)

// Start Asynq worker on a separate goroutine alongside Echo
go func() {
    if err := workerSrv.Run(workerMux); err != nil {
        log.Fatal().Err(err).Msg("asynq worker failed")
    }
}()
```

- [ ] **Step 6: Simplify ReferralPayload — worker does its own lookup**

Update `ReferralPayload` in `referral_worker.go` to carry only what the worker needs to find the referral:

```go
type ReferralPayload struct {
	ReferredID uuid.UUID `json:"referred_id"`
	BookingID  uuid.UUID `json:"booking_id"`
}
```

Update `Handle` to look up both the referral record and the referrer from the DB:

```go
func (w *ReferralWorker) Handle(ctx context.Context, t *asynq.Task) error {
	var p ReferralPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("decode payload: %w", err)
	}

	// Find the pending referral for this user
	var referral entity.Referral
	if err := w.db.WithContext(ctx).
		Where("referred_id = ? AND status = 'pending'", p.ReferredID).
		First(&referral).Error; err != nil {
		return nil // no referral or already rewarded — idempotent
	}

	const rewardPaisa = 10_000
	if err := w.db.WithContext(ctx).Exec(
		"UPDATE users SET wallet_balance_paisa = wallet_balance_paisa + ? WHERE id = ?",
		rewardPaisa, referral.ReferrerID,
	).Error; err != nil {
		return fmt.Errorf("credit wallet: %w", err)
	}

	if err := w.db.WithContext(ctx).Model(&referral).
		Updates(map[string]any{"status": "rewarded"}).Error; err != nil {
		return fmt.Errorf("update referral: %w", err)
	}

	log.Info().Str("referrer", referral.ReferrerID.String()).Msg("referral reward credited")
	return nil
}
```

Update `EnqueueReferralReward` signature to match:

```go
func EnqueueReferralReward(client *asynq.Client, p ReferralPayload) error { ... } // same body
```

- [ ] **Step 7: Enqueue from booking handler on status → completed**

In `backend/internal/interfaces/http/handler/booking_handler.go`, add `asynqClient *asynq.Client` to `BookingHandler` struct. Update `NewBookingHandler`:

```go
type BookingHandler struct {
	bookingSvc  *service.BookingService
	asynqClient *asynq.Client
}

func NewBookingHandler(bookingSvc *service.BookingService, asynqClient *asynq.Client) *BookingHandler {
	return &BookingHandler{bookingSvc: bookingSvc, asynqClient: asynqClient}
}
```

In `UpdateBookingStatus` (or wherever status is set to completed), after successful DB update add:

```go
if newStatus == "completed" {
    _ = worker.EnqueueReferralReward(h.asynqClient, worker.ReferralPayload{
        ReferredID: booking.UserID,
        BookingID:  booking.ID,
    })
}
```

Wire in `main.go`:

```go
bookingH := handler.NewBookingHandler(bookingSvc, asynqClient)
```

- [ ] **Step 6: Build check**

```bash
cd backend && go build ./...
```

Expected: clean build.

- [ ] **Step 7: Commit**

```bash
cd backend && git add go.mod go.sum \
  internal/infrastructure/worker/ \
  cmd/api/main.go
git commit -m "feat(workers): Asynq server + referral reward worker + FCM stub"
```

---

## Final Wave 1 Verification

- [ ] **Run all Go tests**

```bash
cd backend && go test ./... -v 2>&1 | tail -20
```

Expected: all `PASS`, no `FAIL`.

- [ ] **Build the full binary**

```bash
cd backend && go build -o api ./cmd/api/
```

Expected: `api` binary produced, no errors.

- [ ] **Flutter analyze**

```bash
flutter analyze
```

Expected: no errors (warnings about generated files are OK).

- [ ] **Flutter build check**

```bash
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1
```

Expected: APK built successfully.

- [ ] **Tag Wave 1 complete**

```bash
git tag wave1-complete
```
