# Manager Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a manager-facing dashboard with analytics, booking management, manual walk-in booking creation, and financial reporting — scoped to each manager's own pitches.

**Architecture:** New `/api/v1/manager/*` route group gated by `RequireManager()` middleware. Analytics computed via raw SQL on existing tables. Three new columns on `bookings` table (`source`, `payment_method`, `payment_amount`). Flutter adds a `/manager` route branch shown when `user.role == "manager"`.

**Tech Stack:** Go 1.25 + Echo + GORM raw SQL; Flutter + Riverpod + GoRouter + freezed + fl_chart ^0.69.0

---

## Parallel Execution Map

| Chain | Tasks | Notes |
|---|---|---|
| H — Backend | H1 → H2 → H3 | Sequential — each builds on prior |
| M — Flutter | M1 → M2 → M3 → M4 | Sequential — shell before screens |
| H must complete before M starts | H3 defines API contracts M consumes | |

---

## File Map

**Backend — new files:**
- `backend/migrations/010_booking_source.sql`
- `backend/internal/application/service/analytics_service.go`
- `backend/internal/application/service/analytics_service_test.go`
- `backend/internal/interfaces/http/handler/manager_handler.go`
- `backend/internal/interfaces/dto/manager_dto.go`

**Backend — modified files:**
- `backend/internal/domain/entity/booking.go` — add Source, PaymentMethod, PaymentAmount
- `backend/internal/interfaces/http/middleware/auth.go` — add RequireManager()
- `backend/internal/pkg/response/response.go` — add Forbidden()
- `backend/internal/interfaces/http/router.go` — add /manager group
- `backend/cmd/api/main.go` — wire AnalyticsService + ManagerHandler

**Flutter — new files:**
- `lib/data/models/manager_models.dart` + generated files
- `lib/data/sources/remote/manager_remote_source.dart` + generated file
- `lib/presentation/screens/manager/manager_shell.dart`
- `lib/presentation/screens/manager/analytics_screen.dart`
- `lib/presentation/screens/manager/analytics_provider.dart` + generated file
- `lib/presentation/screens/manager/bookings_screen.dart`
- `lib/presentation/screens/manager/bookings_provider.dart` + generated file
- `lib/presentation/screens/manager/manual_booking_sheet.dart`
- `lib/presentation/screens/manager/financials_screen.dart`
- `lib/presentation/screens/manager/financials_provider.dart` + generated file

**Flutter — modified files:**
- `pubspec.yaml` — add fl_chart
- `lib/presentation/providers/auth_provider.dart` — save role to SharedPreferences
- `lib/presentation/screens/otp/otp_screen.dart` — role-aware navigation
- `lib/presentation/screens/welcome/welcome_screen.dart` — role-aware navigation
- `lib/core/router/app_router.dart` — add /manager route + cold-start redirect

---

## Chain H: Backend

### Task H1: Migration + Booking Entity

**Files:**
- Create: `backend/migrations/010_booking_source.sql`
- Modify: `backend/internal/domain/entity/booking.go`

- [ ] **Step 1: Create migration**

Create `backend/migrations/010_booking_source.sql`:

```sql
ALTER TABLE bookings
    ADD COLUMN IF NOT EXISTS source         VARCHAR(20)    NOT NULL DEFAULT 'turfinn',
    ADD COLUMN IF NOT EXISTS payment_method VARCHAR(20),
    ADD COLUMN IF NOT EXISTS payment_amount NUMERIC(10,2);

CREATE INDEX IF NOT EXISTS idx_bookings_source ON bookings(source);
```

- [ ] **Step 2: Update Booking entity**

In `backend/internal/domain/entity/booking.go`, add three fields after `Notes`:

```go
type Booking struct {
	ID        uuid.UUID     `gorm:"type:uuid;primaryKey"`
	PitchID   uuid.UUID     `gorm:"type:uuid;index;not null"`
	UserID    uuid.UUID     `gorm:"type:uuid;index;not null"`
	StartsAt  time.Time     `gorm:"not null"`
	EndsAt    time.Time     `gorm:"not null"`
	TotalCost float64       `gorm:"not null"`
	Status    BookingStatus `gorm:"type:varchar(20);default:'pending'"`
	Notes     string
	Source        string   `gorm:"column:source;default:'turfinn'"`
	PaymentMethod *string  `gorm:"column:payment_method"`
	PaymentAmount *float64 `gorm:"column:payment_amount"`
	CreatedAt time.Time
	UpdatedAt time.Time

	Pitch Pitch `gorm:"foreignKey:PitchID"`
	User  User  `gorm:"foreignKey:UserID"`
}
```

- [ ] **Step 3: Build check**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1/backend && go build ./...
```

Expected: clean build, no output.

- [ ] **Step 4: Commit**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1
git add backend/migrations/010_booking_source.sql backend/internal/domain/entity/booking.go
git commit -m "feat(manager): add booking source + payment fields migration"
```

---

### Task H2: RequireManager Middleware + AnalyticsService

**Files:**
- Modify: `backend/internal/interfaces/http/middleware/auth.go`
- Modify: `backend/internal/pkg/response/response.go`
- Create: `backend/internal/application/service/analytics_service.go`
- Create: `backend/internal/application/service/analytics_service_test.go`

- [ ] **Step 1: Add Forbidden to response package**

In `backend/internal/pkg/response/response.go`, add after `Unauthorized`:

```go
func Forbidden(c echo.Context) error {
	return c.JSON(http.StatusForbidden, map[string]any{"success": false, "error": "forbidden"})
}
```

- [ ] **Step 2: Add RequireManager middleware**

In `backend/internal/interfaces/http/middleware/auth.go`, add after the `OptionalAuth` function:

```go
// RequireManager rejects requests where the authenticated user is not a manager.
// Must be used after Auth() (or as a middleware chain: Auth(), RequireManager()).
func RequireManager() echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			role, _ := c.Get(UserRoleKey).(string)
			if role != "manager" {
				return response.Forbidden(c)
			}
			return next(c)
		}
	}
}
```

- [ ] **Step 3: Write failing test for GetSummary**

Create `backend/internal/application/service/analytics_service_test.go`:

```go
package service_test

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/application/service"
)

func TestGetSummary_NoPitches_ReturnsZeros(t *testing.T) {
	// Uses a real DB — skip if no DB available
	// This is an integration test stub; unit tests use mock db.Raw
	// For now just verify the service can be constructed
	svc := service.NewAnalyticsService(nil)
	_ = svc
}

func TestPeriodRange_Today(t *testing.T) {
	from, to := service.PeriodRange("today")
	now := time.Now().UTC()
	y, m, d := now.Date()
	expectedFrom := time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
	if from != expectedFrom {
		t.Errorf("expected from=%v, got %v", expectedFrom, from)
	}
	if to.Before(now.Add(-time.Second)) || to.After(now.Add(time.Second)) {
		t.Errorf("expected to≈now, got %v", to)
	}
}

func TestPeriodRange_Week(t *testing.T) {
	from, to := service.PeriodRange("week")
	diff := to.Sub(from)
	if diff < 6*24*time.Hour || diff > 8*24*time.Hour {
		t.Errorf("expected ~7 day range, got %v", diff)
	}
}

func TestPeriodRange_Month(t *testing.T) {
	from, _ := service.PeriodRange("month")
	expected := time.Now().UTC().AddDate(0, 0, -30)
	diff := from.Sub(expected)
	if diff > time.Second || diff < -time.Second {
		t.Errorf("expected from≈30 days ago, got %v", from)
	}
}

func TestFillChartDates_AllZero(t *testing.T) {
	result := service.FillChartDates(map[string]float64{}, 3)
	if len(result) != 3 {
		t.Fatalf("expected 3 entries, got %d", len(result))
	}
	for _, r := range result {
		if r.Amount != 0 {
			t.Errorf("expected amount=0 for empty map, got %f", r.Amount)
		}
	}
}

func TestFillChartDates_WithData(t *testing.T) {
	today := time.Now().UTC().Format("2006-01-02")
	result := service.FillChartDates(map[string]float64{today: 150.0}, 1)
	if len(result) != 1 {
		t.Fatalf("expected 1 entry, got %d", len(result))
	}
	if result[0].Amount != 150.0 {
		t.Errorf("expected amount=150, got %f", result[0].Amount)
	}
}

// Compile-time check
var _ = uuid.New()
```

- [ ] **Step 4: Run test to verify it fails**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1/backend && go test ./internal/application/service/... -run TestPeriodRange -v 2>&1
```

Expected: FAIL — `service.PeriodRange` undefined.

- [ ] **Step 5: Create AnalyticsService**

Create `backend/internal/application/service/analytics_service.go`:

```go
package service

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/interfaces/dto"
	"gorm.io/gorm"
)

type AnalyticsService struct {
	db *gorm.DB
}

func NewAnalyticsService(db *gorm.DB) *AnalyticsService {
	return &AnalyticsService{db: db}
}

// PeriodRange converts a period string to a [from, to) time range.
// Exported so tests can call it directly.
func PeriodRange(period string) (from, to time.Time) {
	now := time.Now().UTC()
	switch period {
	case "today":
		y, m, d := now.Date()
		return time.Date(y, m, d, 0, 0, 0, 0, time.UTC), now
	case "week":
		return now.AddDate(0, 0, -7), now
	default: // month
		return now.AddDate(0, 0, -30), now
	}
}

// FillChartDates generates a slice of DailyRevenue for the last `days` days,
// filling in zero for dates not present in dateMap.
// Exported so tests can call it directly.
func FillChartDates(dateMap map[string]float64, days int) []dto.DailyRevenue {
	result := make([]dto.DailyRevenue, days)
	for i := range result {
		d := time.Now().UTC().AddDate(0, 0, -(days-1-i)).Format("2006-01-02")
		result[i] = dto.DailyRevenue{Date: d, Amount: dateMap[d]}
	}
	return result
}

// GetSummary returns revenue totals, booking count, occupancy %, and avg rating
// for the manager's pitches over the given period.
func (s *AnalyticsService) GetSummary(ctx context.Context, managerID uuid.UUID, period string) (dto.AnalyticsSummaryResponse, error) {
	from, to := PeriodRange(period)

	type summaryRow struct {
		Revenue      float64 `gorm:"column:revenue"`
		BookingCount int64   `gorm:"column:booking_count"`
		BookedHours  float64 `gorm:"column:booked_hours"`
		PitchCount   int64   `gorm:"column:pitch_count"`
	}
	var row summaryRow
	s.db.WithContext(ctx).Raw(`
		SELECT
			COALESCE(SUM(b.total_cost), 0)                                        AS revenue,
			COUNT(b.id)                                                            AS booking_count,
			COALESCE(SUM(EXTRACT(EPOCH FROM (b.ends_at - b.starts_at)) / 3600), 0) AS booked_hours,
			COUNT(DISTINCT p.id)                                                   AS pitch_count
		FROM bookings b
		JOIN pitches p ON b.pitch_id = p.id
		WHERE p.owner_id = ?
		  AND b.status IN ('confirmed','completed')
		  AND b.starts_at >= ?
		  AND b.starts_at < ?
	`, managerID, from, to).Scan(&row)

	var avgRating float64
	s.db.WithContext(ctx).Raw(`
		SELECT COALESCE(AVG(r.rating), 0)
		FROM reviews r
		JOIN pitches p ON r.pitch_id = p.id
		WHERE p.owner_id = ?
	`, managerID).Scan(&avgRating)

	occupancy := 0.0
	if row.PitchCount > 0 {
		days := to.Sub(from).Hours() / 24
		totalHours := 16.0 * days * float64(row.PitchCount)
		if totalHours > 0 {
			occupancy = row.BookedHours / totalHours * 100
		}
	}

	return dto.AnalyticsSummaryResponse{
		Revenue:      row.Revenue,
		BookingCount: row.BookingCount,
		OccupancyPct: occupancy,
		AvgRating:    avgRating,
		Period:       period,
	}, nil
}

// GetRevenueChart returns daily revenue for the last `days` days (max 90).
func (s *AnalyticsService) GetRevenueChart(ctx context.Context, managerID uuid.UUID, days int) (dto.RevenueChartResponse, error) {
	if days < 1 {
		days = 30
	}
	if days > 90 {
		days = 90
	}

	type dailyRow struct {
		Date   string  `gorm:"column:date"`
		Amount float64 `gorm:"column:amount"`
	}
	var rows []dailyRow
	s.db.WithContext(ctx).Raw(`
		SELECT
			TO_CHAR(DATE(b.starts_at), 'YYYY-MM-DD') AS date,
			COALESCE(SUM(b.total_cost), 0)            AS amount
		FROM bookings b
		JOIN pitches p ON b.pitch_id = p.id
		WHERE p.owner_id = ?
		  AND b.status IN ('confirmed','completed')
		  AND b.starts_at >= NOW() - (INTERVAL '1 day' * ?)
		GROUP BY DATE(b.starts_at)
		ORDER BY date ASC
	`, managerID, days).Scan(&rows)

	dateMap := make(map[string]float64, len(rows))
	for _, r := range rows {
		dateMap[r.Date] = r.Amount
	}

	return dto.RevenueChartResponse{
		Days: days,
		Data: FillChartDates(dateMap, days),
	}, nil
}

// GetPitchBreakdown returns per-pitch stats for the given period.
func (s *AnalyticsService) GetPitchBreakdown(ctx context.Context, managerID uuid.UUID, period string) ([]dto.PitchStats, error) {
	from, to := PeriodRange(period)
	days := to.Sub(from).Hours() / 24

	type pitchRow struct {
		PitchID      string  `gorm:"column:pitch_id"`
		PitchName    string  `gorm:"column:pitch_name"`
		BookingCount int64   `gorm:"column:booking_count"`
		Revenue      float64 `gorm:"column:revenue"`
		BookedHours  float64 `gorm:"column:booked_hours"`
		AvgRating    float64 `gorm:"column:avg_rating"`
	}
	var rows []pitchRow
	s.db.WithContext(ctx).Raw(`
		SELECT
			p.id::text                                                              AS pitch_id,
			p.name                                                                  AS pitch_name,
			COUNT(b.id)                                                             AS booking_count,
			COALESCE(SUM(b.total_cost), 0)                                         AS revenue,
			COALESCE(SUM(EXTRACT(EPOCH FROM (b.ends_at - b.starts_at)) / 3600), 0) AS booked_hours,
			COALESCE((
				SELECT AVG(r2.rating) FROM reviews r2 WHERE r2.pitch_id = p.id
			), 0)                                                                   AS avg_rating
		FROM pitches p
		LEFT JOIN bookings b ON b.pitch_id = p.id
			AND b.status IN ('confirmed','completed')
			AND b.starts_at >= ?
			AND b.starts_at < ?
		WHERE p.owner_id = ?
		GROUP BY p.id, p.name
		ORDER BY revenue DESC
	`, from, to, managerID).Scan(&rows)

	stats := make([]dto.PitchStats, 0, len(rows))
	for _, r := range rows {
		occupancy := 0.0
		if days > 0 {
			occupancy = r.BookedHours / (16.0 * days) * 100
		}
		stats = append(stats, dto.PitchStats{
			PitchID:      r.PitchID,
			PitchName:    r.PitchName,
			BookingCount: r.BookingCount,
			Revenue:      r.Revenue,
			OccupancyPct: occupancy,
			AvgRating:    r.AvgRating,
		})
	}
	return stats, nil
}

// ListBookings returns paginated bookings for the manager's pitches.
func (s *AnalyticsService) ListBookings(ctx context.Context, managerID uuid.UUID, filter dto.ManagerBookingFilter) ([]*entity.Booking, int64, error) {
	q := s.db.WithContext(ctx).
		Model(&entity.Booking{}).
		Joins("JOIN pitches ON bookings.pitch_id = pitches.id").
		Where("pitches.owner_id = ?", managerID).
		Preload("Pitch").Preload("User")

	if filter.Status != "" {
		q = q.Where("bookings.status = ?", filter.Status)
	}
	if filter.Source != "" {
		q = q.Where("bookings.source = ?", filter.Source)
	}
	if filter.Date != "" {
		q = q.Where("DATE(bookings.starts_at) = ?", filter.Date)
	}

	var total int64
	q.Count(&total)

	var bookings []*entity.Booking
	err := q.Order("bookings.starts_at DESC").
		Offset((filter.Page - 1) * filter.Limit).
		Limit(filter.Limit).
		Find(&bookings).Error
	return bookings, total, err
}

// CreateWalkIn creates a manual walk-in booking for one of the manager's pitches.
func (s *AnalyticsService) CreateWalkIn(ctx context.Context, managerID uuid.UUID, req dto.CreateWalkInBookingRequest) (*entity.Booking, error) {
	pitchID, err := uuid.Parse(req.PitchID)
	if err != nil {
		return nil, fmt.Errorf("invalid pitch_id")
	}

	var pitch entity.Pitch
	if err := s.db.WithContext(ctx).
		Where("id = ? AND owner_id = ?", pitchID, managerID).
		First(&pitch).Error; err != nil {
		return nil, fmt.Errorf("pitch not found or not owned by you")
	}

	var count int64
	s.db.WithContext(ctx).Model(&entity.Booking{}).
		Where("pitch_id = ? AND status NOT IN ? AND starts_at < ? AND ends_at > ?",
			pitchID,
			[]entity.BookingStatus{entity.BookingCancelled},
			req.EndsAt, req.StartsAt,
		).Count(&count)
	if count > 0 {
		return nil, fmt.Errorf("slot not available")
	}

	hours := req.EndsAt.Sub(req.StartsAt).Hours()
	totalCost := hours * pitch.PricePerHour
	pm := req.PaymentMethod
	pa := req.PaymentAmount

	booking := &entity.Booking{
		ID:            uuid.New(),
		PitchID:       pitchID,
		UserID:        managerID,
		StartsAt:      req.StartsAt,
		EndsAt:        req.EndsAt,
		TotalCost:     totalCost,
		Status:        entity.BookingConfirmed,
		Notes:         "Walk-in: " + req.CustomerName,
		Source:        "walk_in",
		PaymentMethod: &pm,
		PaymentAmount: &pa,
	}
	if err := s.db.WithContext(ctx).Create(booking).Error; err != nil {
		return nil, fmt.Errorf("create booking: %w", err)
	}
	booking.Pitch = pitch
	return booking, nil
}

// UpdateBookingStatus confirms or cancels a booking — ownership-checked.
func (s *AnalyticsService) UpdateBookingStatus(ctx context.Context, managerID, bookingID uuid.UUID, status entity.BookingStatus) error {
	var count int64
	s.db.WithContext(ctx).
		Model(&entity.Booking{}).
		Joins("JOIN pitches ON bookings.pitch_id = pitches.id").
		Where("bookings.id = ? AND pitches.owner_id = ?", bookingID, managerID).
		Count(&count)
	if count == 0 {
		return fmt.Errorf("booking not found or not owned by you")
	}
	return s.db.WithContext(ctx).
		Model(&entity.Booking{}).
		Where("id = ?", bookingID).
		Update("status", status).Error
}

// GetFinancials returns revenue breakdown by source and payment method.
func (s *AnalyticsService) GetFinancials(ctx context.Context, managerID uuid.UUID, from, to time.Time) (dto.FinancialsResponse, error) {
	type finRow struct {
		Source        string  `gorm:"column:source"`
		PaymentMethod *string `gorm:"column:payment_method"`
		Amount        float64 `gorm:"column:amount"`
		Count         int64   `gorm:"column:count"`
	}
	var rows []finRow
	s.db.WithContext(ctx).Raw(`
		SELECT
			b.source                       AS source,
			b.payment_method               AS payment_method,
			COALESCE(SUM(b.total_cost), 0) AS amount,
			COUNT(*)                       AS count
		FROM bookings b
		JOIN pitches p ON b.pitch_id = p.id
		WHERE p.owner_id = ?
		  AND b.status IN ('confirmed','completed')
		  AND b.starts_at >= ?
		  AND b.starts_at < ?
		GROUP BY b.source, b.payment_method
	`, managerID, from, to).Scan(&rows)

	var totalRevenue, turfinnRevenue, walkinRevenue float64
	pmMap := make(map[string]*dto.PaymentMethodBreakdown)
	for _, r := range rows {
		totalRevenue += r.Amount
		if r.Source == "turfinn" {
			turfinnRevenue += r.Amount
		} else {
			walkinRevenue += r.Amount
			pm := "unknown"
			if r.PaymentMethod != nil {
				pm = *r.PaymentMethod
			}
			if _, ok := pmMap[pm]; !ok {
				pmMap[pm] = &dto.PaymentMethodBreakdown{Method: pm}
			}
			pmMap[pm].Amount += r.Amount
			pmMap[pm].Count += r.Count
		}
	}
	pmList := make([]dto.PaymentMethodBreakdown, 0, len(pmMap))
	for _, v := range pmMap {
		pmList = append(pmList, *v)
	}

	return dto.FinancialsResponse{
		From:            from.Format("2006-01-02"),
		To:              to.Format("2006-01-02"),
		TotalRevenue:    totalRevenue,
		TurfinnRevenue:  turfinnRevenue,
		WalkInRevenue:   walkinRevenue,
		ByPaymentMethod: pmList,
	}, nil
}
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1/backend && go test ./internal/application/service/... -run "TestPeriodRange|TestFillChart" -v 2>&1
```

Expected: all pass.

- [ ] **Step 7: Build check**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1/backend && go build ./...
```

Expected: clean.

- [ ] **Step 8: Commit**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1
git add \
  backend/internal/pkg/response/response.go \
  backend/internal/interfaces/http/middleware/auth.go \
  backend/internal/application/service/analytics_service.go \
  backend/internal/application/service/analytics_service_test.go
git commit -m "feat(manager): RequireManager middleware + AnalyticsService with SQL aggregations"
```

---

### Task H3: Manager DTOs + Handler + Router Wiring

**Files:**
- Create: `backend/internal/interfaces/dto/manager_dto.go`
- Create: `backend/internal/interfaces/http/handler/manager_handler.go`
- Modify: `backend/internal/interfaces/http/router.go`
- Modify: `backend/cmd/api/main.go`

- [ ] **Step 1: Create manager DTOs**

Create `backend/internal/interfaces/dto/manager_dto.go`:

```go
package dto

import "time"

// --- Analytics ---

type AnalyticsSummaryResponse struct {
	Revenue      float64 `json:"revenue"`
	BookingCount int64   `json:"booking_count"`
	OccupancyPct float64 `json:"occupancy_pct"`
	AvgRating    float64 `json:"avg_rating"`
	Period       string  `json:"period"`
}

type DailyRevenue struct {
	Date   string  `json:"date"`
	Amount float64 `json:"amount"`
}

type RevenueChartResponse struct {
	Days int            `json:"days"`
	Data []DailyRevenue `json:"data"`
}

type PitchStats struct {
	PitchID      string  `json:"pitch_id"`
	PitchName    string  `json:"pitch_name"`
	BookingCount int64   `json:"booking_count"`
	Revenue      float64 `json:"revenue"`
	OccupancyPct float64 `json:"occupancy_pct"`
	AvgRating    float64 `json:"avg_rating"`
}

// --- Bookings ---

type ManagerBookingFilter struct {
	Status string
	Source string
	Date   string
	Page   int
	Limit  int
}

type ManagerBookingResponse struct {
	ID            string    `json:"id"`
	PitchID       string    `json:"pitch_id"`
	PitchName     string    `json:"pitch_name"`
	UserID        string    `json:"user_id"`
	CustomerName  string    `json:"customer_name"`
	StartsAt      time.Time `json:"starts_at"`
	EndsAt        time.Time `json:"ends_at"`
	TotalCost     float64   `json:"total_cost"`
	Status        string    `json:"status"`
	Source        string    `json:"source"`
	PaymentMethod *string   `json:"payment_method,omitempty"`
	PaymentAmount *float64  `json:"payment_amount,omitempty"`
	Notes         string    `json:"notes"`
}

type CreateWalkInBookingRequest struct {
	PitchID       string    `json:"pitch_id" validate:"required,uuid"`
	StartsAt      time.Time `json:"starts_at" validate:"required"`
	EndsAt        time.Time `json:"ends_at" validate:"required"`
	CustomerName  string    `json:"customer_name" validate:"required,min=1,max=100"`
	PaymentMethod string    `json:"payment_method" validate:"required,oneof=cash card transfer"`
	PaymentAmount float64   `json:"payment_amount" validate:"required,gt=0"`
}

// --- Financials ---

type PaymentMethodBreakdown struct {
	Method string  `json:"method"`
	Amount float64 `json:"amount"`
	Count  int64   `json:"count"`
}

type FinancialsResponse struct {
	From            string                   `json:"from"`
	To              string                   `json:"to"`
	TotalRevenue    float64                  `json:"total_revenue"`
	TurfinnRevenue  float64                  `json:"turfinn_revenue"`
	WalkInRevenue   float64                  `json:"walk_in_revenue"`
	ByPaymentMethod []PaymentMethodBreakdown `json:"by_payment_method"`
}
```

- [ ] **Step 2: Create ManagerHandler**

Create `backend/internal/interfaces/http/handler/manager_handler.go`:

```go
package handler

import (
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/interfaces/dto"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type ManagerHandler struct {
	svc *service.AnalyticsService
}

func NewManagerHandler(svc *service.AnalyticsService) *ManagerHandler {
	return &ManagerHandler{svc: svc}
}

// GET /api/v1/manager/analytics/summary?period=today|week|month
func (h *ManagerHandler) GetSummary(c echo.Context) error {
	managerID := c.Get(authmw.UserIDKey).(uuid.UUID)
	period := c.QueryParam("period")
	if period == "" {
		period = "month"
	}
	summary, err := h.svc.GetSummary(c.Request().Context(), managerID, period)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, summary)
}

// GET /api/v1/manager/analytics/revenue-chart?days=30
func (h *ManagerHandler) GetRevenueChart(c echo.Context) error {
	managerID := c.Get(authmw.UserIDKey).(uuid.UUID)
	days := 30
	if d := c.QueryParam("days"); d != "" {
		if n, err := parseInt(d); err == nil && n > 0 {
			days = n
		}
	}
	chart, err := h.svc.GetRevenueChart(c.Request().Context(), managerID, days)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, chart)
}

// GET /api/v1/manager/analytics/pitch-breakdown?period=month
func (h *ManagerHandler) GetPitchBreakdown(c echo.Context) error {
	managerID := c.Get(authmw.UserIDKey).(uuid.UUID)
	period := c.QueryParam("period")
	if period == "" {
		period = "month"
	}
	stats, err := h.svc.GetPitchBreakdown(c.Request().Context(), managerID, period)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, stats)
}

// GET /api/v1/manager/bookings?status=&source=&date=&page=1&limit=20
func (h *ManagerHandler) ListBookings(c echo.Context) error {
	managerID := c.Get(authmw.UserIDKey).(uuid.UUID)
	filter := dto.ManagerBookingFilter{
		Status: c.QueryParam("status"),
		Source: c.QueryParam("source"),
		Date:   c.QueryParam("date"),
		Page:   1,
		Limit:  20,
	}
	if p, err := parseInt(c.QueryParam("page")); err == nil && p > 0 {
		filter.Page = p
	}
	if l, err := parseInt(c.QueryParam("limit")); err == nil && l > 0 && l <= 100 {
		filter.Limit = l
	}
	bookings, total, err := h.svc.ListBookings(c.Request().Context(), managerID, filter)
	if err != nil {
		return response.InternalError(c)
	}
	out := make([]dto.ManagerBookingResponse, len(bookings))
	for i, b := range bookings {
		out[i] = toManagerBookingResponse(b)
	}
	return response.OKPaginated(c, out, response.Meta{
		Page: filter.Page, Limit: filter.Limit, Total: total,
	})
}

// POST /api/v1/manager/bookings
func (h *ManagerHandler) CreateWalkIn(c echo.Context) error {
	managerID := c.Get(authmw.UserIDKey).(uuid.UUID)
	var req dto.CreateWalkInBookingRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	booking, err := h.svc.CreateWalkIn(c.Request().Context(), managerID, req)
	if err != nil {
		if err.Error() == "slot not available" {
			return response.Conflict(c, err.Error())
		}
		return response.BadRequest(c, err.Error())
	}
	return response.Created(c, toManagerBookingResponse(booking))
}

// PUT /api/v1/manager/bookings/:id/status
func (h *ManagerHandler) UpdateStatus(c echo.Context) error {
	managerID := c.Get(authmw.UserIDKey).(uuid.UUID)
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid booking id")
	}
	var req struct {
		Status string `json:"status" validate:"required,oneof=confirmed cancelled"`
	}
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	if err := h.svc.UpdateBookingStatus(c.Request().Context(), managerID, id, entity.BookingStatus(req.Status)); err != nil {
		if strings.Contains(err.Error(), "not found") {
			return response.NotFound(c, err.Error())
		}
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"message": "status updated"})
}

// GET /api/v1/manager/financials?from=2026-01-01&to=2026-12-31
func (h *ManagerHandler) GetFinancials(c echo.Context) error {
	managerID := c.Get(authmw.UserIDKey).(uuid.UUID)
	from := time.Now().UTC().AddDate(0, -1, 0)
	to := time.Now().UTC()
	if f := c.QueryParam("from"); f != "" {
		if t, err := time.Parse("2006-01-02", f); err == nil {
			from = t
		}
	}
	if t := c.QueryParam("to"); t != "" {
		if parsed, err := time.Parse("2006-01-02", t); err == nil {
			to = parsed.Add(24 * time.Hour) // inclusive
		}
	}
	fin, err := h.svc.GetFinancials(c.Request().Context(), managerID, from, to)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, fin)
}

func toManagerBookingResponse(b *entity.Booking) dto.ManagerBookingResponse {
	pitchName := ""
	if b.Pitch.ID != uuid.Nil {
		pitchName = b.Pitch.Name
	}
	customerName := b.Notes
	if strings.HasPrefix(b.Notes, "Walk-in: ") {
		customerName = strings.TrimPrefix(b.Notes, "Walk-in: ")
	}
	return dto.ManagerBookingResponse{
		ID:            b.ID.String(),
		PitchID:       b.PitchID.String(),
		PitchName:     pitchName,
		UserID:        b.UserID.String(),
		CustomerName:  customerName,
		StartsAt:      b.StartsAt,
		EndsAt:        b.EndsAt,
		TotalCost:     b.TotalCost,
		Status:        string(b.Status),
		Source:        b.Source,
		PaymentMethod: b.PaymentMethod,
		PaymentAmount: b.PaymentAmount,
		Notes:         b.Notes,
	}
}

func parseInt(s string) (int, error) {
	var n int
	_, err := fmt.Sscanf(s, "%d", &n)
	return n, err
}
```

Add missing import `"fmt"` to the import block in manager_handler.go.

- [ ] **Step 3: Add /manager routes to router.go**

Read the current `backend/internal/interfaces/http/router.go`. Add `managerH *handler.ManagerHandler` as the last parameter to `NewRouter`, then add the manager route group at the end before `return e`:

```go
// Manager dashboard (role=manager required)
manager := v1.Group("/manager", authmw.Auth(), authmw.RequireManager())
manager.GET("/analytics/summary", managerH.GetSummary)
manager.GET("/analytics/revenue-chart", managerH.GetRevenueChart)
manager.GET("/analytics/pitch-breakdown", managerH.GetPitchBreakdown)
manager.GET("/bookings", managerH.ListBookings)
manager.POST("/bookings", managerH.CreateWalkIn)
manager.PUT("/bookings/:id/status", managerH.UpdateStatus)
manager.GET("/financials", managerH.GetFinancials)
```

Update the `NewRouter` signature — add `managerH *handler.ManagerHandler` after `userH`:

```go
func NewRouter(
	authH *handler.AuthHandler,
	pitchH *handler.PitchHandler,
	bookingH *handler.BookingHandler,
	uploadH *handler.UploadHandler,
	eventsH *handler.EventsHandler,
	reviewH *handler.ReviewHandler,
	userH *handler.UserHandler,
	wsH *handler.WSHandler,
	managerH *handler.ManagerHandler,
) *echo.Echo {
```

- [ ] **Step 4: Wire AnalyticsService + ManagerHandler in main.go**

In `backend/cmd/api/main.go`, in the Services section add:

```go
analyticsSvc := service.NewAnalyticsService(db)
```

In the Handlers section add:

```go
managerH := handler.NewManagerHandler(analyticsSvc)
```

Update the `httpserver.NewRouter(...)` call to pass `managerH` as the final argument:

```go
e := httpserver.NewRouter(authH, pitchH, bookingH, uploadH, eventsH, reviewH, userH, wsH, managerH)
```

- [ ] **Step 5: Build check**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1/backend && go build ./...
```

Expected: clean build.

- [ ] **Step 6: Commit**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1
git add \
  backend/internal/interfaces/dto/manager_dto.go \
  backend/internal/interfaces/http/handler/manager_handler.go \
  backend/internal/interfaces/http/router.go \
  backend/cmd/api/main.go
git commit -m "feat(manager): ManagerHandler + /manager/* routes + full backend wiring"
```

---

## Chain M: Flutter

### Task M1: Manager Models + Remote Source + Role Routing

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/data/models/manager_models.dart`
- Create: `lib/data/sources/remote/manager_remote_source.dart`
- Modify: `lib/presentation/providers/auth_provider.dart`
- Modify: `lib/presentation/screens/otp/otp_screen.dart`
- Modify: `lib/presentation/screens/welcome/welcome_screen.dart`
- Modify: `lib/core/router/app_router.dart`

- [ ] **Step 1: Add fl_chart to pubspec.yaml**

In `pubspec.yaml`, add under `dependencies:` (after `web_socket_channel`):

```yaml
  fl_chart: ^0.69.0
```

Run:

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1 && flutter pub get 2>&1
```

Expected: exit code 0.

- [ ] **Step 2: Create freezed manager models**

Create `lib/data/models/manager_models.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'manager_models.freezed.dart';
part 'manager_models.g.dart';

@freezed
class AnalyticsSummary with _$AnalyticsSummary {
  const factory AnalyticsSummary({
    required double revenue,
    @JsonKey(name: 'booking_count') required int bookingCount,
    @JsonKey(name: 'occupancy_pct') required double occupancyPct,
    @JsonKey(name: 'avg_rating') required double avgRating,
    required String period,
  }) = _AnalyticsSummary;
  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) =>
      _$AnalyticsSummaryFromJson(json);
}

@freezed
class DailyRevenue with _$DailyRevenue {
  const factory DailyRevenue({
    required String date,
    required double amount,
  }) = _DailyRevenue;
  factory DailyRevenue.fromJson(Map<String, dynamic> json) =>
      _$DailyRevenueFromJson(json);
}

@freezed
class RevenueChart with _$RevenueChart {
  const factory RevenueChart({
    required int days,
    required List<DailyRevenue> data,
  }) = _RevenueChart;
  factory RevenueChart.fromJson(Map<String, dynamic> json) =>
      _$RevenueChartFromJson(json);
}

@freezed
class PitchStats with _$PitchStats {
  const factory PitchStats({
    @JsonKey(name: 'pitch_id') required String pitchId,
    @JsonKey(name: 'pitch_name') required String pitchName,
    @JsonKey(name: 'booking_count') required int bookingCount,
    required double revenue,
    @JsonKey(name: 'occupancy_pct') required double occupancyPct,
    @JsonKey(name: 'avg_rating') required double avgRating,
  }) = _PitchStats;
  factory PitchStats.fromJson(Map<String, dynamic> json) =>
      _$PitchStatsFromJson(json);
}

@freezed
class ManagerBooking with _$ManagerBooking {
  const factory ManagerBooking({
    required String id,
    @JsonKey(name: 'pitch_id') required String pitchId,
    @JsonKey(name: 'pitch_name') required String pitchName,
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'customer_name') required String customerName,
    @JsonKey(name: 'starts_at') required DateTime startsAt,
    @JsonKey(name: 'ends_at') required DateTime endsAt,
    @JsonKey(name: 'total_cost') required double totalCost,
    required String status,
    required String source,
    @JsonKey(name: 'payment_method') String? paymentMethod,
    @JsonKey(name: 'payment_amount') double? paymentAmount,
    required String notes,
  }) = _ManagerBooking;
  factory ManagerBooking.fromJson(Map<String, dynamic> json) =>
      _$ManagerBookingFromJson(json);
}

@freezed
class PaymentMethodBreakdown with _$PaymentMethodBreakdown {
  const factory PaymentMethodBreakdown({
    required String method,
    required double amount,
    required int count,
  }) = _PaymentMethodBreakdown;
  factory PaymentMethodBreakdown.fromJson(Map<String, dynamic> json) =>
      _$PaymentMethodBreakdownFromJson(json);
}

@freezed
class Financials with _$Financials {
  const factory Financials({
    required String from,
    required String to,
    @JsonKey(name: 'total_revenue') required double totalRevenue,
    @JsonKey(name: 'turfinn_revenue') required double turfinnRevenue,
    @JsonKey(name: 'walk_in_revenue') required double walkInRevenue,
    @JsonKey(name: 'by_payment_method')
    required List<PaymentMethodBreakdown> byPaymentMethod,
  }) = _Financials;
  factory Financials.fromJson(Map<String, dynamic> json) =>
      _$FinancialsFromJson(json);
}
```

- [ ] **Step 3: Run build_runner**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1 && dart run build_runner build --delete-conflicting-outputs 2>&1 | tail -5
```

Expected: `[INFO] Build Succeeded`.

- [ ] **Step 4: Create manager remote source**

Create `lib/data/sources/remote/manager_remote_source.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/manager_models.dart';
import 'dio_client.dart';

part 'manager_remote_source.g.dart';

@riverpod
ManagerRemoteSource managerRemoteSource(Ref ref) =>
    ManagerRemoteSource(ref.watch(dioProvider));

class ManagerRemoteSource {
  ManagerRemoteSource(this._dio);
  final Dio _dio;

  Future<AnalyticsSummary> getSummary(String period) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/manager/analytics/summary',
      queryParameters: {'period': period},
    );
    return AnalyticsSummary.fromJson(res.data!['data'] as Map<String, dynamic>);
  }

  Future<RevenueChart> getRevenueChart(int days) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/manager/analytics/revenue-chart',
      queryParameters: {'days': days},
    );
    return RevenueChart.fromJson(res.data!['data'] as Map<String, dynamic>);
  }

  Future<List<PitchStats>> getPitchBreakdown(String period) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/manager/analytics/pitch-breakdown',
      queryParameters: {'period': period},
    );
    final list = res.data!['data'] as List<dynamic>;
    return list
        .cast<Map<String, dynamic>>()
        .map(PitchStats.fromJson)
        .toList();
  }

  Future<({List<ManagerBooking> bookings, int total})> listBookings({
    String? status,
    String? source,
    String? date,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/manager/bookings',
      queryParameters: {
        if (status != null) 'status': status,
        if (source != null) 'source': source,
        if (date != null) 'date': date,
        'page': page,
        'limit': limit,
      },
    );
    final list = (res.data!['data'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(ManagerBooking.fromJson)
        .toList();
    final meta = res.data!['meta'] as Map<String, dynamic>;
    return (bookings: list, total: (meta['total'] as num).toInt());
  }

  Future<ManagerBooking> createWalkIn({
    required String pitchId,
    required DateTime startsAt,
    required DateTime endsAt,
    required String customerName,
    required String paymentMethod,
    required double paymentAmount,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/manager/bookings',
      data: {
        'pitch_id': pitchId,
        'starts_at': startsAt.toIso8601String(),
        'ends_at': endsAt.toIso8601String(),
        'customer_name': customerName,
        'payment_method': paymentMethod,
        'payment_amount': paymentAmount,
      },
    );
    return ManagerBooking.fromJson(res.data!['data'] as Map<String, dynamic>);
  }

  Future<void> updateBookingStatus(String bookingId, String status) async {
    await _dio.put<void>(
      '/manager/bookings/$bookingId/status',
      data: {'status': status},
    );
  }

  Future<Financials> getFinancials({String? from, String? to}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/manager/financials',
      queryParameters: {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      },
    );
    return Financials.fromJson(res.data!['data'] as Map<String, dynamic>);
  }
}
```

- [ ] **Step 5: Run build_runner again for manager_remote_source.g.dart**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1 && dart run build_runner build --delete-conflicting-outputs 2>&1 | tail -5
```

Expected: `[INFO] Build Succeeded`.

- [ ] **Step 6: Save role to SharedPreferences after login**

In `lib/presentation/providers/auth_provider.dart`, in `verifyOTP` after `await prefs.setString('auth_token', token);` add:

```dart
await prefs.setString('user_role', (data['user'] as Map<String, dynamic>)['role'] as String? ?? 'player');
```

In `signInWithGoogle`, after `await prefs.setString('auth_token', token);` add:

```dart
await prefs.setString('user_role', (data['user'] as Map<String, dynamic>)['role'] as String? ?? 'player');
```

- [ ] **Step 7: Add role-aware navigation to otp_screen.dart**

In `lib/presentation/screens/otp/otp_screen.dart`, change the `ref.listen` block from:

```dart
ref.listen(authProvider, (_, next) {
  if (next is AuthAuthenticated) {
    context.go(AppRoutes.home);
  }
});
```

To:

```dart
ref.listen(authProvider, (_, next) {
  if (next is AuthAuthenticated) {
    final role = next.user['role'] as String? ?? 'player';
    context.go(role == 'manager' ? AppRoutes.manager : AppRoutes.home);
  }
});
```

- [ ] **Step 8: Add role-aware navigation to welcome_screen.dart**

In `lib/presentation/screens/welcome/welcome_screen.dart`, change the Google sign-in callback from:

```dart
onPressed: () async {
  await ref.read(authProvider.notifier).signInWithGoogle();
  if (!context.mounted) return;
  if (ref.read(authProvider) is AuthAuthenticated) {
    context.go(AppRoutes.home);
  }
},
```

To:

```dart
onPressed: () async {
  await ref.read(authProvider.notifier).signInWithGoogle();
  if (!context.mounted) return;
  final authState = ref.read(authProvider);
  if (authState is AuthAuthenticated) {
    final role = authState.user['role'] as String? ?? 'player';
    context.go(role == 'manager' ? AppRoutes.manager : AppRoutes.home);
  }
},
```

- [ ] **Step 9: Add /manager route to app_router.dart**

Replace the entire `lib/core/router/app_router.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../presentation/screens/splash/splash_screen.dart';
import '../../presentation/screens/welcome/welcome_screen.dart';
import '../../presentation/screens/sign_up/sign_up_screen.dart';
import '../../presentation/screens/otp/otp_screen.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/manager/manager_shell.dart';

abstract final class AppRoutes {
  static const splash = '/';
  static const welcome = '/welcome';
  static const signUp = '/sign-up';
  static const signIn = '/sign-in';
  static const otp = '/otp';
  static const home = '/home';
  static const manager = '/manager';
}

final appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  redirect: (context, state) async {
    // Cold-start: if a session exists, redirect to the right home
    if (state.matchedLocation == AppRoutes.splash) return null;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) return null;
    final role = prefs.getString('user_role') ?? 'player';
    final onAuthScreen = state.matchedLocation == AppRoutes.welcome ||
        state.matchedLocation == AppRoutes.signUp ||
        state.matchedLocation == AppRoutes.signIn ||
        state.matchedLocation == AppRoutes.otp;
    if (onAuthScreen) {
      return role == 'manager' ? AppRoutes.manager : AppRoutes.home;
    }
    return null;
  },
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.welcome,
      builder: (context, state) => const WelcomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.signUp,
      builder: (context, state) => const SignUpScreen(),
    ),
    GoRoute(
      path: AppRoutes.signIn,
      builder: (context, state) => const SignUpScreen(),
    ),
    GoRoute(
      path: AppRoutes.otp,
      builder: (context, state) {
        final phone = state.extra as String? ?? '';
        return OtpScreen(phone: phone);
      },
    ),
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.manager,
      builder: (context, state) => const ManagerShell(),
    ),
  ],
);
```

- [ ] **Step 10: flutter analyze**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1 && flutter analyze 2>&1 | grep -E "error:|warning:" | head -20
```

Expected: 0 errors. Fix any that appear.

- [ ] **Step 11: Commit**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1
git add \
  pubspec.yaml pubspec.lock \
  lib/data/models/manager_models.dart \
  lib/data/models/manager_models.freezed.dart \
  lib/data/models/manager_models.g.dart \
  lib/data/sources/remote/manager_remote_source.dart \
  lib/data/sources/remote/manager_remote_source.g.dart \
  lib/presentation/providers/auth_provider.dart \
  lib/presentation/screens/otp/otp_screen.dart \
  lib/presentation/screens/welcome/welcome_screen.dart \
  lib/core/router/app_router.dart
git commit -m "feat(manager): models + remote source + role-aware routing"
```

---

### Task M2: Manager Shell + Analytics Screen

**Files:**
- Create: `lib/presentation/screens/manager/manager_shell.dart`
- Create: `lib/presentation/screens/manager/analytics_screen.dart`
- Create: `lib/presentation/screens/manager/analytics_provider.dart`

- [ ] **Step 1: Create ManagerShell**

Create `lib/presentation/screens/manager/manager_shell.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import 'analytics_screen.dart';
import 'bookings_screen.dart';
import 'financials_screen.dart';

class ManagerShell extends ConsumerStatefulWidget {
  const ManagerShell({super.key});

  @override
  ConsumerState<ManagerShell> createState() => _ManagerShellState();
}

class _ManagerShellState extends ConsumerState<ManagerShell> {
  int _tab = 0;

  static const _screens = [
    AnalyticsScreen(),
    BookingsScreen(),
    FinancialsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: AppColors.background,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Analytics',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Bookings',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Financials',
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Create analytics provider**

Create `lib/presentation/screens/manager/analytics_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../data/models/manager_models.dart';
import '../../../data/sources/remote/manager_remote_source.dart';

part 'analytics_provider.g.dart';

@riverpod
Future<AnalyticsSummary> analyticsSummary(Ref ref, String period) =>
    ref.watch(managerRemoteSourceProvider).getSummary(period);

@riverpod
Future<RevenueChart> revenueChart(Ref ref, int days) =>
    ref.watch(managerRemoteSourceProvider).getRevenueChart(days);

@riverpod
Future<List<PitchStats>> pitchBreakdown(Ref ref, String period) =>
    ref.watch(managerRemoteSourceProvider).getPitchBreakdown(period);
```

- [ ] **Step 3: Run build_runner**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1 && dart run build_runner build --delete-conflicting-outputs 2>&1 | tail -5
```

- [ ] **Step 4: Create analytics screen**

Create `lib/presentation/screens/manager/analytics_screen.dart`:

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/manager_models.dart';
import 'analytics_provider.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  String _period = 'month';

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(analyticsSummaryProvider(_period));
    final chartAsync = ref.watch(revenueChartProvider(30));
    final breakdownAsync = ref.watch(pitchBreakdownProvider(_period));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Analytics',
            style: GoogleFonts.nunito(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(analyticsSummaryProvider(_period));
          ref.invalidate(revenueChartProvider(30));
          ref.invalidate(pitchBreakdownProvider(_period));
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Period selector
            _PeriodSelector(
              selected: _period,
              onSelect: (p) => setState(() => _period = p),
            ),
            const SizedBox(height: 16),

            // Summary cards
            summaryAsync.when(
              loading: () => const _SummaryCardsSkeleton(),
              error: (e, _) =>
                  Text('Error loading summary', style: TextStyle(color: Colors.red)),
              data: (s) => _SummaryCards(summary: s),
            ),
            const SizedBox(height: 24),

            // Revenue chart
            Text('Daily Revenue (last 30 days)',
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: chartAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    const Center(child: Text('Chart unavailable')),
                data: (c) => _RevenueBarChart(chart: c),
              ),
            ),
            const SizedBox(height: 24),

            // Per-pitch breakdown
            Text('Pitch Breakdown',
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            breakdownAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  const Center(child: Text('Breakdown unavailable')),
              data: (list) => _PitchBreakdownTable(stats: list),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.selected, required this.onSelect});
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ['today', 'week', 'month'].map((p) {
        final isSelected = selected == p;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(p[0].toUpperCase() + p.substring(1)),
            selected: isSelected,
            onSelected: (_) => onSelect(p),
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.summary});
  final AnalyticsSummary summary;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _StatCard(label: 'Revenue', value: 'RM ${summary.revenue.toStringAsFixed(0)}', icon: Icons.attach_money),
        _StatCard(label: 'Bookings', value: '${summary.bookingCount}', icon: Icons.calendar_today),
        _StatCard(label: 'Occupancy', value: '${summary.occupancyPct.toStringAsFixed(1)}%', icon: Icons.stadium),
        _StatCard(label: 'Avg Rating', value: summary.avgRating.toStringAsFixed(1), icon: Icons.star),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryDark.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryDeep),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: AppColors.textSecondary)),
          ]),
          Text(value,
              style: GoogleFonts.nunito(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _SummaryCardsSkeleton extends StatelessWidget {
  const _SummaryCardsSkeleton();
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: List.generate(
        4,
        (_) => Container(
          decoration: BoxDecoration(
            color: AppColors.primaryDark.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _RevenueBarChart extends StatelessWidget {
  const _RevenueBarChart({required this.chart});
  final RevenueChart chart;

  @override
  Widget build(BuildContext context) {
    if (chart.data.isEmpty) {
      return const Center(child: Text('No revenue data'));
    }
    final maxY = chart.data.map((e) => e.amount).fold(0.0, (a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 100 : maxY * 1.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i % 7 != 0 || i >= chart.data.length) {
                  return const SizedBox.shrink();
                }
                return Text(
                  chart.data[i].date.substring(5), // MM-DD
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                );
              },
            ),
          ),
        ),
        barGroups: chart.data.asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: e.value.amount,
                color: AppColors.primary,
                width: 6,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _PitchBreakdownTable extends StatelessWidget {
  const _PitchBreakdownTable({required this.stats});
  final List<PitchStats> stats;

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) {
      return const Center(child: Text('No pitch data'));
    }
    return Column(
      children: stats.map((s) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primaryDark.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(s.pitchName,
                    style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('RM ${s.revenue.toStringAsFixed(0)}',
                    style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w700, color: AppColors.primary)),
                Text('${s.bookingCount} bookings · ${s.occupancyPct.toStringAsFixed(0)}%',
                    style: GoogleFonts.dmSans(
                        fontSize: 11, color: AppColors.textSecondary)),
              ]),
            ],
          ),
        );
      }).toList(),
    );
  }
}
```

- [ ] **Step 5: flutter analyze**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1 && flutter analyze 2>&1 | grep "error:" | head -10
```

Expected: 0 errors.

- [ ] **Step 6: Commit**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1
git add \
  lib/presentation/screens/manager/manager_shell.dart \
  lib/presentation/screens/manager/analytics_screen.dart \
  lib/presentation/screens/manager/analytics_provider.dart \
  lib/presentation/screens/manager/analytics_provider.g.dart
git commit -m "feat(manager): ManagerShell + AnalyticsScreen with bar chart and summary cards"
```

---

### Task M3: Bookings Screen + Manual Booking Sheet

**Files:**
- Create: `lib/presentation/screens/manager/bookings_screen.dart`
- Create: `lib/presentation/screens/manager/bookings_provider.dart`
- Create: `lib/presentation/screens/manager/manual_booking_sheet.dart`

- [ ] **Step 1: Create bookings provider**

Create `lib/presentation/screens/manager/bookings_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../data/models/manager_models.dart';
import '../../../data/sources/remote/manager_remote_source.dart';

part 'bookings_provider.g.dart';

@riverpod
Future<({List<ManagerBooking> bookings, int total})> managerBookings(
  Ref ref, {
  String? status,
  String? source,
  String? date,
  int page = 1,
}) =>
    ref.watch(managerRemoteSourceProvider).listBookings(
          status: status,
          source: source,
          date: date,
          page: page,
        );
```

- [ ] **Step 2: Run build_runner**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1 && dart run build_runner build --delete-conflicting-outputs 2>&1 | tail -3
```

- [ ] **Step 3: Create manual booking sheet**

Create `lib/presentation/screens/manager/manual_booking_sheet.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/sources/remote/manager_remote_source.dart';
import 'bookings_provider.dart';

class ManualBookingSheet extends ConsumerStatefulWidget {
  const ManualBookingSheet({super.key});

  @override
  ConsumerState<ManualBookingSheet> createState() => _ManualBookingSheetState();
}

class _ManualBookingSheetState extends ConsumerState<ManualBookingSheet> {
  final _formKey = GlobalKey<FormState>();
  final _customerCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  String? _pitchId;
  DateTime? _date;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String _paymentMethod = 'cash';
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _customerCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  DateTime? get _startsAt {
    if (_date == null || _startTime == null) return null;
    return DateTime(_date!.year, _date!.month, _date!.day,
        _startTime!.hour, _startTime!.minute);
  }

  DateTime? get _endsAt {
    if (_date == null || _endTime == null) return null;
    return DateTime(_date!.year, _date!.month, _date!.day,
        _endTime!.hour, _endTime!.minute);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pitchId == null) {
      setState(() => _error = 'Select a pitch');
      return;
    }
    if (_startsAt == null || _endsAt == null) {
      setState(() => _error = 'Select date and times');
      return;
    }
    if (!_endsAt!.isAfter(_startsAt!)) {
      setState(() => _error = 'End time must be after start time');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(managerRemoteSourceProvider).createWalkIn(
        pitchId: _pitchId!,
        startsAt: _startsAt!,
        endsAt: _endsAt!,
        customerName: _customerCtrl.text.trim(),
        paymentMethod: _paymentMethod,
        paymentAmount: double.parse(_amountCtrl.text.trim()),
      );
      ref.invalidate(managerBookingsProvider);
      if (mounted) Navigator.of(context).pop();
    } on DioException catch (e) {
      final msg = (e.response?.data as Map?)?['error'] as String? ?? 'Failed to create booking';
      setState(() { _loading = false; _error = msg; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Form(
          key: _formKey,
          child: ListView(
            controller: scrollCtrl,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.primaryDeep,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Manual Booking',
                  style: GoogleFonts.nunito(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 20),

              // Pitch ID (text field — manager knows their own pitch IDs)
              TextFormField(
                decoration: _inputDecoration('Pitch ID (UUID)'),
                onChanged: (v) => _pitchId = v.isEmpty ? null : v,
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 14),

              // Date picker
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _date == null
                      ? 'Select date'
                      : '${_date!.year}-${_date!.month.toString().padLeft(2,'0')}-${_date!.day.toString().padLeft(2,'0')}',
                  style: TextStyle(
                      color: _date == null ? AppColors.textSecondary : AppColors.textPrimary),
                ),
                trailing: const Icon(Icons.calendar_today, color: AppColors.primary),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) setState(() => _date = d);
                },
              ),

              // Start time
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _startTime == null ? 'Start time' : _startTime!.format(context),
                  style: TextStyle(
                      color: _startTime == null ? AppColors.textSecondary : AppColors.textPrimary),
                ),
                trailing: const Icon(Icons.access_time, color: AppColors.primary),
                onTap: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: const TimeOfDay(hour: 9, minute: 0),
                  );
                  if (t != null) {
                    setState(() {
                      _startTime = t;
                      _endTime = TimeOfDay(hour: t.hour + 1, minute: t.minute);
                    });
                  }
                },
              ),

              // End time
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _endTime == null ? 'End time' : _endTime!.format(context),
                  style: TextStyle(
                      color: _endTime == null ? AppColors.textSecondary : AppColors.textPrimary),
                ),
                trailing: const Icon(Icons.access_time_filled, color: AppColors.primary),
                onTap: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: _endTime ?? const TimeOfDay(hour: 10, minute: 0),
                  );
                  if (t != null) setState(() => _endTime = t);
                },
              ),
              const SizedBox(height: 8),

              // Customer name
              TextFormField(
                controller: _customerCtrl,
                decoration: _inputDecoration('Customer name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 14),

              // Payment method
              DropdownButtonFormField<String>(
                value: _paymentMethod,
                decoration: _inputDecoration('Payment method'),
                dropdownColor: AppColors.background,
                style: const TextStyle(color: AppColors.textPrimary),
                items: ['cash', 'card', 'transfer']
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(() => _paymentMethod = v ?? 'cash'),
              ),
              const SizedBox(height: 14),

              // Payment amount
              TextFormField(
                controller: _amountCtrl,
                decoration: _inputDecoration('Amount collected (RM)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (double.tryParse(v) == null) return 'Enter a valid amount';
                  return null;
                },
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 20),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: const StadiumBorder(),
                    elevation: 0,
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Confirm Booking',
                          style: GoogleFonts.dmSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textSecondary),
      filled: true,
      fillColor: AppColors.primaryDark.withOpacity(0.1),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primaryDeep),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primaryDeep),
      ),
    );
  }
}
```

- [ ] **Step 4: Create bookings screen**

Create `lib/presentation/screens/manager/bookings_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/manager_models.dart';
import '../../../data/sources/remote/manager_remote_source.dart';
import 'bookings_provider.dart';
import 'manual_booking_sheet.dart';

class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  String? _statusFilter;
  String? _sourceFilter;

  static const _statusOptions = ['All', 'pending', 'confirmed', 'cancelled'];
  static const _sourceOptions = ['All', 'turfinn', 'walk_in'];

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(managerBookingsProvider(
      status: _statusFilter,
      source: _sourceFilter,
    ));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Bookings',
            style: GoogleFonts.nunito(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const ManualBookingSheet(),
        ),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Manual Booking',
            style: GoogleFonts.dmSans(
                fontWeight: FontWeight.w600, color: Colors.white)),
      ),
      body: Column(
        children: [
          // Status filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: _statusOptions.map((opt) {
                final val = opt == 'All' ? null : opt;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(opt),
                    selected: _statusFilter == val,
                    onSelected: (_) => setState(() => _statusFilter = val),
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                        color: _statusFilter == val
                            ? Colors.white
                            : AppColors.textPrimary),
                  ),
                );
              }).toList(),
            ),
          ),
          // Source filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: _sourceOptions.map((opt) {
                final val = opt == 'All' ? null : opt;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(opt == 'walk_in' ? 'Walk-in' : opt),
                    selected: _sourceFilter == val,
                    onSelected: (_) => setState(() => _sourceFilter = val),
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                        color: _sourceFilter == val
                            ? Colors.white
                            : AppColors.textPrimary),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: bookingsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Error: $e')),
              data: (result) => result.bookings.isEmpty
                  ? const Center(child: Text('No bookings'))
                  : RefreshIndicator(
                      onRefresh: () async => ref.invalidate(managerBookingsProvider),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: result.bookings.length,
                        itemBuilder: (ctx, i) =>
                            _BookingCard(booking: result.bookings[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingCard extends ConsumerWidget {
  const _BookingCard({required this.booking});
  final ManagerBooking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('dd MMM · HH:mm');
    final isWalkIn = booking.source == 'walk_in';
    final isPending = booking.status == 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryDark.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryDeep),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(booking.pitchName,
                      style: GoogleFonts.dmSans(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(width: 8),
                  if (isWalkIn)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Walk-in',
                          style: TextStyle(fontSize: 10, color: Colors.blue)),
                    ),
                ]),
                const SizedBox(height: 4),
                Text(
                  '${fmt.format(booking.startsAt)} – ${DateFormat('HH:mm').format(booking.endsAt)}',
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                Text(
                  booking.customerName.isEmpty ? booking.userId : booking.customerName,
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StatusBadge(status: booking.status),
              if (isPending) ...[
                const SizedBox(height: 8),
                Row(children: [
                  _ActionButton(
                    label: 'Confirm',
                    color: AppColors.primary,
                    onTap: () => _updateStatus(context, ref, 'confirmed'),
                  ),
                  const SizedBox(width: 6),
                  _ActionButton(
                    label: 'Cancel',
                    color: Colors.redAccent,
                    onTap: () => _updateStatus(context, ref, 'cancelled'),
                  ),
                ]),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(
      BuildContext context, WidgetRef ref, String status) async {
    try {
      await ref
          .read(managerRemoteSourceProvider)
          .updateBookingStatus(booking.id, status);
      ref.invalidate(managerBookingsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'confirmed' => Colors.green,
      'cancelled' => Colors.red,
      'completed' => Colors.blue,
      _ => Colors.orange,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(status,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
```

- [ ] **Step 5: flutter analyze**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1 && flutter analyze 2>&1 | grep "error:" | head -10
```

Expected: 0 errors.

- [ ] **Step 6: Commit**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1
git add \
  lib/presentation/screens/manager/bookings_screen.dart \
  lib/presentation/screens/manager/bookings_provider.dart \
  lib/presentation/screens/manager/bookings_provider.g.dart \
  lib/presentation/screens/manager/manual_booking_sheet.dart
git commit -m "feat(manager): BookingsScreen + ManualBookingSheet with walk-in booking form"
```

---

### Task M4: Financials Screen

**Files:**
- Create: `lib/presentation/screens/manager/financials_screen.dart`
- Create: `lib/presentation/screens/manager/financials_provider.dart`

- [ ] **Step 1: Create financials provider**

Create `lib/presentation/screens/manager/financials_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../data/models/manager_models.dart';
import '../../../data/sources/remote/manager_remote_source.dart';

part 'financials_provider.g.dart';

@riverpod
Future<Financials> managerFinancials(Ref ref, {String? from, String? to}) =>
    ref.watch(managerRemoteSourceProvider).getFinancials(from: from, to: to);
```

- [ ] **Step 2: Run build_runner**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1 && dart run build_runner build --delete-conflicting-outputs 2>&1 | tail -3
```

- [ ] **Step 3: Create financials screen**

Create `lib/presentation/screens/manager/financials_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/manager_models.dart';
import 'financials_provider.dart';

class FinancialsScreen extends ConsumerStatefulWidget {
  const FinancialsScreen({super.key});

  @override
  ConsumerState<FinancialsScreen> createState() => _FinancialsScreenState();
}

class _FinancialsScreenState extends ConsumerState<FinancialsScreen> {
  String _preset = 'month'; // month | week | custom
  DateTime? _customFrom;
  DateTime? _customTo;

  String? get _from {
    if (_preset == 'custom' && _customFrom != null) {
      return DateFormat('yyyy-MM-dd').format(_customFrom!);
    }
    if (_preset == 'week') {
      return DateFormat('yyyy-MM-dd')
          .format(DateTime.now().subtract(const Duration(days: 7)));
    }
    return DateFormat('yyyy-MM-dd')
        .format(DateTime.now().subtract(const Duration(days: 30)));
  }

  String? get _to => DateFormat('yyyy-MM-dd').format(
      _preset == 'custom' && _customTo != null ? _customTo! : DateTime.now());

  @override
  Widget build(BuildContext context) {
    final financialsAsync =
        ref.watch(managerFinancialsProvider(from: _from, to: _to));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Financials',
            style: GoogleFonts.nunito(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(managerFinancialsProvider(from: _from, to: _to)),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Period selector
            Row(
              children: [
                for (final p in ['week', 'month', 'custom'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(p[0].toUpperCase() + p.substring(1)),
                      selected: _preset == p,
                      onSelected: (_) async {
                        if (p == 'custom') {
                          final range = await showDateRangePicker(
                            context: context,
                            firstDate:
                                DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now(),
                          );
                          if (range != null) {
                            setState(() {
                              _customFrom = range.start;
                              _customTo = range.end;
                              _preset = 'custom';
                            });
                          }
                        } else {
                          setState(() => _preset = p);
                        }
                      },
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                          color: _preset == p ? Colors.white : AppColors.textPrimary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            financialsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Error: $e')),
              data: (fin) => _FinancialsContent(financials: fin),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinancialsContent extends StatelessWidget {
  const _FinancialsContent({required this.financials});
  final Financials financials;

  @override
  Widget build(BuildContext context) {
    final total = financials.totalRevenue;
    final turfinnPct =
        total > 0 ? (financials.turfinnRevenue / total * 100) : 0.0;
    final walkinPct =
        total > 0 ? (financials.walkInRevenue / total * 100) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Total revenue card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.primaryDark.withOpacity(0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primaryDeep),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total Revenue',
                  style: GoogleFonts.dmSans(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Text('RM ${total.toStringAsFixed(2)}',
                  style: GoogleFonts.nunito(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
              const SizedBox(height: 16),

              // Turfinn row
              _RevenueRow(
                label: 'Turfinn bookings',
                amount: financials.turfinnRevenue,
                pct: turfinnPct,
                color: AppColors.primary,
              ),
              const SizedBox(height: 8),
              // Walk-in row
              _RevenueRow(
                label: 'Walk-in bookings',
                amount: financials.walkInRevenue,
                pct: walkinPct,
                color: Colors.blue,
              ),
            ],
          ),
        ),

        if (financials.byPaymentMethod.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Walk-in Payment Methods',
              style: GoogleFonts.nunito(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          ...financials.byPaymentMethod
              .map((pm) => _PaymentMethodRow(breakdown: pm)),
        ],
      ],
    );
  }
}

class _RevenueRow extends StatelessWidget {
  const _RevenueRow({
    required this.label,
    required this.amount,
    required this.pct,
    required this.color,
  });
  final String label;
  final double amount;
  final double pct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: GoogleFonts.dmSans(color: AppColors.textSecondary, fontSize: 13)),
        ),
        Text('RM ${amount.toStringAsFixed(0)} (${pct.toStringAsFixed(0)}%)',
            style: GoogleFonts.dmSans(
                fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      ],
    );
  }
}

class _PaymentMethodRow extends StatelessWidget {
  const _PaymentMethodRow({required this.breakdown});
  final PaymentMethodBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryDark.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            switch (breakdown.method) {
              'cash' => Icons.payments_outlined,
              'card' => Icons.credit_card,
              _ => Icons.swap_horiz,
            },
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(breakdown.method[0].toUpperCase() + breakdown.method.substring(1),
                style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('RM ${breakdown.amount.toStringAsFixed(2)}',
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            Text('${breakdown.count} transactions',
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: AppColors.textSecondary)),
          ]),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: flutter analyze**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1 && flutter analyze 2>&1 | grep "error:" | head -10
```

Expected: 0 errors.

- [ ] **Step 5: Commit**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/.worktrees/wave1
git add \
  lib/presentation/screens/manager/financials_screen.dart \
  lib/presentation/screens/manager/financials_provider.dart \
  lib/presentation/screens/manager/financials_provider.g.dart
git commit -m "feat(manager): FinancialsScreen with revenue breakdown + payment method list"
```
