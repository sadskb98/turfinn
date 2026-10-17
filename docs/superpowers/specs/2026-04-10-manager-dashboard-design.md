# Manager Dashboard — Analytics, Bookings & Financials Design

## Goal

Give turf managers a dedicated dashboard to track analytics, manage bookings (confirm/cancel), view financial reports, and manually create walk-in bookings outside of Turfinn.

## Scope

- **Audience:** Users with `role = "manager"`. Each manager sees data scoped to their own pitches only.
- **Access:** After login, if `user.role == "manager"`, the app routes to `ManagerShell` instead of the player home screen.
- **Not in scope:** Superadmin cross-platform views, payment processing, invoice generation.

---

## Architecture

### Approach: Clean `/manager` route group

All new backend endpoints live under `/api/v1/manager/*`, gated by a new `RequireManager()` middleware. Analytics are computed at query time via GORM raw SQL aggregations against existing tables — no new analytics tables or materialized views.

---

## Data Model

### Migration 010: Extend bookings table

Three new nullable columns added to `bookings`:

| Column | Type | Default | Purpose |
|---|---|---|---|
| `source` | `VARCHAR(20)` | `'turfinn'` | `turfinn` or `walk_in` — splits revenue in financial reports |
| `payment_method` | `VARCHAR(20)` | `NULL` | `cash`, `card`, or `transfer` — populated for walk-in bookings only |
| `payment_amount` | `NUMERIC(10,2)` | `NULL` | Actual amount collected (may differ from `total_cost`) |

All existing bookings default to `source = 'turfinn'`. No data migration required.

Customer name for walk-in bookings is stored in the existing `notes` field (format: `"Walk-in: <name>"`).

---

## Backend

### New middleware

`RequireManager()` in `backend/internal/interfaces/http/middleware/auth.go`:
- Calls `Auth()` first (validates JWT, sets `user_id` and `user_role` in context)
- Additionally checks `role == "manager"` — returns `403 Forbidden` if not

### New service

`backend/internal/application/service/analytics_service.go` — `AnalyticsService` with:
- `GetSummary(ctx, managerID, period)` — revenue total, booking count, occupancy %, avg rating for manager's pitches
- `GetRevenueChart(ctx, managerID, days)` — daily revenue array for last N days
- `GetPitchBreakdown(ctx, managerID, period)` — per-pitch: bookings, revenue, occupancy %, avg rating
- `GetFinancials(ctx, managerID, from, to)` — revenue split by source and payment method

All queries use `WHERE pitches.owner_id = managerID` to scope data to the manager's pitches.

**Occupancy % definition:** `(sum of confirmed booked hours in period) / (16h operating day × days in period × pitch count) × 100`. Uses 16h/day (08:00–00:00) as the operating window. Cancelled and pending bookings are excluded.

### New handler

`backend/internal/interfaces/http/handler/manager_handler.go` — `ManagerHandler` with 7 methods:

| Method | Path | Description |
|---|---|---|
| `GET` | `/manager/analytics/summary` | Summary cards — `period` query param: `today` (current calendar day), `week` (last 7 days), `month` (last 30 days) |
| `GET` | `/manager/analytics/revenue-chart` | Daily revenue — `days` query param (default 30, max 90). Returns array of `{date: "YYYY-MM-DD", amount: float}` |
| `GET` | `/manager/analytics/pitch-breakdown` | Per-pitch stats — period query param |
| `GET` | `/manager/bookings` | Paginated booking list — filterable by `status`, `source`, `date` |
| `POST` | `/manager/bookings` | Create walk-in booking — sets `source=walk_in`, `status=confirmed` immediately |
| `PUT` | `/manager/bookings/:id/status` | Confirm or cancel — ownership-checked (manager must own the pitch) |
| `GET` | `/manager/financials` | Revenue breakdown by source + payment method — `from`/`to` date params |

### New DTO file

`backend/internal/interfaces/dto/manager_dto.go`:
- `AnalyticsSummaryResponse` — revenue, bookings, occupancy, avg_rating
- `RevenueChartResponse` — array of `{date, amount}`
- `PitchBreakdownResponse` — array of per-pitch stats
- `ManagerBookingResponse` — booking list item with source/payment fields
- `CreateWalkInBookingRequest` — pitch_id, starts_at, ends_at, customer_name, payment_method, payment_amount
- `FinancialsResponse` — total, turfinn_total, walkin_total, by_payment_method

### New files

```
backend/migrations/010_booking_source.sql
backend/internal/application/service/analytics_service.go
backend/internal/interfaces/http/handler/manager_handler.go
backend/internal/interfaces/dto/manager_dto.go
```

### Modified files

```
backend/internal/domain/entity/booking.go       — add Source, PaymentMethod, PaymentAmount fields
backend/internal/interfaces/http/middleware/auth.go — add RequireManager()
backend/internal/interfaces/http/router.go      — register /manager/* routes
backend/cmd/api/main.go                         — wire AnalyticsService + ManagerHandler
```

---

## Flutter

### Navigation

`ManagerShell` — `ConsumerStatefulWidget` with a `BottomNavigationBar` (3 tabs: Analytics, Bookings, Financials). Shown when `user.role == "manager"` after login — wired in `app_router.dart` as a separate route branch.

### Screens

**Analytics screen** (`manager/analytics_screen.dart`):
- Period selector chip row: Today / Week / Month
- 4 summary cards: Revenue, Bookings, Occupancy %, Avg Rating
- Daily revenue bar chart (using `fl_chart` package)
- Per-pitch breakdown table (scrollable)

**Bookings screen** (`manager/bookings_screen.dart`):
- Filter chip row: All / Pending / Confirmed / Walk-in
- Paginated `ListView` of `ManagerBookingCard` widgets
- Each card shows: pitch name, time slot, customer, status badge, source badge (walk-in shown in blue)
- Swipe or tap → confirm / cancel for pending bookings
- FAB opens `ManualBookingSheet`

**Financials screen** (`manager/financials_screen.dart`):
- Period selector: Week / Month / Custom (date range picker)
- Revenue summary card: total, Turfinn portion, walk-in portion with percentage
- Payment method breakdown list: Cash / Card / Transfer with amounts

**Manual Booking Sheet** (`manager/manual_booking_sheet.dart`):
- `DraggableScrollableSheet` (bottom sheet)
- Step 1: Select pitch (dropdown of manager's pitches)
- Step 2: Pick date → pick start time → end time auto-filled to +1 hour, adjustable
- Step 3: Customer name (stored in `notes`)
- Step 4: Payment method (Cash / Card / Transfer) + amount
- Conflict check against existing bookings before submit
- On submit: `POST /manager/bookings` → booking created as `source=walk_in`, `status=confirmed`

### New Flutter files

```
lib/presentation/screens/manager/manager_shell.dart
lib/presentation/screens/manager/analytics_screen.dart
lib/presentation/screens/manager/analytics_provider.dart
lib/presentation/screens/manager/bookings_screen.dart
lib/presentation/screens/manager/bookings_provider.dart
lib/presentation/screens/manager/financials_screen.dart
lib/presentation/screens/manager/financials_provider.dart
lib/presentation/screens/manager/manual_booking_sheet.dart
lib/data/models/manager_models.dart
```

### Modified Flutter files

```
lib/core/router/app_router.dart    — add /manager branch, redirect by role after login
pubspec.yaml                       — add fl_chart for bar charts
```

### Dependencies

`fl_chart: ^0.69.0` — bar chart for daily revenue. No other new packages needed.

---

## Error handling

- `RequireManager()` returns `403` with `{"success": false, "error": "forbidden"}` for non-managers
- Manual booking conflict → `409 Conflict` (same as player booking flow)
- Analytics queries with no data return zero-value responses (not 404)
- Flutter providers handle loading / error / empty states on every screen

---

## Testing

- `analytics_service_test.go` — unit tests for each aggregation with mock DB
- Manual booking integration: conflict detection tested same as `BookingService.Create`
- Flutter: `flutter analyze` must pass with zero errors
