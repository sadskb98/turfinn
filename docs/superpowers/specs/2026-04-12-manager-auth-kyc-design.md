# Manager Auth + KYC — Design Spec
_Date: 2026-04-12_

## Overview

The turf manager panel (`main_manage.dart`) currently has no authentication — it routes directly to the dashboard. This spec adds OTP login, a KYC submission flow, and an approval gate so only verified managers can access the dashboard. It also replaces the broken image URL text fields on the pitch form with real file pickers backed by MinIO.

---

## 1. Router + Auth Flow

**Entry point:** `main_manage.dart`

On startup:
1. Read JWT from `SharedPreferences` key `manager_token`
2. If absent → `/login`
3. If present → `GET /manage/kyc/me`
4. Route based on KYC status:

| KYC status | Route |
|---|---|
| No token | `/login` |
| No record / `draft` | `/kyc` |
| `submitted` / `under_review` | `/kyc/pending` |
| `rejected` | `/kyc` (with rejection note banner) |
| `approved` | `/` (dashboard) |

GoRouter redirects handle all guards. JWT stored under key `manager_token` (separate from the player app's `auth_token`).

---

## 2. New Screens

### 2a. `ManageLoginScreen`
File: `lib/presentation/screens/manage/manage_login_screen.dart`

Two-step form:
- Step 1: phone number input → `POST /auth/send-otp`
- Step 2: OTP input (6 digits) → `POST /auth/verify-otp`
- On success: store JWT in SharedPreferences `manager_token`, navigate per KYC status

Same endpoints as the player app. Dark theme matching the manage panel (`AppColors.background`).

### 2b. `ManageKycScreen`
File: `lib/presentation/screens/manage/manage_kyc_screen.dart`

Single-page form with sections:

**Business Info:**
- Business name (text, required)
- NID number (text, required)
- Payout account / bKash number (text, required)

**Documents — file picker fields:**
- NID front photo (required)
- NID back photo (required)
- Selfie (required)

Each photo field: thumbnail preview when a file is selected, upload progress indicator, error state if upload fails.

If KYC was previously `rejected`, show a red banner at the top with `review_note` text and a "Your previous application was rejected" heading. Form is pre-filled with previously submitted values.

Submit button → `POST /manage/kyc` → navigate to `/kyc/pending`.

### 2c. `ManageKycPendingScreen`
File: `lib/presentation/screens/manage/manage_kyc_pending_screen.dart`

Shows:
- Status chip: `Submitted` (amber) or `Under Review` (blue)
- Submitted-at timestamp
- "We'll notify you once your application is reviewed" copy
- Refresh button → re-calls `GET /manage/kyc/me` → redirects to dashboard if approved

---

## 3. File Upload Flow

Used by KYC screen and pitch form. Same pattern for all:

1. `FilePicker.platform.pickFiles(type: FileType.image)` → get bytes + filename
2. `POST /upload/presign {filename, content_type}` → `{upload_url, public_url}`
3. `PUT` file bytes directly to `upload_url` (MinIO presigned URL)
4. Store `public_url` in form state

Shared widget: `_ImagePickerField` — renders a dashed-border upload zone when empty, thumbnail + remove button when filled. Defined as a private widget in `manage_kyc_screen.dart`, imported nowhere else.

---

## 4. Pitch Form Changes

File: `lib/presentation/screens/manage/manage_panel_screen.dart` (`_PitchFormDialogState`)

**Banner image (new field):**
- Single `_ImagePickerField` labelled "Banner Image *"
- Stored as `banner_url` in the pitch payload
- Required for new pitches

**Gallery photos (replace URL text field):**
- Multi-image picker: up to 5 files
- Shown as a row of thumbnail chips, each with an `×` remove button
- Add-photo button visible until 5 photos are selected
- Stored as comma-separated URLs in `image_urls` field (existing backend field)

---

## 5. Backend — New Endpoints

Both routes added under `/manage` group (auth + `RequireRole("manager", "admin")`).

### `GET /manage/kyc/me`
Returns own KYC record. If no record exists, returns `{"status": "none"}`.

Response:
```json
{
  "id": "uuid",
  "status": "draft|submitted|under_review|approved|rejected",
  "business_name": "...",
  "nid_number": "...",
  "nid_photo_front_url": "...",
  "nid_photo_back_url": "...",
  "selfie_url": "...",
  "payout_account": "...",
  "review_note": "...",
  "submitted_at": "2026-04-12T..."
}
```

### `POST /manage/kyc`
Upsert: creates record on first call, allows resubmit if current status is `draft` or `rejected`. Sets `status = "submitted"`, `submitted_at = NOW()`. Returns updated record.

Request body:
```json
{
  "business_name": "...",
  "nid_number": "...",
  "nid_photo_front_url": "...",
  "nid_photo_back_url": "...",
  "selfie_url": "...",
  "payout_account": "..."
}
```

Returns `400` if status is `submitted` or `under_review` (cannot resubmit while under review).

### `PUT /admin/kyc/:id/approve` (existing — update behaviour)
After setting `status = "approved"`, also run:
```sql
UPDATE users SET role = 'manager' WHERE id = $kyc.user_id
```
So the manager can access the dashboard on next login without any manual role grant step.

---

## 6. Pitch Model — Add `banner_url`

New migration: `022_pitch_banner.sql`
```sql
ALTER TABLE pitches ADD COLUMN IF NOT EXISTS banner_url TEXT;
```

Backend: add `BannerURL` field to pitch entity, DTO, and handler.
Flutter: add `bannerUrl` to `PitchModel` (freezed).

---

## Files Changed

| File | Change |
|---|---|
| `lib/main_manage.dart` | Add GoRouter with auth/KYC guards |
| `lib/presentation/screens/manage/manage_login_screen.dart` | New |
| `lib/presentation/screens/manage/manage_kyc_screen.dart` | New |
| `lib/presentation/screens/manage/manage_kyc_pending_screen.dart` | New |
| `lib/presentation/screens/manage/manage_panel_screen.dart` | Pitch form: banner + gallery file pickers |
| `lib/data/sources/remote/manage_remote_source.dart` | Add `submitKyc`, `getMyKyc` |
| `lib/data/models/pitch_model.dart` | Add `bannerUrl` |
| `backend/internal/interfaces/http/router.go` | Register new KYC routes |
| `backend/internal/interfaces/http/handler/manage_handler.go` | `GetMyKYC`, `SubmitKYC` handlers |
| `backend/internal/interfaces/http/handler/dispute_handler.go` | `ApproveKYC` sets user role |
| `backend/migrations/022_pitch_banner.sql` | Add `banner_url` column |

---

## Non-Goals

- No email notifications for KYC status changes (out of scope)
- No admin-side UI changes beyond the role-grant behaviour
- No manager registration via invitation code
