# Manager Auth + KYC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add OTP login, KYC submission flow, and approval gate to the turf manager panel so only verified managers reach the dashboard; also replace pitch image URL fields with real file pickers.

**Architecture:** A separate Dio client reading `manager_token` from SharedPreferences powers all manage-panel API calls. Three new screens (Login, KYC form, KYC pending) guard the router. The backend gains two new endpoints under `/manage/kyc` and the `ApproveKYC` handler now grants the manager role on approval.

**Tech Stack:** Flutter 3.x, Go 1.22, GoRouter 13, Riverpod 2, MinIO presigned uploads, `file_picker ^8.1.2`, `shared_preferences ^2.2.3`

---

## File Map

| File | Change |
|---|---|
| `pubspec.yaml` | Add `file_picker: ^8.1.2` |
| `lib/data/sources/remote/manage_dio_client.dart` | New — Dio reading `manager_token` |
| `lib/data/sources/remote/manage_remote_source.dart` | Use `manageDioProvider`, add KYC + upload methods |
| `lib/presentation/screens/manage/manage_login_screen.dart` | New — OTP login |
| `lib/presentation/screens/manage/manage_kyc_screen.dart` | New — KYC form + `_ImagePickerField` |
| `lib/presentation/screens/manage/manage_kyc_pending_screen.dart` | New — pending/rejected state |
| `lib/main_manage.dart` | Add GoRouter guards |
| `lib/presentation/screens/manage/manage_panel_screen.dart` | Pitch form: banner + gallery pickers |
| `backend/internal/interfaces/dto/upload_dto.go` | Add `PublicURL` to `PresignResponse` |
| `backend/internal/interfaces/http/handler/upload_handler.go` | Populate `PublicURL` in response |
| `backend/internal/interfaces/dto/dispute_dto.go` | Add `SubmitKYCRequest` |
| `backend/internal/interfaces/http/handler/manage_handler.go` | Add `verifyRepo`, `userRepo`, `GetMyKYC`, `SubmitKYC` |
| `backend/internal/interfaces/http/router.go` | Register `/manage/kyc/me` + `/manage/kyc` |
| `backend/cmd/api/main.go` | Pass `verificationRepo`+`userRepo` to `NewManageHandler` |
| `backend/internal/interfaces/http/handler/dispute_handler.go` | `ApproveKYC` grants manager role |
| `backend/migrations/022_pitch_banner.sql` | Add `banner_url` to pitches |
| `backend/internal/domain/entity/pitch.go` | Add `BannerURL` field |
| `backend/internal/interfaces/dto/pitch_dto.go` | Expose `banner_url` in responses/requests |
| `backend/internal/interfaces/http/handler/manage_handler.go` | Handle `banner_url` in create/update pitch |

---

### Task 1: Add `file_picker` dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add `file_picker` to pubspec.yaml**

In `pubspec.yaml`, under `dependencies:` after `geolocator`, add:
```yaml
  file_picker: ^8.1.2
```

- [ ] **Step 2: Install**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn
flutter pub get
```
Expected: `Resolving dependencies... Got dependencies!`

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add file_picker dependency"
```

---

### Task 2: Backend — add `public_url` to PresignResponse

**Files:**
- Modify: `backend/internal/interfaces/dto/upload_dto.go`
- Modify: `backend/internal/interfaces/http/handler/upload_handler.go`

- [ ] **Step 1: Add `PublicURL` to `PresignResponse`**

In `backend/internal/interfaces/dto/upload_dto.go`, replace the `PresignResponse` struct:

```go
// PresignResponse is returned with the presigned PUT URL.
type PresignResponse struct {
	URL       string `json:"url"`
	Key       string `json:"key"`
	PublicURL string `json:"public_url"`
	ExpiresIn int    `json:"expires_in"` // seconds
}
```

- [ ] **Step 2: Populate `PublicURL` in the handler**

In `backend/internal/interfaces/http/handler/upload_handler.go`, replace the `return response.OK(...)` call:

```go
	return response.OK(c, dto.PresignResponse{
		URL:       presignedURL,
		Key:       key,
		PublicURL: h.store.ObjectURL(req.Bucket, key),
		ExpiresIn: int(presignTTL.Seconds()),
	})
```

- [ ] **Step 3: Verify build**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/backend
go build ./...
```
Expected: no output (success).

- [ ] **Step 4: Commit**

```bash
git add backend/internal/interfaces/dto/upload_dto.go backend/internal/interfaces/http/handler/upload_handler.go
git commit -m "feat: add public_url to presign response"
```

---

### Task 3: Backend — KYC submission endpoint

**Files:**
- Modify: `backend/internal/interfaces/dto/dispute_dto.go`
- Modify: `backend/internal/interfaces/http/handler/manage_handler.go`

- [ ] **Step 1: Add `SubmitKYCRequest` DTO**

In `backend/internal/interfaces/dto/dispute_dto.go`, add after `RejectKYCRequest`:

```go
type SubmitKYCRequest struct {
	BusinessName     string `json:"business_name"      validate:"required"`
	NIDNumber        string `json:"nid_number"         validate:"required"`
	NIDPhotoFrontURL string `json:"nid_photo_front_url" validate:"required"`
	NIDPhotoBackURL  string `json:"nid_photo_back_url"  validate:"required"`
	SelfieURL        string `json:"selfie_url"          validate:"required"`
	PayoutAccount    string `json:"payout_account"      validate:"required"`
}
```

- [ ] **Step 2: Add `verifyRepo` and `userRepo` to `ManageHandler`**

In `backend/internal/interfaces/http/handler/manage_handler.go`, replace the struct and constructor:

```go
type ManageHandler struct {
	pitchRepo   domain.PitchRepository
	bookingRepo domain.BookingRepository
	verifyRepo  domain.VerificationRepository
	userRepo    domain.UserRepository
}

func NewManageHandler(
	pr domain.PitchRepository,
	br domain.BookingRepository,
	vr domain.VerificationRepository,
	ur domain.UserRepository,
) *ManageHandler {
	return &ManageHandler{pitchRepo: pr, bookingRepo: br, verifyRepo: vr, userRepo: ur}
}
```

- [ ] **Step 3: Add `GetMyKYC` handler**

Add to `manage_handler.go` (after the existing handlers):

```go
// GetMyKYC handles GET /manage/kyc/me
func (h *ManageHandler) GetMyKYC(c echo.Context) error {
	userID, ok := c.Get(authmw.UserIDKey).(uuid.UUID)
	if !ok {
		return response.Unauthorized(c)
	}
	k, err := h.verifyRepo.GetKYCByUser(c.Request().Context(), userID)
	if err != nil {
		return response.OK(c, map[string]string{"status": "none"})
	}
	submittedAt := ""
	if k.SubmittedAt != nil {
		submittedAt = k.SubmittedAt.Format(time.RFC3339)
	}
	return response.OK(c, dto.KYCResponse{
		ID:               k.ID.String(),
		UserID:           k.UserID.String(),
		BusinessName:     k.BusinessName,
		NIDNumber:        k.NIDNumber,
		NIDPhotoFrontURL: k.NIDPhotoFrontURL,
		NIDPhotoBackURL:  k.NIDPhotoBackURL,
		SelfieURL:        k.SelfieURL,
		PayoutAccount:    k.PayoutAccount,
		Status:           k.Status,
		ReviewNote:       k.ReviewNote,
		SubmittedAt:      submittedAt,
	})
}
```

- [ ] **Step 4: Add `SubmitKYC` handler**

Add to `manage_handler.go`:

```go
// SubmitKYC handles POST /manage/kyc
func (h *ManageHandler) SubmitKYC(c echo.Context) error {
	userID, ok := c.Get(authmw.UserIDKey).(uuid.UUID)
	if !ok {
		return response.Unauthorized(c)
	}
	var req dto.SubmitKYCRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	now := time.Now()
	existing, err := h.verifyRepo.GetKYCByUser(c.Request().Context(), userID)

	if err != nil || existing == nil {
		k := &entity.ManagerKYC{
			UserID:           userID,
			BusinessName:     req.BusinessName,
			NIDNumber:        req.NIDNumber,
			NIDPhotoFrontURL: req.NIDPhotoFrontURL,
			NIDPhotoBackURL:  req.NIDPhotoBackURL,
			SelfieURL:        req.SelfieURL,
			PayoutAccount:    req.PayoutAccount,
			Status:           "submitted",
			SubmittedAt:      &now,
		}
		if err := h.verifyRepo.CreateKYC(c.Request().Context(), k); err != nil {
			return response.InternalError(c)
		}
		return response.OK(c, map[string]string{"status": "submitted"})
	}

	if existing.Status == "submitted" || existing.Status == "under_review" {
		return response.BadRequest(c, "application already under review")
	}

	existing.BusinessName = req.BusinessName
	existing.NIDNumber = req.NIDNumber
	existing.NIDPhotoFrontURL = req.NIDPhotoFrontURL
	existing.NIDPhotoBackURL = req.NIDPhotoBackURL
	existing.SelfieURL = req.SelfieURL
	existing.PayoutAccount = req.PayoutAccount
	existing.Status = "submitted"
	existing.SubmittedAt = &now
	existing.ReviewNote = ""

	if err := h.verifyRepo.UpdateKYC(c.Request().Context(), existing); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"status": "submitted"})
}
```

You will need the following imports at the top of `manage_handler.go`:
```go
import (
	"time"
	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/domain"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/interfaces/dto"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)
```

- [ ] **Step 5: Verify build**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/backend && go build ./...
```
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/interfaces/dto/dispute_dto.go backend/internal/interfaces/http/handler/manage_handler.go
git commit -m "feat: add GetMyKYC and SubmitKYC handlers"
```

---

### Task 4: Backend — wire new handler in router + main

**Files:**
- Modify: `backend/internal/interfaces/http/router.go`
- Modify: `backend/cmd/api/main.go`

- [ ] **Step 1: Register KYC routes in router**

In `backend/internal/interfaces/http/router.go`, find the `manage` group (look for `manage.GET("", manageH.ListMyPitches)` or similar). Add after the existing manage routes:

```go
	manage.GET("/kyc/me", manageH.GetMyKYC)
	manage.POST("/kyc", manageH.SubmitKYC)
```

- [ ] **Step 2: Update `NewManageHandler` call in `main.go`**

In `backend/cmd/api/main.go`, find:
```go
manageH := handler.NewManageHandler(pitchRepo, bookingRepo)
```
Replace with:
```go
manageH := handler.NewManageHandler(pitchRepo, bookingRepo, verificationRepo, userRepo)
```

(`verificationRepo` and `userRepo` are already created earlier in `main.go`.)

- [ ] **Step 3: Verify build**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/backend && go build ./...
```

- [ ] **Step 4: Commit**

```bash
git add backend/internal/interfaces/http/router.go backend/cmd/api/main.go
git commit -m "feat: register manager KYC routes"
```

---

### Task 5: Backend — ApproveKYC grants manager role

**Files:**
- Modify: `backend/internal/interfaces/http/handler/dispute_handler.go`

- [ ] **Step 1: Locate `ApproveKYC` in `dispute_handler.go`**

Find the function (around line 430). It currently sets `k.Status = "approved"` and calls `UpdateKYC`. Add the role grant after `UpdateKYC` succeeds:

```go
func (h *DisputeHandler) ApproveKYC(c echo.Context) error {
	// ... existing code to get id, get KYC record ...
	k.Status = "approved"
	reviewedAt := time.Now()
	k.ReviewedAt = &reviewedAt
	if reviewerID, ok := c.Get(authmw.UserIDKey).(uuid.UUID); ok {
		k.ReviewedBy = reviewerID
	}
	if err := h.verifyRepo.UpdateKYC(c.Request().Context(), k); err != nil {
		return response.InternalError(c)
	}
	// Grant manager role to the applicant
	if u, err := h.userRepo.FindByID(c.Request().Context(), k.UserID); err == nil {
		u.Role = "manager"
		_ = h.userRepo.Update(c.Request().Context(), u)
	}
	return response.OK(c, map[string]string{"status": "approved"})
}
```

Replace only the section after `UpdateKYC` succeeds — keep the existing guard logic for `id` parsing and `GetKYC` intact.

- [ ] **Step 2: Verify build**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/backend && go build ./...
```

- [ ] **Step 3: Commit**

```bash
git add backend/internal/interfaces/http/handler/dispute_handler.go
git commit -m "feat: grant manager role on KYC approval"
```

---

### Task 6: Backend — add `banner_url` to pitches

**Files:**
- Create: `backend/migrations/022_pitch_banner.sql`
- Modify: `backend/internal/domain/entity/pitch.go`
- Modify: `backend/internal/interfaces/dto/pitch_dto.go` (or equivalent)
- Modify: `backend/internal/interfaces/http/handler/manage_handler.go`

- [ ] **Step 1: Create migration**

Create `backend/migrations/022_pitch_banner.sql`:
```sql
ALTER TABLE pitches ADD COLUMN IF NOT EXISTS banner_url TEXT NOT NULL DEFAULT '';
```

- [ ] **Step 2: Add `BannerURL` to pitch entity**

In `backend/internal/domain/entity/pitch.go`, find the `Pitch` struct and add:
```go
BannerURL string `gorm:"column:banner_url"`
```

- [ ] **Step 3: Expose `banner_url` in DTOs**

Find the pitch create/update request and response DTOs (in `backend/internal/interfaces/dto/`). Add `BannerURL string \`json:"banner_url"\`` to each struct that represents a pitch (request + response).

- [ ] **Step 4: Handle `banner_url` in `CreatePitch` and `UpdatePitch`**

In `manage_handler.go`, the `CreatePitch` and `UpdatePitch` handlers map request fields to the entity. Add:
```go
BannerURL: req.BannerURL,
```
in both handlers where the pitch struct is built from the request.

- [ ] **Step 5: Verify build**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/backend && go build ./...
```

- [ ] **Step 6: Apply migration (fresh DB or manual)**

```bash
docker compose down -v && docker compose up -d --build
```
Or if you want to preserve data, connect to Postgres and run the migration SQL manually.

- [ ] **Step 7: Commit**

```bash
git add backend/migrations/022_pitch_banner.sql backend/internal/domain/entity/pitch.go backend/internal/interfaces/dto/ backend/internal/interfaces/http/handler/manage_handler.go
git commit -m "feat: add banner_url to pitches"
```

---

### Task 7: Flutter — separate Dio client for manage panel

**Files:**
- Create: `lib/data/sources/remote/manage_dio_client.dart`
- Modify: `lib/data/sources/remote/manage_remote_source.dart`

- [ ] **Step 1: Create `manage_dio_client.dart`**

Create `lib/data/sources/remote/manage_dio_client.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/config/app_config.dart';

part 'manage_dio_client.g.dart';

@riverpod
Dio manageDio(Ref ref) {
  final d = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'Content-Type': 'application/json'},
  ));
  d.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('manager_token');
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (error, handler) => handler.next(error),
  ));
  return d;
}
```

- [ ] **Step 2: Update `manage_remote_source.dart` to use `manageDioProvider`**

In `lib/data/sources/remote/manage_remote_source.dart`, change the import and provider:

```dart
import 'manage_dio_client.dart';

@riverpod
ManageRemoteSource manageRemoteSource(ManageRemoteSourceRef ref) =>
    ManageRemoteSource(ref.watch(manageDioProvider));
```

(Remove the import of `dio_client.dart` and replace with `manage_dio_client.dart`.)

- [ ] **Step 3: Add KYC and upload methods to `ManageRemoteSource`**

Add to `ManageRemoteSource` class:

```dart
Future<Map<String, dynamic>?> getMyKyc() async {
  try {
    final resp = await _dio.get('/manage/kyc/me');
    return resp.data['data'] as Map<String, dynamic>;
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) return null;
    rethrow;
  }
}

Future<void> submitKyc(Map<String, dynamic> data) async {
  await _dio.post('/manage/kyc', data: data);
}

/// Returns {url, key, public_url} from the presign endpoint.
Future<Map<String, dynamic>> presignUpload(String bucket, String filename) async {
  final resp = await _dio.post('/upload/presign', data: {
    'bucket': bucket,
    'filename': filename,
  });
  return resp.data['data'] as Map<String, dynamic>;
}

/// Uploads bytes directly to a MinIO presigned PUT URL.
Future<void> uploadToPresignUrl(String presignUrl, List<int> bytes, String contentType) async {
  final uploadDio = Dio();
  await uploadDio.put(
    presignUrl,
    data: bytes,
    options: Options(headers: {'Content-Type': contentType}),
  );
}
```

- [ ] **Step 4: Regenerate Riverpod code**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn
dart run build_runner build --delete-conflicting-outputs
```
Expected: generates `manage_dio_client.g.dart` and updates `manage_remote_source.g.dart`.

- [ ] **Step 5: Analyze**

```bash
flutter analyze lib/data/sources/remote/manage_dio_client.dart lib/data/sources/remote/manage_remote_source.dart
```
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/data/sources/remote/manage_dio_client.dart lib/data/sources/remote/manage_dio_client.g.dart lib/data/sources/remote/manage_remote_source.dart lib/data/sources/remote/manage_remote_source.g.dart
git commit -m "feat: separate Dio client for manage panel using manager_token"
```

---

### Task 8: Flutter — ManageLoginScreen

**Files:**
- Create: `lib/presentation/screens/manage/manage_login_screen.dart`

- [ ] **Step 1: Create the login screen**

Create `lib/presentation/screens/manage/manage_login_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/sources/remote/manage_remote_source.dart';

class ManageLoginScreen extends ConsumerStatefulWidget {
  const ManageLoginScreen({super.key});

  @override
  ConsumerState<ManageLoginScreen> createState() => _ManageLoginScreenState();
}

class _ManageLoginScreenState extends ConsumerState<ManageLoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _otpSent = false;
  bool _loading = false;
  String? _error;
  String? _devOtp;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final src = ref.read(manageRemoteSourceProvider);
      // Re-use the auth endpoint via a plain Dio call (no auth required)
      final resp = await src.sendOtp(phone);
      setState(() { _otpSent = true; _devOtp = resp; });
    } catch (e) {
      setState(() => _error = 'Failed to send OTP. Check your number.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyOtp() async {
    final phone = _phoneCtrl.text.trim();
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) return;
    setState(() { _loading = true; _error = null; });
    try {
      final src = ref.read(manageRemoteSourceProvider);
      final data = await src.verifyOtp(phone, otp);
      final token = data['token'] as String;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('manager_token', token);
      if (!mounted) return;
      context.go('/kyc-check');
    } catch (e) {
      setState(() => _error = 'Invalid OTP. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Turf Manager', style: GoogleFonts.nunito(
                  fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.primary)),
                const SizedBox(height: 8),
                Text('Sign in to your dashboard', style: GoogleFonts.dmSans(
                  fontSize: 15, color: AppColors.textSecondary)),
                const SizedBox(height: 40),
                _field('Phone number', _phoneCtrl, enabled: !_otpSent,
                    hint: '+8801XXXXXXXXX', keyboardType: TextInputType.phone),
                if (_otpSent) ...[
                  const SizedBox(height: 16),
                  _field('OTP code', _otpCtrl, hint: '6-digit code',
                      keyboardType: TextInputType.number),
                  if (_devOtp != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Dev OTP: $_devOtp',
                          style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.primary)),
                    ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: GoogleFonts.dmSans(fontSize: 13, color: Colors.redAccent)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _loading ? null : (_otpSent ? _verifyOtp : _sendOtp),
                    child: _loading
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black))
                        : Text(_otpSent ? 'Verify OTP' : 'Send OTP',
                            style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {bool enabled = true, String? hint, TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          enabled: enabled,
          keyboardType: keyboardType,
          style: GoogleFonts.dmSans(fontSize: 15, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.surfaceDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primaryDeep),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primaryDeep),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Add `sendOtp` and `verifyOtp` to `ManageRemoteSource`**

In `lib/data/sources/remote/manage_remote_source.dart`, add — these call the public auth endpoints (no token needed, but manageDio is fine since it only adds token if present):

```dart
Future<String?> sendOtp(String phone) async {
  final resp = await _dio.post('/auth/send-otp', data: {'phone': phone});
  return resp.data['data']['otp_dev'] as String?;
}

Future<Map<String, dynamic>> verifyOtp(String phone, String otp) async {
  final resp = await _dio.post('/auth/verify-otp', data: {'phone': phone, 'otp': otp});
  return resp.data['data'] as Map<String, dynamic>;
}
```

- [ ] **Step 3: Analyze**

```bash
flutter analyze lib/presentation/screens/manage/manage_login_screen.dart lib/data/sources/remote/manage_remote_source.dart
```
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/manage/manage_login_screen.dart lib/data/sources/remote/manage_remote_source.dart
git commit -m "feat: add manage login screen with OTP flow"
```

---

### Task 9: Flutter — ManageKycScreen

**Files:**
- Create: `lib/presentation/screens/manage/manage_kyc_screen.dart`

- [ ] **Step 1: Create `manage_kyc_screen.dart`**

Create `lib/presentation/screens/manage/manage_kyc_screen.dart`:

```dart
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/sources/remote/manage_remote_source.dart';

class ManageKycScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existing; // pre-fill on resubmit
  const ManageKycScreen({super.key, this.existing});

  @override
  ConsumerState<ManageKycScreen> createState() => _ManageKycScreenState();
}

class _ManageKycScreenState extends ConsumerState<ManageKycScreen> {
  late final TextEditingController _businessName;
  late final TextEditingController _nidNumber;
  late final TextEditingController _payout;

  String? _nidFrontUrl;
  String? _nidBackUrl;
  String? _selfieUrl;
  bool _submitting = false;
  String? _error;
  String? _rejectionNote;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _businessName = TextEditingController(text: e?['business_name'] ?? '');
    _nidNumber = TextEditingController(text: e?['nid_number'] ?? '');
    _payout = TextEditingController(text: e?['payout_account'] ?? '');
    _nidFrontUrl = e?['nid_photo_front_url'];
    _nidBackUrl = e?['nid_photo_back_url'];
    _selfieUrl = e?['selfie_url'];
    if (e?['status'] == 'rejected') {
      _rejectionNote = e?['review_note'] as String?;
    }
  }

  @override
  void dispose() {
    _businessName.dispose();
    _nidNumber.dispose();
    _payout.dispose();
    super.dispose();
  }

  Future<String?> _pickAndUpload(String label, String bucket) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return null;
    final ext = file.extension ?? 'jpg';
    final contentType = 'image/$ext';
    final src = ref.read(manageRemoteSourceProvider);
    final presign = await src.presignUpload(bucket, '${label.toLowerCase().replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await src.uploadToPresignUrl(presign['url'] as String, bytes, contentType);
    return presign['public_url'] as String;
  }

  Future<void> _submit() async {
    if (_businessName.text.isEmpty || _nidNumber.text.isEmpty || _payout.text.isEmpty) {
      setState(() => _error = 'All fields are required.');
      return;
    }
    if (_nidFrontUrl == null || _nidBackUrl == null || _selfieUrl == null) {
      setState(() => _error = 'Please upload all required photos.');
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      await ref.read(manageRemoteSourceProvider).submitKyc({
        'business_name': _businessName.text,
        'nid_number': _nidNumber.text,
        'nid_photo_front_url': _nidFrontUrl,
        'nid_photo_back_url': _nidBackUrl,
        'selfie_url': _selfieUrl,
        'payout_account': _payout.text,
      });
      if (mounted) context.go('/kyc-pending');
    } catch (e) {
      setState(() => _error = 'Submission failed. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Verify Your Business', style: GoogleFonts.nunito(
                  fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text('Complete KYC to access your dashboard', style: GoogleFonts.dmSans(
                  fontSize: 14, color: AppColors.textSecondary)),
                if (_rejectionNote != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Previous application rejected', style: GoogleFonts.dmSans(
                          fontSize: 13, fontWeight: FontWeight.w700, color: Colors.redAccent)),
                        const SizedBox(height: 4),
                        Text(_rejectionNote!, style: GoogleFonts.dmSans(
                          fontSize: 13, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _textField('Business name *', _businessName),
                const SizedBox(height: 14),
                _textField('NID number *', _nidNumber),
                const SizedBox(height: 14),
                _textField('bKash / payout account *', _payout),
                const SizedBox(height: 24),
                Text('Documents', style: GoogleFonts.dmSans(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                _ImagePickerField(
                  label: 'NID Front *',
                  currentUrl: _nidFrontUrl,
                  onPick: () async {
                    final url = await _pickAndUpload('nid_front', 'kyc-documents');
                    if (url != null) setState(() => _nidFrontUrl = url);
                  },
                ),
                const SizedBox(height: 12),
                _ImagePickerField(
                  label: 'NID Back *',
                  currentUrl: _nidBackUrl,
                  onPick: () async {
                    final url = await _pickAndUpload('nid_back', 'kyc-documents');
                    if (url != null) setState(() => _nidBackUrl = url);
                  },
                ),
                const SizedBox(height: 12),
                _ImagePickerField(
                  label: 'Selfie *',
                  currentUrl: _selfieUrl,
                  onPick: () async {
                    final url = await _pickAndUpload('selfie', 'kyc-documents');
                    if (url != null) setState(() => _selfieUrl = url);
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: GoogleFonts.dmSans(fontSize: 13, color: Colors.redAccent)),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black))
                        : Text('Submit Application', style: GoogleFonts.dmSans(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _textField(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          style: GoogleFonts.dmSans(fontSize: 15, color: AppColors.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primaryDeep),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primaryDeep),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}

class _ImagePickerField extends StatelessWidget {
  const _ImagePickerField({
    required this.label,
    required this.currentUrl,
    required this.onPick,
  });

  final String label;
  final String? currentUrl;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPick,
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: currentUrl != null ? AppColors.primary : AppColors.primaryDeep,
            style: currentUrl != null ? BorderStyle.solid : BorderStyle.solid,
          ),
        ),
        child: Row(
          children: [
            Icon(
              currentUrl != null ? Icons.check_circle : Icons.upload_file,
              color: currentUrl != null ? AppColors.primary : AppColors.textSecondary,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                currentUrl != null ? '$label — uploaded ✓' : 'Tap to upload $label',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  color: currentUrl != null ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
flutter analyze lib/presentation/screens/manage/manage_kyc_screen.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/screens/manage/manage_kyc_screen.dart
git commit -m "feat: add manager KYC submission screen"
```

---

### Task 10: Flutter — ManageKycPendingScreen

**Files:**
- Create: `lib/presentation/screens/manage/manage_kyc_pending_screen.dart`

- [ ] **Step 1: Create the pending screen**

Create `lib/presentation/screens/manage/manage_kyc_pending_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/sources/remote/manage_remote_source.dart';

class ManageKycPendingScreen extends ConsumerStatefulWidget {
  const ManageKycPendingScreen({super.key});

  @override
  ConsumerState<ManageKycPendingScreen> createState() => _ManageKycPendingScreenState();
}

class _ManageKycPendingScreenState extends ConsumerState<ManageKycPendingScreen> {
  bool _checking = false;

  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    try {
      final kyc = await ref.read(manageRemoteSourceProvider).getMyKyc();
      if (!mounted) return;
      final status = kyc?['status'] as String? ?? 'none';
      if (status == 'approved') {
        context.go('/');
      } else if (status == 'rejected') {
        context.go('/kyc', extra: kyc);
      }
    } catch (_) {}
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hourglass_top_rounded, size: 64, color: AppColors.primary),
                const SizedBox(height: 24),
                Text('Application Submitted', style: GoogleFonts.nunito(
                  fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                Text(
                  "We'll review your KYC documents and notify you once approved. This usually takes 1–2 business days.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary, height: 1.6),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _checking ? null : _checkStatus,
                    child: _checking
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                        : Text('Check Status', style: GoogleFonts.dmSans(
                            fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
flutter analyze lib/presentation/screens/manage/manage_kyc_pending_screen.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/screens/manage/manage_kyc_pending_screen.dart
git commit -m "feat: add KYC pending screen"
```

---

### Task 11: Flutter — Update `main_manage.dart` router

**Files:**
- Modify: `lib/main_manage.dart`

- [ ] **Step 1: Replace the router in `main_manage.dart`**

Replace the entire content of `lib/main_manage.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_colors.dart';
import 'data/sources/remote/manage_remote_source.dart';
import 'presentation/screens/manage/manage_login_screen.dart';
import 'presentation/screens/manage/manage_kyc_screen.dart';
import 'presentation/screens/manage/manage_kyc_pending_screen.dart';
import 'presentation/screens/manage/manage_panel_screen.dart';

// KYC gate: reads token + KYC status and returns the correct initial route.
Future<String> _resolveStartRoute() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('manager_token');
  if (token == null) return '/login';
  return '/kyc-check'; // router handles status check
}

final _manageRouter = GoRouter(
  initialLocation: '/loading',
  routes: [
    GoRoute(path: '/loading', builder: (_, __) => const _LoadingScreen()),
    GoRoute(path: '/login', builder: (_, __) => const ManageLoginScreen()),
    GoRoute(
      path: '/kyc-check',
      builder: (_, __) => const _KycCheckScreen(),
    ),
    GoRoute(
      path: '/kyc',
      builder: (ctx, state) => ManageKycScreen(
        existing: state.extra as Map<String, dynamic>?,
      ),
    ),
    GoRoute(path: '/kyc-pending', builder: (_, __) => const ManageKycPendingScreen()),
    GoRoute(path: '/', builder: (_, __) => const ManagePanelScreen()),
  ],
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final startRoute = await _resolveStartRoute();
  _manageRouter.go(startRoute);
  runApp(
    ProviderScope(
      child: MaterialApp.router(
        title: 'Turfinn Turf Manager',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: AppColors.background,
          colorScheme: ColorScheme.dark(
            primary: AppColors.primary,
            surface: AppColors.background,
          ),
          textTheme: GoogleFonts.dmSansTextTheme(ThemeData.dark().textTheme),
        ),
        routerConfig: _manageRouter,
      ),
    ),
  );
}

// Briefly shown while resolving initial route
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
  );
}

// Checks KYC status and redirects
class _KycCheckScreen extends ConsumerStatefulWidget {
  const _KycCheckScreen();
  @override
  ConsumerState<_KycCheckScreen> createState() => _KycCheckScreenState();
}

class _KycCheckScreenState extends ConsumerState<_KycCheckScreen> {
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final kyc = await ref.read(manageRemoteSourceProvider).getMyKyc();
      if (!mounted) return;
      final status = kyc?['status'] as String? ?? 'none';
      switch (status) {
        case 'approved': context.go('/'); break;
        case 'submitted':
        case 'under_review': context.go('/kyc-pending'); break;
        case 'rejected': context.go('/kyc', extra: kyc); break;
        default: context.go('/kyc'); break;
      }
    } catch (_) {
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
  );
}
```

- [ ] **Step 2: Analyze**

```bash
flutter analyze lib/main_manage.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/main_manage.dart
git commit -m "feat: add auth+KYC router guards to manage panel"
```

---

### Task 12: Flutter — Pitch form: banner + gallery file pickers

**Files:**
- Modify: `lib/presentation/screens/manage/manage_panel_screen.dart`

- [ ] **Step 1: Add imports**

At the top of `manage_panel_screen.dart`, add:
```dart
import 'package:file_picker/file_picker.dart';
```

- [ ] **Step 2: Add state fields to `_PitchFormDialogState`**

In `_PitchFormDialogState`, add new fields after `_serviceRadius`:
```dart
String? _bannerUrl;
List<String> _galleryUrls = [];
bool _uploadingBanner = false;
bool _uploadingGallery = false;
```

- [ ] **Step 3: Initialize from existing pitch data**

In `initState()`, after `_serviceRadius = ...`, add:
```dart
_bannerUrl = e?['banner_url'] as String?;
final rawGallery = e?['image_urls'] as String? ?? '';
_galleryUrls = rawGallery.isEmpty ? [] : rawGallery.split(',').where((s) => s.trim().isNotEmpty).toList();
```

- [ ] **Step 4: Add upload helper to `_PitchFormDialogState`**

```dart
Future<String?> _uploadImage(String bucket) async {
  final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.first;
  if (file.bytes == null) return null;
  final ext = file.extension ?? 'jpg';
  final src = context.findAncestorStateOfType<ConsumerState>() != null
      ? null : null; // unused — use ref directly below
  // Note: _PitchFormDialog is a StatefulWidget, not ConsumerStatefulWidget.
  // Retrieve ManageRemoteSource via the parent ref passed in widget.
  final presign = await widget.remoteSource.presignUpload(
      bucket, 'pitch_${DateTime.now().millisecondsSinceEpoch}.$ext');
  await widget.remoteSource.uploadToPresignUrl(
      presign['url'] as String, file.bytes!, 'image/$ext');
  return presign['public_url'] as String;
}
```

**Important:** `_PitchFormDialog` currently has a `onSave` callback. Add a `remoteSource` parameter so the form can make upload calls:

Change `_PitchFormDialog` constructor to accept `ManageRemoteSource`:
```dart
class _PitchFormDialog extends StatefulWidget {
  const _PitchFormDialog({
    required this.onSave,
    required this.remoteSource,
    this.existing,
  });
  final Future<void> Function(Map<String, dynamic>) onSave;
  final ManageRemoteSource remoteSource;
  final Map<String, dynamic>? existing;
  ...
}
```

Update the call site (where `_PitchFormDialog` is instantiated) to pass `remoteSource: ref.read(manageRemoteSourceProvider)`.

- [ ] **Step 5: Replace the `_imageUrls` text field with gallery picker UI**

Find `_FormField(label: 'Address *', controller: _address)` and the `_imageUrls` text field. Replace the `_imageUrls` field with:

```dart
// Banner image
const SizedBox(height: 12),
Text('Banner Image *', style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary)),
const SizedBox(height: 6),
GestureDetector(
  onTap: _uploadingBanner ? null : () async {
    setState(() => _uploadingBanner = true);
    final url = await _uploadImage('pitch-images');
    if (url != null) setState(() => _bannerUrl = url);
    setState(() => _uploadingBanner = false);
  },
  child: Container(
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: AppColors.surfaceDark,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _bannerUrl != null ? AppColors.primary : AppColors.primaryDeep),
    ),
    child: Row(children: [
      if (_uploadingBanner)
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
      else
        Icon(_bannerUrl != null ? Icons.check_circle : Icons.image, size: 18,
            color: _bannerUrl != null ? AppColors.primary : AppColors.textSecondary),
      const SizedBox(width: 10),
      Text(_bannerUrl != null ? 'Banner uploaded ✓' : 'Tap to upload banner',
          style: GoogleFonts.dmSans(fontSize: 13,
              color: _bannerUrl != null ? AppColors.primary : AppColors.textSecondary)),
    ]),
  ),
),
const SizedBox(height: 12),
// Gallery photos (up to 5)
Text('Gallery Photos (up to 5)', style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary)),
const SizedBox(height: 6),
if (_galleryUrls.isNotEmpty)
  Wrap(
    spacing: 8,
    runSpacing: 8,
    children: _galleryUrls.map((url) => Stack(
      children: [
        Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primaryDeep),
            image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
          ),
        ),
        Positioned(
          top: 2, right: 2,
          child: GestureDetector(
            onTap: () => setState(() => _galleryUrls.remove(url)),
            child: Container(
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.background),
              child: const Icon(Icons.cancel, size: 18, color: AppColors.textSecondary),
            ),
          ),
        ),
      ],
    )).toList(),
  ),
if (_galleryUrls.length < 5)
  GestureDetector(
    onTap: _uploadingGallery ? null : () async {
      setState(() => _uploadingGallery = true);
      final url = await _uploadImage('pitch-images');
      if (url != null && _galleryUrls.length < 5) setState(() => _galleryUrls.add(url));
      setState(() => _uploadingGallery = false);
    },
    child: Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primaryDeep),
      ),
      child: Row(children: [
        if (_uploadingGallery)
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
        else
          const Icon(Icons.add_photo_alternate, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Text(_uploadingGallery ? 'Uploading...' : 'Add photo (${_galleryUrls.length}/5)',
            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
      ]),
    ),
  ),
```

- [ ] **Step 6: Include `banner_url` and `image_urls` in `_submit()`**

In the `_submit()` method, add to the data map:
```dart
'banner_url': _bannerUrl ?? '',
'image_urls': _galleryUrls.join(','),
```
Remove the old `'image_urls': _imageUrls.text` line and dispose of `_imageUrls` controller removal.

- [ ] **Step 7: Analyze**

```bash
flutter analyze lib/presentation/screens/manage/manage_panel_screen.dart
```
Expected: `No issues found!`

- [ ] **Step 8: Build + commit**

```bash
flutter build web --target lib/main_manage.dart --output build/web_manage --dart-define=API_BASE_URL=/api/v1 --pwa-strategy=none 2>&1 | tail -3
git add lib/presentation/screens/manage/manage_panel_screen.dart
git commit -m "feat: replace pitch image URL fields with file pickers"
```

---

## Self-Review Notes

- All five KYC statuses (`none`, `draft`, `submitted`, `under_review`, `approved`, `rejected`) are handled in the router.
- The `manage_token` key is used consistently in `manage_dio_client.dart`, `manage_login_screen.dart`, and the router.
- `build_runner` must be run after Task 7 to generate `manage_dio_client.g.dart`.
- After Task 6, run `docker compose down -v && docker compose up -d --build` to apply the `022_pitch_banner.sql` migration.
- `_PitchFormDialog` needs `remoteSource` passed in — find all instantiation sites and update them.
