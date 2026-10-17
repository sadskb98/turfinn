# Manager Enhanced Analytics, Financials & Campaigns Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the Turf Manager panel from basic stats to a professional SaaS dashboard with hourly heatmaps, customer insights, daily financial ledger, export-ready reports, and self-serve promo code management — making the turf manager panel a compelling standalone product for turf owners.

**Architecture:** Extends the existing `/api/v1/manager/*` route group with 8 new endpoints. New analytics queries use raw SQL on existing tables (no new migrations needed — all data already exists in `bookings`, `reviews`, `users`, `promo_codes`). Manager-scoped promo codes are stored in the existing `promo_codes` table with a new `owner_id` column. Flutter adds 3 new sidebar views to the existing `ManagePanelScreen`.

**Tech Stack:** Go 1.25 + Echo + GORM raw SQL; Flutter + Riverpod + `fl_chart` (already in pubspec) for charts; existing `PanelScaffold`, `StatCard`, `DataTableCard` widgets.

---

## Scope — Three Subsystems

| Subsystem | New Backend Endpoints | New Flutter Views | Description |
|---|---|---|---|
| Enhanced Analytics | 3 | 1 (replaces existing My Analytics) | Hourly heatmap, peak hours, customer insights, trends |
| Enhanced Financials | 2 | 1 (replaces existing My Financials) | Daily revenue ledger, per-pitch P&L, CSV export |
| Manager Campaigns | 3 | 1 (new sidebar item) | Self-serve promo codes scoped to manager's pitches |

---

## Parallel Execution Map

| Chain | Tasks | Dependencies |
|---|---|---|
| B — Backend | B1 → B2 → B3 → B4 | Sequential: migration → service → handler → router |
| F — Flutter | F1 → F2 → F3 → F4 | Sequential: remote source → analytics view → financials view → campaigns view |
| **B must complete before F starts** | F consumes API contracts defined in B | |

---

## File Map

**Backend — new files:**
- `backend/migrations/015_manager_promo_codes.sql` — add `owner_id` to promo_codes
- `backend/internal/application/service/manager_analytics_service.go` — enhanced analytics queries
- `backend/internal/application/service/manager_analytics_service_test.go` — unit tests
- `backend/internal/interfaces/dto/manager_enhanced_dto.go` — DTOs for new endpoints
- `backend/internal/interfaces/http/handler/manager_campaigns_handler.go` — promo code CRUD for managers

**Backend — modified files:**
- `backend/internal/interfaces/http/handler/manager_handler.go` — add 5 new handler methods
- `backend/internal/interfaces/http/router.go:115-122` — add new routes to manager group
- `backend/cmd/api/main.go` — wire new service + handler

**Flutter — modified files:**
- `lib/data/sources/remote/manage_remote_source.dart` — add 8 new API methods
- `lib/presentation/screens/manage/manage_panel_screen.dart` — add 3 sidebar items, replace analytics/financials views, add campaigns view

---

## Chain B: Backend

### Task B1: Migration — Manager-Scoped Promo Codes

**Files:**
- Create: `backend/migrations/015_manager_promo_codes.sql`

- [ ] **Step 1: Create migration**

Create `backend/migrations/015_manager_promo_codes.sql`:

```sql
-- Manager-scoped promo codes: allow managers to create promos for their own pitches
ALTER TABLE promo_codes
    ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id);

CREATE INDEX IF NOT EXISTS idx_promo_codes_owner ON promo_codes(owner_id);

COMMENT ON COLUMN promo_codes.owner_id IS 'NULL = platform promo (admin), non-NULL = manager-created promo';
```

- [ ] **Step 2: Verify migration syntax**

Run: `cd /Users/fin.com/Projects/brain-systems/turfinn/backend && grep -c "IF NOT EXISTS" migrations/015_manager_promo_codes.sql`
Expected: 2 (both statements use guards)

- [ ] **Step 3: Commit**

```bash
git add backend/migrations/015_manager_promo_codes.sql
git commit -m "feat(db): add owner_id to promo_codes for manager-scoped promos"
```

---

### Task B2: Enhanced Analytics DTOs

**Files:**
- Create: `backend/internal/interfaces/dto/manager_enhanced_dto.go`

- [ ] **Step 1: Write DTOs**

Create `backend/internal/interfaces/dto/manager_enhanced_dto.go`:

```go
package dto

// --- Enhanced Analytics ---

// HourlyBookingCount represents booking volume for a specific hour.
type HourlyBookingCount struct {
	DayOfWeek int     `json:"day_of_week"` // 0=Sunday, 6=Saturday
	Hour      int     `json:"hour"`        // 0-23
	Count     int64   `json:"count"`
	Revenue   float64 `json:"revenue"`
}

// HeatmapResponse returns hourly booking data for building a 7x16 heatmap grid.
type HeatmapResponse struct {
	Period string               `json:"period"`
	Data   []HourlyBookingCount `json:"data"`
}

// PeakHoursResponse identifies the busiest and slowest hours.
type PeakHour struct {
	Hour    int     `json:"hour"`
	Count   int64   `json:"count"`
	Revenue float64 `json:"revenue"`
}

type PeakHoursResponse struct {
	Period    string     `json:"period"`
	Busiest   []PeakHour `json:"busiest"`  // top 5
	Slowest   []PeakHour `json:"slowest"`  // bottom 5
	AvgPerDay float64    `json:"avg_bookings_per_day"`
}

// CustomerInsightsResponse provides customer-level analytics.
type CustomerInsight struct {
	UserID       string  `json:"user_id"`
	Name         string  `json:"name"`
	Phone        string  `json:"phone"`
	BookingCount int64   `json:"booking_count"`
	TotalSpent   float64 `json:"total_spent"`
	LastVisit    string  `json:"last_visit"`
}

type CustomerInsightsResponse struct {
	Period          string            `json:"period"`
	TotalCustomers  int64             `json:"total_customers"`
	NewCustomers    int64             `json:"new_customers"`
	ReturningPct    float64           `json:"returning_pct"`
	TopCustomers    []CustomerInsight `json:"top_customers"` // top 10 by spend
}

// --- Enhanced Financials ---

// DailyLedgerEntry is one row in the daily financial ledger.
type DailyLedgerEntry struct {
	Date          string  `json:"date"`
	BookingCount  int64   `json:"booking_count"`
	TotalRevenue  float64 `json:"total_revenue"`
	AppRevenue    float64 `json:"app_revenue"`
	WalkInRevenue float64 `json:"walkin_revenue"`
	Commission    float64 `json:"commission"` // 5% of app revenue
}

// DailyLedgerResponse returns a daily financial breakdown.
type DailyLedgerResponse struct {
	From    string             `json:"from"`
	To      string             `json:"to"`
	Entries []DailyLedgerEntry `json:"entries"`
	Summary DailyLedgerEntry   `json:"summary"` // totals row
}

// PitchPnLEntry is per-pitch profit/loss for a period.
type PitchPnLEntry struct {
	PitchID      string  `json:"pitch_id"`
	PitchName    string  `json:"pitch_name"`
	Revenue      float64 `json:"revenue"`
	BookingCount int64   `json:"booking_count"`
	BookedHours  float64 `json:"booked_hours"`
	OccupancyPct float64 `json:"occupancy_pct"`
	Commission   float64 `json:"commission"`
	NetRevenue   float64 `json:"net_revenue"` // revenue - commission
}

// --- Manager Promo Codes ---

// ManagerPromoResponse is the manager-facing promo code view.
type ManagerPromoResponse struct {
	ID            string  `json:"id"`
	Code          string  `json:"code"`
	DiscountType  string  `json:"discount_type"`
	DiscountValue float64 `json:"discount_value"`
	MaxUses       int     `json:"max_uses"`
	UsedCount     int     `json:"used_count"`
	ValidFrom     string  `json:"valid_from"`
	ValidTo       string  `json:"valid_to"`
	IsActive      bool    `json:"is_active"`
	CreatedAt     string  `json:"created_at"`
}

// CreateManagerPromoRequest is the input for creating a manager promo code.
type CreateManagerPromoRequest struct {
	Code          string  `json:"code" validate:"required,min=3,max=20"`
	DiscountType  string  `json:"discount_type" validate:"required,oneof=percent fixed"`
	DiscountValue float64 `json:"discount_value" validate:"required,gt=0"`
	MaxUses       int     `json:"max_uses" validate:"required,min=1,max=10000"`
	ValidFrom     string  `json:"valid_from" validate:"required"`
	ValidTo       string  `json:"valid_to" validate:"required"`
}
```

- [ ] **Step 2: Verify build**

Run: `cd /Users/fin.com/Projects/brain-systems/turfinn/backend && go build ./...`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add backend/internal/interfaces/dto/manager_enhanced_dto.go
git commit -m "feat(dto): add enhanced analytics, financials, and campaign DTOs for manager"
```

---

### Task B3: Enhanced Analytics Service

**Files:**
- Create: `backend/internal/application/service/manager_analytics_service.go`
- Create: `backend/internal/application/service/manager_analytics_service_test.go`

- [ ] **Step 1: Write test for HeatmapResponse structure**

Create `backend/internal/application/service/manager_analytics_service_test.go`:

```go
package service

import (
	"testing"

	"github.com/turfinn/backend/internal/interfaces/dto"
)

func TestFillHeatmapGrid(t *testing.T) {
	// Sparse input: only a few cells have data
	raw := []dto.HourlyBookingCount{
		{DayOfWeek: 1, Hour: 18, Count: 5, Revenue: 2500},
		{DayOfWeek: 5, Hour: 20, Count: 8, Revenue: 4000},
	}
	grid := FillHeatmapGrid(raw)

	// Should produce 7 days * 16 hours (08:00-23:00) = 112 cells
	if len(grid) != 112 {
		t.Fatalf("expected 112 cells, got %d", len(grid))
	}

	// Check that our sparse data is in the right place
	found := 0
	for _, cell := range grid {
		if cell.DayOfWeek == 1 && cell.Hour == 18 {
			if cell.Count != 5 {
				t.Errorf("Monday 18:00 count = %d, want 5", cell.Count)
			}
			found++
		}
		if cell.DayOfWeek == 5 && cell.Hour == 20 {
			if cell.Count != 8 {
				t.Errorf("Friday 20:00 count = %d, want 8", cell.Count)
			}
			found++
		}
	}
	if found != 2 {
		t.Errorf("expected 2 populated cells, found %d", found)
	}
}

func TestTopAndBottom(t *testing.T) {
	hours := []dto.PeakHour{
		{Hour: 8, Count: 1, Revenue: 100},
		{Hour: 9, Count: 2, Revenue: 200},
		{Hour: 18, Count: 10, Revenue: 5000},
		{Hour: 19, Count: 12, Revenue: 6000},
		{Hour: 20, Count: 15, Revenue: 7500},
		{Hour: 21, Count: 14, Revenue: 7000},
		{Hour: 22, Count: 8, Revenue: 4000},
		{Hour: 10, Count: 3, Revenue: 300},
	}
	top, bottom := TopAndBottom(hours, 3)

	if len(top) != 3 {
		t.Fatalf("expected 3 top, got %d", len(top))
	}
	if top[0].Hour != 20 {
		t.Errorf("busiest hour = %d, want 20", top[0].Hour)
	}

	if len(bottom) != 3 {
		t.Fatalf("expected 3 bottom, got %d", len(bottom))
	}
	if bottom[0].Hour != 8 {
		t.Errorf("slowest hour = %d, want 8", bottom[0].Hour)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/fin.com/Projects/brain-systems/turfinn/backend && go test ./internal/application/service/ -run TestFillHeatmapGrid -v`
Expected: FAIL — `FillHeatmapGrid` undefined

- [ ] **Step 3: Write the service**

Create `backend/internal/application/service/manager_analytics_service.go`:

```go
package service

import (
	"context"
	"sort"
	"time"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/interfaces/dto"
	"gorm.io/gorm"
)

type ManagerAnalyticsService struct {
	db *gorm.DB
}

func NewManagerAnalyticsService(db *gorm.DB) *ManagerAnalyticsService {
	return &ManagerAnalyticsService{db: db}
}

// FillHeatmapGrid takes sparse hourly data and fills a 7x16 grid (days 0-6, hours 8-23).
func FillHeatmapGrid(raw []dto.HourlyBookingCount) []dto.HourlyBookingCount {
	lookup := make(map[[2]int]dto.HourlyBookingCount, len(raw))
	for _, r := range raw {
		lookup[[2]int{r.DayOfWeek, r.Hour}] = r
	}
	grid := make([]dto.HourlyBookingCount, 0, 112)
	for day := 0; day < 7; day++ {
		for hour := 8; hour < 24; hour++ {
			key := [2]int{day, hour}
			if cell, ok := lookup[key]; ok {
				grid = append(grid, cell)
			} else {
				grid = append(grid, dto.HourlyBookingCount{DayOfWeek: day, Hour: hour})
			}
		}
	}
	return grid
}

// TopAndBottom returns the top-N busiest and bottom-N slowest hours by count.
func TopAndBottom(hours []dto.PeakHour, n int) (top, bottom []dto.PeakHour) {
	sorted := make([]dto.PeakHour, len(hours))
	copy(sorted, hours)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].Count > sorted[j].Count })
	if n > len(sorted) {
		n = len(sorted)
	}
	top = sorted[:n]
	// bottom = least bookings
	bottom = make([]dto.PeakHour, n)
	copy(bottom, sorted[len(sorted)-n:])
	sort.Slice(bottom, func(i, j int) bool { return bottom[i].Count < bottom[j].Count })
	return top, bottom
}

// GetHeatmap returns hourly booking counts across the operating window.
func (s *ManagerAnalyticsService) GetHeatmap(ctx context.Context, managerID uuid.UUID, period string) (dto.HeatmapResponse, error) {
	from, to := PeriodRange(period)

	var raw []dto.HourlyBookingCount
	if err := s.db.WithContext(ctx).Raw(`
		SELECT
			EXTRACT(DOW FROM b.starts_at)::int           AS day_of_week,
			EXTRACT(HOUR FROM b.starts_at)::int          AS hour,
			COUNT(*)                                      AS count,
			COALESCE(SUM(b.total_cost), 0)                AS revenue
		FROM bookings b
		JOIN pitches p ON b.pitch_id = p.id
		WHERE p.owner_id = ?
		  AND b.status IN ('confirmed','completed')
		  AND b.starts_at >= ?
		  AND b.starts_at < ?
		GROUP BY 1, 2
		ORDER BY 1, 2
	`, managerID, from, to).Scan(&raw).Error; err != nil {
		return dto.HeatmapResponse{}, err
	}

	return dto.HeatmapResponse{
		Period: period,
		Data:   FillHeatmapGrid(raw),
	}, nil
}

// GetPeakHours returns busiest/slowest hours and average bookings per day.
func (s *ManagerAnalyticsService) GetPeakHours(ctx context.Context, managerID uuid.UUID, period string) (dto.PeakHoursResponse, error) {
	from, to := PeriodRange(period)

	var hours []dto.PeakHour
	if err := s.db.WithContext(ctx).Raw(`
		SELECT
			EXTRACT(HOUR FROM b.starts_at)::int AS hour,
			COUNT(*)                             AS count,
			COALESCE(SUM(b.total_cost), 0)       AS revenue
		FROM bookings b
		JOIN pitches p ON b.pitch_id = p.id
		WHERE p.owner_id = ?
		  AND b.status IN ('confirmed','completed')
		  AND b.starts_at >= ?
		  AND b.starts_at < ?
		GROUP BY 1
		ORDER BY count DESC
	`, managerID, from, to).Scan(&hours).Error; err != nil {
		return dto.PeakHoursResponse{}, err
	}

	top, bottom := TopAndBottom(hours, 5)

	days := to.Sub(from).Hours() / 24
	var totalBookings int64
	for _, h := range hours {
		totalBookings += h.Count
	}
	avgPerDay := 0.0
	if days > 0 {
		avgPerDay = float64(totalBookings) / days
	}

	return dto.PeakHoursResponse{
		Period:    period,
		Busiest:   top,
		Slowest:   bottom,
		AvgPerDay: avgPerDay,
	}, nil
}

// GetCustomerInsights returns customer-level analytics for the manager's pitches.
func (s *ManagerAnalyticsService) GetCustomerInsights(ctx context.Context, managerID uuid.UUID, period string) (dto.CustomerInsightsResponse, error) {
	from, to := PeriodRange(period)

	// Total unique + new customers
	type countsRow struct {
		Total int64 `gorm:"column:total"`
		New   int64 `gorm:"column:new_count"`
	}
	var counts countsRow
	if err := s.db.WithContext(ctx).Raw(`
		SELECT
			COUNT(DISTINCT b.user_id)  AS total,
			COUNT(DISTINCT b.user_id) FILTER (
				WHERE NOT EXISTS (
					SELECT 1 FROM bookings b2
					JOIN pitches p2 ON b2.pitch_id = p2.id
					WHERE p2.owner_id = ?
					  AND b2.user_id = b.user_id
					  AND b2.starts_at < ?
					  AND b2.status IN ('confirmed','completed')
				)
			) AS new_count
		FROM bookings b
		JOIN pitches p ON b.pitch_id = p.id
		WHERE p.owner_id = ?
		  AND b.status IN ('confirmed','completed')
		  AND b.starts_at >= ?
		  AND b.starts_at < ?
	`, managerID, from, managerID, from, to).Scan(&counts).Error; err != nil {
		return dto.CustomerInsightsResponse{}, err
	}

	returningPct := 0.0
	if counts.Total > 0 {
		returningPct = float64(counts.Total-counts.New) / float64(counts.Total) * 100
	}

	// Top 10 customers by spend
	type customerRow struct {
		UserID       string  `gorm:"column:user_id"`
		Name         string  `gorm:"column:name"`
		Phone        string  `gorm:"column:phone"`
		BookingCount int64   `gorm:"column:booking_count"`
		TotalSpent   float64 `gorm:"column:total_spent"`
		LastVisit    string  `gorm:"column:last_visit"`
	}
	var customers []customerRow
	if err := s.db.WithContext(ctx).Raw(`
		SELECT
			u.id::text                                    AS user_id,
			COALESCE(u.name, '')                          AS name,
			COALESCE(u.phone, '')                         AS phone,
			COUNT(b.id)                                   AS booking_count,
			COALESCE(SUM(b.total_cost), 0)                AS total_spent,
			TO_CHAR(MAX(b.starts_at), 'YYYY-MM-DD')       AS last_visit
		FROM bookings b
		JOIN pitches p ON b.pitch_id = p.id
		JOIN users u ON b.user_id = u.id
		WHERE p.owner_id = ?
		  AND b.status IN ('confirmed','completed')
		  AND b.starts_at >= ?
		  AND b.starts_at < ?
		  AND b.source != 'walk_in'
		GROUP BY u.id, u.name, u.phone
		ORDER BY total_spent DESC
		LIMIT 10
	`, managerID, from, to).Scan(&customers).Error; err != nil {
		return dto.CustomerInsightsResponse{}, err
	}

	topCustomers := make([]dto.CustomerInsight, len(customers))
	for i, c := range customers {
		topCustomers[i] = dto.CustomerInsight{
			UserID:       c.UserID,
			Name:         c.Name,
			Phone:        c.Phone,
			BookingCount: c.BookingCount,
			TotalSpent:   c.TotalSpent,
			LastVisit:    c.LastVisit,
		}
	}

	return dto.CustomerInsightsResponse{
		Period:         period,
		TotalCustomers: counts.Total,
		NewCustomers:   counts.New,
		ReturningPct:   returningPct,
		TopCustomers:   topCustomers,
	}, nil
}

// GetDailyLedger returns daily financial breakdown.
func (s *ManagerAnalyticsService) GetDailyLedger(ctx context.Context, managerID uuid.UUID, from, to time.Time) (dto.DailyLedgerResponse, error) {
	type ledgerRow struct {
		Date          string  `gorm:"column:date"`
		BookingCount  int64   `gorm:"column:booking_count"`
		TotalRevenue  float64 `gorm:"column:total_revenue"`
		AppRevenue    float64 `gorm:"column:app_revenue"`
		WalkInRevenue float64 `gorm:"column:walkin_revenue"`
	}
	var rows []ledgerRow
	if err := s.db.WithContext(ctx).Raw(`
		SELECT
			TO_CHAR(DATE(b.starts_at), 'YYYY-MM-DD')                                    AS date,
			COUNT(*)                                                                      AS booking_count,
			COALESCE(SUM(b.total_cost), 0)                                                AS total_revenue,
			COALESCE(SUM(CASE WHEN b.source = 'turfinn' THEN b.total_cost ELSE 0 END), 0) AS app_revenue,
			COALESCE(SUM(CASE WHEN b.source = 'walk_in' THEN b.total_cost ELSE 0 END), 0) AS walkin_revenue
		FROM bookings b
		JOIN pitches p ON b.pitch_id = p.id
		WHERE p.owner_id = ?
		  AND b.status IN ('confirmed','completed')
		  AND b.starts_at >= ?
		  AND b.starts_at < ?
		GROUP BY DATE(b.starts_at)
		ORDER BY date ASC
	`, managerID, from, to).Scan(&rows).Error; err != nil {
		return dto.DailyLedgerResponse{}, err
	}

	commissionRate := 0.05
	entries := make([]dto.DailyLedgerEntry, len(rows))
	var summary dto.DailyLedgerEntry
	for i, r := range rows {
		commission := r.AppRevenue * commissionRate
		entries[i] = dto.DailyLedgerEntry{
			Date:          r.Date,
			BookingCount:  r.BookingCount,
			TotalRevenue:  r.TotalRevenue,
			AppRevenue:    r.AppRevenue,
			WalkInRevenue: r.WalkInRevenue,
			Commission:    commission,
		}
		summary.BookingCount += r.BookingCount
		summary.TotalRevenue += r.TotalRevenue
		summary.AppRevenue += r.AppRevenue
		summary.WalkInRevenue += r.WalkInRevenue
		summary.Commission += commission
	}
	summary.Date = "TOTAL"

	return dto.DailyLedgerResponse{
		From:    from.Format("2006-01-02"),
		To:      to.Format("2006-01-02"),
		Entries: entries,
		Summary: summary,
	}, nil
}

// GetPitchPnL returns per-pitch profit/loss breakdown.
func (s *ManagerAnalyticsService) GetPitchPnL(ctx context.Context, managerID uuid.UUID, from, to time.Time) ([]dto.PitchPnLEntry, error) {
	days := to.Sub(from).Hours() / 24

	type pitchRow struct {
		PitchID      string  `gorm:"column:pitch_id"`
		PitchName    string  `gorm:"column:pitch_name"`
		Revenue      float64 `gorm:"column:revenue"`
		BookingCount int64   `gorm:"column:booking_count"`
		BookedHours  float64 `gorm:"column:booked_hours"`
		AppRevenue   float64 `gorm:"column:app_revenue"`
	}
	var rows []pitchRow
	if err := s.db.WithContext(ctx).Raw(`
		SELECT
			p.id::text                                                                     AS pitch_id,
			p.name                                                                         AS pitch_name,
			COALESCE(SUM(b.total_cost), 0)                                                 AS revenue,
			COUNT(b.id)                                                                    AS booking_count,
			COALESCE(SUM(EXTRACT(EPOCH FROM (b.ends_at - b.starts_at)) / 3600), 0)        AS booked_hours,
			COALESCE(SUM(CASE WHEN b.source = 'turfinn' THEN b.total_cost ELSE 0 END), 0) AS app_revenue
		FROM pitches p
		LEFT JOIN bookings b ON b.pitch_id = p.id
			AND b.status IN ('confirmed','completed')
			AND b.starts_at >= ?
			AND b.starts_at < ?
		WHERE p.owner_id = ?
		GROUP BY p.id, p.name
		ORDER BY revenue DESC
	`, from, to, managerID).Scan(&rows).Error; err != nil {
		return nil, err
	}

	commissionRate := 0.05
	entries := make([]dto.PitchPnLEntry, len(rows))
	for i, r := range rows {
		occupancy := 0.0
		if days > 0 {
			occupancy = r.BookedHours / (operatingHoursPerDay * days) * 100
		}
		commission := r.AppRevenue * commissionRate
		entries[i] = dto.PitchPnLEntry{
			PitchID:      r.PitchID,
			PitchName:    r.PitchName,
			Revenue:      r.Revenue,
			BookingCount: r.BookingCount,
			BookedHours:  r.BookedHours,
			OccupancyPct: occupancy,
			Commission:   commission,
			NetRevenue:   r.Revenue - commission,
		}
	}
	return entries, nil
}
```

- [ ] **Step 4: Run tests**

Run: `cd /Users/fin.com/Projects/brain-systems/turfinn/backend && go test ./internal/application/service/ -run "TestFillHeatmap|TestTopAndBottom" -v`
Expected: PASS

- [ ] **Step 5: Verify build**

Run: `cd /Users/fin.com/Projects/brain-systems/turfinn/backend && go build ./...`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add backend/internal/application/service/manager_analytics_service.go backend/internal/application/service/manager_analytics_service_test.go
git commit -m "feat(service): add enhanced analytics with heatmap, peak hours, customer insights, ledger"
```

---

### Task B4: Handler Methods + Router Wiring

**Files:**
- Modify: `backend/internal/interfaces/http/handler/manager_handler.go` — add 5 new methods
- Create: `backend/internal/interfaces/http/handler/manager_campaigns_handler.go`
- Modify: `backend/internal/interfaces/http/router.go:115-122`
- Modify: `backend/cmd/api/main.go`

- [ ] **Step 1: Add enhanced analytics handlers to manager_handler.go**

Add these methods to the bottom of `backend/internal/interfaces/http/handler/manager_handler.go`, and update the struct to include the new service:

First, update the struct and constructor at the top of the file. Replace:

```go
type ManagerHandler struct {
	svc *service.AnalyticsService
}

func NewManagerHandler(svc *service.AnalyticsService) *ManagerHandler {
	return &ManagerHandler{svc: svc}
}
```

With:

```go
type ManagerHandler struct {
	svc     *service.AnalyticsService
	enhanced *service.ManagerAnalyticsService
}

func NewManagerHandler(svc *service.AnalyticsService, enhanced *service.ManagerAnalyticsService) *ManagerHandler {
	return &ManagerHandler{svc: svc, enhanced: enhanced}
}
```

Then add these handler methods at the end of the file (before the `parseInt` function):

```go
// GET /api/v1/manager/analytics/heatmap?period=month
func (h *ManagerHandler) GetHeatmap(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}
	period := c.QueryParam("period")
	if period == "" {
		period = "month"
	}
	heatmap, err := h.enhanced.GetHeatmap(c.Request().Context(), managerID, period)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, heatmap)
}

// GET /api/v1/manager/analytics/peak-hours?period=month
func (h *ManagerHandler) GetPeakHours(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}
	period := c.QueryParam("period")
	if period == "" {
		period = "month"
	}
	peaks, err := h.enhanced.GetPeakHours(c.Request().Context(), managerID, period)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, peaks)
}

// GET /api/v1/manager/analytics/customers?period=month
func (h *ManagerHandler) GetCustomerInsights(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}
	period := c.QueryParam("period")
	if period == "" {
		period = "month"
	}
	insights, err := h.enhanced.GetCustomerInsights(c.Request().Context(), managerID, period)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, insights)
}

// GET /api/v1/manager/financials/ledger?from=2026-01-01&to=2026-12-31
func (h *ManagerHandler) GetDailyLedger(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}
	from := time.Now().UTC().AddDate(0, -1, 0)
	to := time.Now().UTC()
	if f := c.QueryParam("from"); f != "" {
		if t, err := time.Parse("2006-01-02", f); err == nil {
			from = t
		}
	}
	if t := c.QueryParam("to"); t != "" {
		if parsed, err := time.Parse("2006-01-02", t); err == nil {
			to = parsed.Add(24 * time.Hour)
		}
	}
	ledger, err := h.enhanced.GetDailyLedger(c.Request().Context(), managerID, from, to)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, ledger)
}

// GET /api/v1/manager/financials/pitch-pnl?from=2026-01-01&to=2026-12-31
func (h *ManagerHandler) GetPitchPnL(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}
	from := time.Now().UTC().AddDate(0, -1, 0)
	to := time.Now().UTC()
	if f := c.QueryParam("from"); f != "" {
		if t, err := time.Parse("2006-01-02", f); err == nil {
			from = t
		}
	}
	if t := c.QueryParam("to"); t != "" {
		if parsed, err := time.Parse("2006-01-02", t); err == nil {
			to = parsed.Add(24 * time.Hour)
		}
	}
	entries, err := h.enhanced.GetPitchPnL(c.Request().Context(), managerID, from, to)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, entries)
}
```

- [ ] **Step 2: Create manager campaigns handler**

Create `backend/internal/interfaces/http/handler/manager_campaigns_handler.go`:

```go
package handler

import (
	"html"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/interfaces/dto"
	"github.com/turfinn/backend/internal/pkg/response"
	"gorm.io/gorm"
)

type ManagerCampaignsHandler struct {
	db *gorm.DB
}

func NewManagerCampaignsHandler(db *gorm.DB) *ManagerCampaignsHandler {
	return &ManagerCampaignsHandler{db: db}
}

// GET /api/v1/manager/promos
func (h *ManagerCampaignsHandler) ListPromos(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}

	var promos []entity.PromoCode
	if err := h.db.WithContext(c.Request().Context()).
		Where("owner_id = ?", managerID).
		Order("created_at DESC").
		Find(&promos).Error; err != nil {
		return response.InternalError(c)
	}

	out := make([]dto.ManagerPromoResponse, len(promos))
	for i, p := range promos {
		out[i] = dto.ManagerPromoResponse{
			ID:            p.ID.String(),
			Code:          p.Code,
			DiscountType:  p.DiscountType,
			DiscountValue: p.DiscountValue,
			MaxUses:       p.MaxUses,
			UsedCount:     p.UsedCount,
			ValidFrom:     p.ValidFrom.Format("2006-01-02"),
			ValidTo:       p.ValidTo.Format("2006-01-02"),
			IsActive:      p.IsActive,
			CreatedAt:     p.CreatedAt.Format("2006-01-02T15:04:05Z"),
		}
	}
	return response.OK(c, out)
}

// POST /api/v1/manager/promos
func (h *ManagerCampaignsHandler) CreatePromo(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}

	var req dto.CreateManagerPromoRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	validFrom, err := time.Parse("2006-01-02", req.ValidFrom)
	if err != nil {
		return response.BadRequest(c, "invalid valid_from date")
	}
	validTo, err := time.Parse("2006-01-02", req.ValidTo)
	if err != nil {
		return response.BadRequest(c, "invalid valid_to date")
	}
	if validTo.Before(validFrom) {
		return response.BadRequest(c, "valid_to must be after valid_from")
	}

	code := html.EscapeString(strings.ToUpper(strings.TrimSpace(req.Code)))

	// Check uniqueness
	var count int64
	h.db.WithContext(c.Request().Context()).
		Model(&entity.PromoCode{}).
		Where("UPPER(code) = ?", code).
		Count(&count)
	if count > 0 {
		return response.Conflict(c, "promo code already exists")
	}

	// Get manager's pitch IDs to scope the promo
	var pitchIDs []string
	h.db.WithContext(c.Request().Context()).
		Model(&entity.Pitch{}).
		Where("owner_id = ?", managerID).
		Pluck("id::text", &pitchIDs)

	promo := entity.PromoCode{
		ID:            uuid.New(),
		Code:          code,
		DiscountType:  req.DiscountType,
		DiscountValue: req.DiscountValue,
		MaxUses:       req.MaxUses,
		PerUserLimit:  1,
		PitchIDs:      strings.Join(pitchIDs, ","),
		ValidFrom:     validFrom,
		ValidTo:       validTo,
		IsActive:      true,
		OwnerID:       &managerID,
	}
	if err := h.db.WithContext(c.Request().Context()).Create(&promo).Error; err != nil {
		return response.InternalError(c)
	}

	return response.Created(c, dto.ManagerPromoResponse{
		ID:            promo.ID.String(),
		Code:          promo.Code,
		DiscountType:  promo.DiscountType,
		DiscountValue: promo.DiscountValue,
		MaxUses:       promo.MaxUses,
		UsedCount:     0,
		ValidFrom:     promo.ValidFrom.Format("2006-01-02"),
		ValidTo:       promo.ValidTo.Format("2006-01-02"),
		IsActive:      true,
		CreatedAt:     promo.CreatedAt.Format("2006-01-02T15:04:05Z"),
	})
}

// PUT /api/v1/manager/promos/:id/deactivate
func (h *ManagerCampaignsHandler) DeactivatePromo(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}

	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid promo id")
	}

	result := h.db.WithContext(c.Request().Context()).
		Model(&entity.PromoCode{}).
		Where("id = ? AND owner_id = ?", id, managerID).
		Update("is_active", false)
	if result.Error != nil {
		return response.InternalError(c)
	}
	if result.RowsAffected == 0 {
		return response.NotFound(c, "promo not found or not owned by you")
	}
	return response.OK(c, map[string]string{"message": "promo deactivated"})
}
```

- [ ] **Step 3: Update PromoCode entity to include OwnerID**

Check the entity file and add `OwnerID` field. Open `backend/internal/domain/entity/` and find the PromoCode struct. Add:

```go
OwnerID *uuid.UUID `json:"owner_id,omitempty" gorm:"type:uuid;index"`
```

to the `PromoCode` struct (after the existing fields).

- [ ] **Step 4: Add routes to router.go**

In `backend/internal/interfaces/http/router.go`, find the manager group (around line 115-122) and add new routes after the existing ones:

```go
	// Enhanced analytics
	manager.GET("/analytics/heatmap", managerH.GetHeatmap)
	manager.GET("/analytics/peak-hours", managerH.GetPeakHours)
	manager.GET("/analytics/customers", managerH.GetCustomerInsights)

	// Enhanced financials
	manager.GET("/financials/ledger", managerH.GetDailyLedger)
	manager.GET("/financials/pitch-pnl", managerH.GetPitchPnL)

	// Manager campaigns (promo codes)
	manager.GET("/promos", campaignsH.ListPromos)
	manager.POST("/promos", campaignsH.CreatePromo)
	manager.PUT("/promos/:id/deactivate", campaignsH.DeactivatePromo)
```

Also update the `NewRouter` function signature to accept the new handler:

```go
campaignsH *handler.ManagerCampaignsHandler,
```

- [ ] **Step 5: Wire in main.go**

In `backend/cmd/api/main.go`, add:

```go
managerAnalyticsSvc := service.NewManagerAnalyticsService(db)
campaignsH := handler.NewManagerCampaignsHandler(db)
```

And update the `NewManagerHandler` call to pass the new service:

```go
managerH := handler.NewManagerHandler(analyticsSvc, managerAnalyticsSvc)
```

And pass `campaignsH` to `NewRouter`.

- [ ] **Step 6: Verify build**

Run: `cd /Users/fin.com/Projects/brain-systems/turfinn/backend && go build ./...`
Expected: Build succeeds

- [ ] **Step 7: Commit**

```bash
git add backend/internal/interfaces/http/handler/manager_handler.go \
       backend/internal/interfaces/http/handler/manager_campaigns_handler.go \
       backend/internal/interfaces/http/router.go \
       backend/cmd/api/main.go \
       backend/internal/domain/entity/
git commit -m "feat(api): add enhanced analytics, financials, and campaigns endpoints for manager"
```

---

## Chain F: Flutter Frontend

### Task F1: Remote Source — New API Methods

**Files:**
- Modify: `lib/data/sources/remote/manage_remote_source.dart`

- [ ] **Step 1: Add 8 new methods to ManageRemoteSource**

Add these methods to the `ManageRemoteSource` class in `lib/data/sources/remote/manage_remote_source.dart`, after the existing `getManagerFinancials` method:

```dart
  // ── Enhanced Analytics ──────────────────────────────────────────────
  Future<Map<String, dynamic>> getManagerHeatmap({String period = 'month'}) async {
    final resp = await _dio.get('/manager/analytics/heatmap', queryParameters: {'period': period});
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getManagerPeakHours({String period = 'month'}) async {
    final resp = await _dio.get('/manager/analytics/peak-hours', queryParameters: {'period': period});
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getManagerCustomerInsights({String period = 'month'}) async {
    final resp = await _dio.get('/manager/analytics/customers', queryParameters: {'period': period});
    return resp.data['data'] as Map<String, dynamic>;
  }

  // ── Enhanced Financials ─────────────────────────────────────────────
  Future<Map<String, dynamic>> getManagerDailyLedger({String? from, String? to}) async {
    final resp = await _dio.get('/manager/financials/ledger', queryParameters: {
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    });
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> getManagerPitchPnL({String? from, String? to}) async {
    final resp = await _dio.get('/manager/financials/pitch-pnl', queryParameters: {
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    });
    return resp.data['data'] as List<dynamic>;
  }

  // ── Manager Campaigns (Promo Codes) ─────────────────────────────────
  Future<List<dynamic>> listManagerPromos() async {
    final resp = await _dio.get('/manager/promos');
    return resp.data['data'] as List<dynamic>;
  }

  Future<void> createManagerPromo(Map<String, dynamic> data) async {
    await _dio.post('/manager/promos', data: data);
  }

  Future<void> deactivateManagerPromo(String id) async {
    await _dio.put('/manager/promos/$id/deactivate');
  }
```

- [ ] **Step 2: Verify Flutter analyze**

Run: `cd /Users/fin.com/Projects/brain-systems/turfinn && flutter analyze lib/data/sources/remote/manage_remote_source.dart`
Expected: No issues

- [ ] **Step 3: Commit**

```bash
git add lib/data/sources/remote/manage_remote_source.dart
git commit -m "feat(remote): add enhanced analytics, financials, and campaigns API methods"
```

---

### Task F2: Enhanced Analytics View

**Files:**
- Modify: `lib/presentation/screens/manage/manage_panel_screen.dart`

- [ ] **Step 1: Update sidebar nav items**

In `manage_panel_screen.dart`, update the `_navItems` list to add new items and rename existing ones. Replace the existing `_navItems`:

```dart
  static const _navItems = [
    PanelNavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    PanelNavItem(icon: Icons.stadium_rounded, label: 'My Pitches'),
    PanelNavItem(icon: Icons.calendar_month_rounded, label: 'Bookings'),
    PanelNavItem(icon: Icons.analytics_rounded, label: 'Analytics Pro'),
    PanelNavItem(icon: Icons.event_note_rounded, label: 'My Bookings'),
    PanelNavItem(icon: Icons.account_balance_rounded, label: 'Financials Pro'),
    PanelNavItem(icon: Icons.dynamic_feed_rounded, label: 'Smart Pricing'),
    PanelNavItem(icon: Icons.campaign_rounded, label: 'Campaigns'),
  ];
```

And update the `IndexedStack` children to add the campaigns view:

```dart
      body: IndexedStack(
        index: _selectedIdx,
        children: const [
          _ManagerDashboard(),
          _MyPitchesView(),
          _ManagerBookingsView(),
          _AnalyticsProView(),
          _MyBookingsEnhancedView(),
          _FinancialsProView(),
          _SmartPricingView(),
          _CampaignsView(),
        ],
      ),
```

- [ ] **Step 2: Add the _AnalyticsProView widget**

Add this new widget class to `manage_panel_screen.dart`. This replaces `_MyAnalyticsView` in the IndexedStack. Add the widget below the existing `_MyAnalyticsView` class (keep the old one for reference but it's no longer in the IndexedStack):

```dart
// ─────────────────────────────────────────────────────────────────────────────
// Analytics Pro (Enhanced with Heatmap, Peak Hours, Customer Insights)
// ─────────────────────────────────────────────────────────────────────────────
class _AnalyticsProView extends ConsumerStatefulWidget {
  const _AnalyticsProView();
  @override
  ConsumerState<_AnalyticsProView> createState() => _AnalyticsProViewState();
}

class _AnalyticsProViewState extends ConsumerState<_AnalyticsProView> {
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _heatmap;
  Map<String, dynamic>? _peaks;
  Map<String, dynamic>? _customers;
  List<dynamic>? _pitchBreakdown;
  bool _loading = true;
  String _period = 'month';
  int _tab = 0; // 0=overview, 1=heatmap, 2=customers

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final src = ref.read(manageRemoteSourceProvider);
    try {
      final results = await Future.wait([
        src.getManagerSummary(period: _period),
        src.getManagerHeatmap(period: _period),
        src.getManagerPeakHours(period: _period),
        src.getManagerCustomerInsights(period: _period),
        src.getManagerPitchBreakdown(period: _period),
      ]);
      _summary = results[0] as Map<String, dynamic>;
      _heatmap = results[1] as Map<String, dynamic>;
      _peaks = results[2] as Map<String, dynamic>;
      _customers = results[3] as Map<String, dynamic>;
      _pitchBreakdown = results[4] as List<dynamic>;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));

    final s = _summary ?? {};
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Analytics Pro', style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Deep performance insights for your business', style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          // Period selector + tab selector
          Row(children: [
            _PeriodDropdown(value: _period, onChanged: (v) { _period = v; _load(); }),
            const SizedBox(width: 24),
            _TabButton(label: 'Overview', active: _tab == 0, onTap: () => setState(() => _tab = 0)),
            const SizedBox(width: 8),
            _TabButton(label: 'Heatmap', active: _tab == 1, onTap: () => setState(() => _tab = 1)),
            const SizedBox(width: 8),
            _TabButton(label: 'Customers', active: _tab == 2, onTap: () => setState(() => _tab = 2)),
          ]),
          const SizedBox(height: 20),
          // Summary cards (always visible)
          LayoutBuilder(builder: (ctx, box) {
            final cols = box.maxWidth > 1000 ? 5 : (box.maxWidth > 600 ? 3 : 2);
            final w = (box.maxWidth - (cols - 1) * 16) / cols;
            return Wrap(
              spacing: 16, runSpacing: 16,
              children: [
                SizedBox(width: w, child: StatCard(label: 'Revenue (BDT)', value: _fmtNum(s['revenue']), icon: Icons.payments, iconColor: AppColors.primary)),
                SizedBox(width: w, child: StatCard(label: 'Bookings', value: '${s['bookings'] ?? 0}', icon: Icons.calendar_month, iconColor: Colors.blueAccent)),
                SizedBox(width: w, child: StatCard(label: 'Occupancy', value: '${(s['occupancy'] as num?)?.toStringAsFixed(1) ?? '0'}%', icon: Icons.stadium, iconColor: Colors.orangeAccent)),
                SizedBox(width: w, child: StatCard(label: 'Avg Rating', value: (s['avg_rating'] as num?)?.toStringAsFixed(1) ?? '—', icon: Icons.star, iconColor: Colors.amber)),
                SizedBox(width: w, child: StatCard(
                  label: 'Avg/Day',
                  value: (_peaks?['avg_bookings_per_day'] as num?)?.toStringAsFixed(1) ?? '0',
                  icon: Icons.trending_up,
                  iconColor: Colors.tealAccent,
                )),
              ],
            );
          }),
          const SizedBox(height: 24),
          // Tab content
          if (_tab == 0) _buildOverviewTab(),
          if (_tab == 1) _buildHeatmapTab(),
          if (_tab == 2) _buildCustomersTab(),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final peakData = _peaks ?? {};
    final busiest = peakData['busiest'] as List<dynamic>? ?? [];
    final slowest = peakData['slowest'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Peak hours cards
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _peakHoursCard('Busiest Hours', busiest, AppColors.primary)),
            const SizedBox(width: 16),
            Expanded(child: _peakHoursCard('Slowest Hours', slowest, Colors.orangeAccent)),
          ],
        ),
        const SizedBox(height: 24),
        // Per-pitch breakdown
        if (_pitchBreakdown != null && _pitchBreakdown!.isNotEmpty)
          DataTableCard(
            title: 'Per-Pitch Breakdown',
            columns: const ['Pitch', 'Bookings', 'Revenue', 'Occupancy %', 'Rating'],
            onRefresh: _load,
            rows: _pitchBreakdown!.map((p) {
              final m = p as Map<String, dynamic>;
              return [
                CellText('${m['pitch_name'] ?? ''}', bold: true),
                CellText('${m['bookings'] ?? 0}'),
                CellText('${m['revenue'] ?? 0} BDT'),
                CellText('${(m['occupancy'] as num?)?.toStringAsFixed(1) ?? '0'}%'),
                CellText('${(m['avg_rating'] as num?)?.toStringAsFixed(1) ?? '—'}'),
              ];
            }).toList(),
          ),
      ],
    );
  }

  Widget _peakHoursCard(String title, List<dynamic> hours, Color accent) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryDeep, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          ...hours.map((h) {
            final m = h as Map<String, dynamic>;
            final hour = m['hour'] as int? ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${hour.toString().padLeft(2, '0')}:00',
                      style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: accent),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('${m['count'] ?? 0} bookings', style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textPrimary)),
                  const Spacer(),
                  Text('${m['revenue'] ?? 0} BDT', style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHeatmapTab() {
    final data = _heatmap?['data'] as List<dynamic>? ?? [];
    if (data.isEmpty) {
      return Center(child: Text('No heatmap data', style: GoogleFonts.dmSans(color: AppColors.textSecondary)));
    }

    final days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    // Build lookup: [day][hour] -> count
    final grid = <int, Map<int, int>>{};
    int maxCount = 1;
    for (final cell in data) {
      final m = cell as Map<String, dynamic>;
      final day = (m['day_of_week'] as num?)?.toInt() ?? 0;
      final hour = (m['hour'] as num?)?.toInt() ?? 0;
      final count = (m['count'] as num?)?.toInt() ?? 0;
      grid.putIfAbsent(day, () => {});
      grid[day]![hour] = count;
      if (count > maxCount) maxCount = count;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryDeep, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Booking Heatmap', style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Booking density by day and hour (darker = more bookings)', style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hour headers
                Row(
                  children: [
                    const SizedBox(width: 40),
                    for (int h = 8; h < 24; h++)
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${h.toString().padLeft(2, '0')}',
                          style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                // Rows per day
                for (int d = 0; d < 7; d++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          child: Text(days[d], style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                        ),
                        for (int h = 8; h < 24; h++)
                          _heatCell(grid[d]?[h] ?? 0, maxCount),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Legend
          Row(
            children: [
              Text('Less', style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(width: 6),
              for (double intensity in [0.0, 0.25, 0.5, 0.75, 1.0])
                Container(
                  width: 20, height: 20,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1 + intensity * 0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              const SizedBox(width: 6),
              Text('More', style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heatCell(int count, int maxCount) {
    final intensity = maxCount > 0 ? count / maxCount : 0.0;
    return Tooltip(
      message: '$count bookings',
      child: Container(
        width: 40, height: 32,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: count == 0
              ? const Color(0xFF051210)
              : AppColors.primary.withOpacity(0.15 + intensity * 0.75),
          borderRadius: BorderRadius.circular(4),
        ),
        child: count > 0
            ? Center(child: Text('$count', style: GoogleFonts.dmSans(fontSize: 10, color: Colors.white70)))
            : null,
      ),
    );
  }

  Widget _buildCustomersTab() {
    final c = _customers ?? {};
    final topCustomers = c['top_customers'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (ctx, box) {
          final cols = box.maxWidth > 800 ? 4 : 2;
          final w = (box.maxWidth - (cols - 1) * 16) / cols;
          return Wrap(
            spacing: 16, runSpacing: 16,
            children: [
              SizedBox(width: w, child: StatCard(label: 'Total Customers', value: '${c['total_customers'] ?? 0}', icon: Icons.people, iconColor: Colors.blueAccent)),
              SizedBox(width: w, child: StatCard(label: 'New Customers', value: '${c['new_customers'] ?? 0}', icon: Icons.person_add, iconColor: AppColors.primary)),
              SizedBox(width: w, child: StatCard(label: 'Returning %', value: '${(c['returning_pct'] as num?)?.toStringAsFixed(1) ?? '0'}%', icon: Icons.repeat, iconColor: Colors.purpleAccent)),
              SizedBox(width: w, child: StatCard(label: 'Avg Spend', value: _avgSpend(topCustomers), icon: Icons.payments, iconColor: Colors.orangeAccent)),
            ],
          );
        }),
        const SizedBox(height: 24),
        if (topCustomers.isNotEmpty)
          DataTableCard(
            title: 'Top Customers by Spend',
            columns: const ['Name', 'Phone', 'Bookings', 'Total Spent', 'Last Visit'],
            onRefresh: _load,
            rows: topCustomers.map((cu) {
              final m = cu as Map<String, dynamic>;
              return [
                CellText(m['name']?.toString().isNotEmpty == true ? m['name'] : 'Anonymous', bold: true),
                CellText(m['phone'] ?? '—'),
                CellText('${m['booking_count'] ?? 0}'),
                CellText('${m['total_spent'] ?? 0} BDT'),
                CellText(m['last_visit'] ?? '—'),
              ];
            }).toList(),
          ),
      ],
    );
  }

  String _avgSpend(List<dynamic> customers) {
    if (customers.isEmpty) return '0';
    double total = 0;
    for (final c in customers) {
      total += ((c as Map<String, dynamic>)['total_spent'] as num?)?.toDouble() ?? 0;
    }
    return '${(total / customers.length).toStringAsFixed(0)} BDT';
  }

  String _fmtNum(dynamic v) {
    if (v == null) return '0';
    final n = (v is int) ? v.toDouble() : (v as num).toDouble();
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }
}
```

- [ ] **Step 3: Add the _TabButton helper widget**

Add this small helper widget near the other helper widgets at the bottom of the file:

```dart
class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.primaryDeep,
            width: active ? 1.5 : 0.5,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Verify Flutter analyze**

Run: `cd /Users/fin.com/Projects/brain-systems/turfinn && flutter analyze lib/presentation/screens/manage/`
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/manage/manage_panel_screen.dart
git commit -m "feat(ui): add Analytics Pro view with heatmap, peak hours, and customer insights"
```

---

### Task F3: Enhanced Financials View

**Files:**
- Modify: `lib/presentation/screens/manage/manage_panel_screen.dart`

- [ ] **Step 1: Add the _FinancialsProView widget**

Add this widget class to `manage_panel_screen.dart`:

```dart
// ─────────────────────────────────────────────────────────────────────────────
// Financials Pro (Daily Ledger + Pitch P&L)
// ─────────────────────────────────────────────────────────────────────────────
class _FinancialsProView extends ConsumerStatefulWidget {
  const _FinancialsProView();
  @override
  ConsumerState<_FinancialsProView> createState() => _FinancialsProViewState();
}

class _FinancialsProViewState extends ConsumerState<_FinancialsProView> {
  Map<String, dynamic>? _ledger;
  List<dynamic>? _pitchPnL;
  Map<String, dynamic>? _basicFinancials;
  bool _loading = true;
  String _preset = 'month';
  int _tab = 0; // 0=overview, 1=daily ledger, 2=pitch P&L
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  String? get _from {
    if (_preset == 'custom' && _fromCtrl.text.isNotEmpty) return _fromCtrl.text;
    final now = DateTime.now();
    final days = _preset == 'week' ? 7 : 30;
    final d = now.subtract(Duration(days: days));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String? get _to {
    if (_preset == 'custom' && _toCtrl.text.isNotEmpty) return _toCtrl.text;
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final src = ref.read(manageRemoteSourceProvider);
    try {
      final results = await Future.wait([
        src.getManagerFinancials(from: _from, to: _to),
        src.getManagerDailyLedger(from: _from, to: _to),
        src.getManagerPitchPnL(from: _from, to: _to),
      ]);
      _basicFinancials = results[0] as Map<String, dynamic>;
      _ledger = results[1] as Map<String, dynamic>;
      _pitchPnL = results[2] as List<dynamic>;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));

    final f = _basicFinancials ?? {};
    final total = (f['total_revenue'] as num?)?.toDouble() ?? 0.0;
    final turfinn = (f['turfinn_revenue'] as num?)?.toDouble() ?? 0.0;
    final walkin = (f['walkin_revenue'] as num?)?.toDouble() ?? 0.0;
    final commission = turfinn * 0.05;
    final net = total - commission;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Financials Pro', style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Complete financial overview with daily ledger', style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          // Controls row
          Row(children: [
            _PeriodDropdown(value: _preset, items: const ['week', 'month', 'custom'], onChanged: (v) {
              _preset = v; if (v != 'custom') _load();
            }),
            if (_preset == 'custom') ...[
              const SizedBox(width: 12),
              SizedBox(width: 160, child: _WalkInField(controller: _fromCtrl, label: 'From (YYYY-MM-DD)')),
              const SizedBox(width: 8),
              SizedBox(width: 160, child: _WalkInField(controller: _toCtrl, label: 'To (YYYY-MM-DD)')),
              const SizedBox(width: 8),
              _SmallAction(icon: Icons.search, color: AppColors.primary, onTap: _load),
            ],
            const SizedBox(width: 24),
            _TabButton(label: 'Overview', active: _tab == 0, onTap: () => setState(() => _tab = 0)),
            const SizedBox(width: 8),
            _TabButton(label: 'Daily Ledger', active: _tab == 1, onTap: () => setState(() => _tab = 1)),
            const SizedBox(width: 8),
            _TabButton(label: 'Pitch P&L', active: _tab == 2, onTap: () => setState(() => _tab = 2)),
          ]),
          const SizedBox(height: 20),
          // Summary cards
          LayoutBuilder(builder: (ctx, box) {
            final cols = box.maxWidth > 1000 ? 5 : (box.maxWidth > 600 ? 3 : 2);
            final w = (box.maxWidth - (cols - 1) * 16) / cols;
            return Wrap(
              spacing: 16, runSpacing: 16,
              children: [
                SizedBox(width: w, child: StatCard(label: 'Gross Revenue', value: '${total.toStringAsFixed(0)} BDT', icon: Icons.payments, iconColor: AppColors.primary)),
                SizedBox(width: w, child: StatCard(label: 'App Revenue', value: '${turfinn.toStringAsFixed(0)} BDT', icon: Icons.phone_android, iconColor: Colors.blueAccent)),
                SizedBox(width: w, child: StatCard(label: 'Walk-in Revenue', value: '${walkin.toStringAsFixed(0)} BDT', icon: Icons.store, iconColor: Colors.orangeAccent)),
                SizedBox(width: w, child: StatCard(label: 'Commission (5%)', value: '${commission.toStringAsFixed(0)} BDT', icon: Icons.receipt_long, iconColor: Colors.redAccent)),
                SizedBox(width: w, child: StatCard(label: 'Net Revenue', value: '${net.toStringAsFixed(0)} BDT', icon: Icons.account_balance_wallet, iconColor: Colors.tealAccent)),
              ],
            );
          }),
          const SizedBox(height: 24),
          if (_tab == 0) _buildFinOverview(),
          if (_tab == 1) _buildDailyLedger(),
          if (_tab == 2) _buildPitchPnL(),
        ],
      ),
    );
  }

  Widget _buildFinOverview() {
    final pmList = _basicFinancials?['by_payment_method'] as List<dynamic>? ?? [];
    if (pmList.isEmpty) {
      return Center(child: Text('No financial data for this period', style: GoogleFonts.dmSans(color: AppColors.textSecondary)));
    }
    return DataTableCard(
      title: 'Walk-in Payment Methods',
      columns: const ['Method', 'Amount (BDT)', 'Count'],
      onRefresh: _load,
      rows: pmList.map((pm) {
        final m = pm as Map<String, dynamic>;
        final method = (m['method'] ?? '').toString();
        return [
          CellText(method.isNotEmpty ? '${method[0].toUpperCase()}${method.substring(1)}' : '—', bold: true),
          CellText('${m['amount'] ?? 0}'),
          CellText('${m['count'] ?? 0}'),
        ];
      }).toList(),
    );
  }

  Widget _buildDailyLedger() {
    final entries = _ledger?['entries'] as List<dynamic>? ?? [];
    final summary = _ledger?['summary'] as Map<String, dynamic>? ?? {};

    if (entries.isEmpty) {
      return Center(child: Text('No ledger entries', style: GoogleFonts.dmSans(color: AppColors.textSecondary)));
    }

    return DataTableCard(
      title: 'Daily Revenue Ledger (${entries.length} days)',
      columns: const ['Date', 'Bookings', 'Total', 'App', 'Walk-in', 'Commission', 'Net'],
      onRefresh: _load,
      rows: [
        ...entries.map((e) {
          final m = e as Map<String, dynamic>;
          final total = (m['total_revenue'] as num?)?.toDouble() ?? 0;
          final commission = (m['commission'] as num?)?.toDouble() ?? 0;
          return [
            CellText(m['date'] ?? '', bold: true),
            CellText('${m['booking_count'] ?? 0}'),
            CellText('${total.toStringAsFixed(0)}'),
            CellText('${((m['app_revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}'),
            CellText('${((m['walkin_revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}'),
            CellText('${commission.toStringAsFixed(0)}'),
            CellText('${(total - commission).toStringAsFixed(0)}'),
          ];
        }),
        // Summary row
        [
          CellText('TOTAL', bold: true),
          CellText('${summary['booking_count'] ?? 0}', bold: true),
          CellText('${((summary['total_revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', bold: true),
          CellText('${((summary['app_revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', bold: true),
          CellText('${((summary['walkin_revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', bold: true),
          CellText('${((summary['commission'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', bold: true),
          CellText('${(((summary['total_revenue'] as num?)?.toDouble() ?? 0) - ((summary['commission'] as num?)?.toDouble() ?? 0)).toStringAsFixed(0)}', bold: true),
        ],
      ],
    );
  }

  Widget _buildPitchPnL() {
    if (_pitchPnL == null || _pitchPnL!.isEmpty) {
      return Center(child: Text('No pitch data', style: GoogleFonts.dmSans(color: AppColors.textSecondary)));
    }

    return DataTableCard(
      title: 'Per-Pitch Profit & Loss',
      columns: const ['Pitch', 'Revenue', 'Bookings', 'Hours', 'Occupancy', 'Commission', 'Net'],
      onRefresh: _load,
      rows: _pitchPnL!.map((p) {
        final m = p as Map<String, dynamic>;
        return [
          CellText(m['pitch_name'] ?? '', bold: true),
          CellText('${((m['revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} BDT'),
          CellText('${m['booking_count'] ?? 0}'),
          CellText('${((m['booked_hours'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)}h'),
          CellText('${((m['occupancy_pct'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)}%'),
          CellText('${((m['commission'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} BDT'),
          CellText('${((m['net_revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} BDT'),
        ];
      }).toList(),
    );
  }
}
```

- [ ] **Step 2: Verify Flutter analyze**

Run: `cd /Users/fin.com/Projects/brain-systems/turfinn && flutter analyze lib/presentation/screens/manage/`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/screens/manage/manage_panel_screen.dart
git commit -m "feat(ui): add Financials Pro view with daily ledger and pitch P&L"
```

---

### Task F4: Campaigns View (Manager Promo Codes)

**Files:**
- Modify: `lib/presentation/screens/manage/manage_panel_screen.dart`

- [ ] **Step 1: Add the _CampaignsView widget**

Add this widget class to `manage_panel_screen.dart`:

```dart
// ─────────────────────────────────────────────────────────────────────────────
// Campaigns (Manager Promo Codes)
// ─────────────────────────────────────────────────────────────────────────────
class _CampaignsView extends ConsumerStatefulWidget {
  const _CampaignsView();
  @override
  ConsumerState<_CampaignsView> createState() => _CampaignsViewState();
}

class _CampaignsViewState extends ConsumerState<_CampaignsView> {
  List<dynamic> _promos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _promos = await ref.read(manageRemoteSourceProvider).listManagerPromos();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _deactivate(String id) async {
    try {
      await ref.read(manageRemoteSourceProvider).deactivateManagerPromo(id);
      _load();
    } catch (_) {}
  }

  void _showCreateDialog() {
    final codeCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    final maxUsesCtrl = TextEditingController(text: '100');
    final fromCtrl = TextEditingController();
    final toCtrl = TextEditingController();
    String discountType = 'percent';
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0A1F1A),
          title: Text('Create Promo Code', style: GoogleFonts.nunito(color: AppColors.textPrimary)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WalkInField(controller: codeCtrl, label: 'Promo Code (e.g. SUMMER25)'),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF051210),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.primaryDeep),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: discountType,
                            dropdownColor: const Color(0xFF0A1F1A),
                            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textPrimary),
                            icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary, size: 18),
                            onChanged: (v) => setDialogState(() => discountType = v ?? 'percent'),
                            items: [
                              DropdownMenuItem(value: 'percent', child: Text('Percent (%)')),
                              DropdownMenuItem(value: 'fixed', child: Text('Fixed (BDT)')),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _WalkInField(controller: valueCtrl, label: discountType == 'percent' ? 'Discount %' : 'Discount BDT')),
                  ]),
                  const SizedBox(height: 10),
                  _WalkInField(controller: maxUsesCtrl, label: 'Max Uses'),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _WalkInField(controller: fromCtrl, label: 'Valid From (YYYY-MM-DD)')),
                    const SizedBox(width: 10),
                    Expanded(child: _WalkInField(controller: toCtrl, label: 'Valid To (YYYY-MM-DD)')),
                  ]),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (codeCtrl.text.isEmpty || valueCtrl.text.isEmpty ||
                    fromCtrl.text.isEmpty || toCtrl.text.isEmpty) {
                  setDialogState(() => error = 'All fields are required');
                  return;
                }
                final value = double.tryParse(valueCtrl.text);
                if (value == null || value <= 0) {
                  setDialogState(() => error = 'Invalid discount value');
                  return;
                }
                if (discountType == 'percent' && value > 100) {
                  setDialogState(() => error = 'Percent discount cannot exceed 100');
                  return;
                }
                try {
                  await ref.read(manageRemoteSourceProvider).createManagerPromo({
                    'code': codeCtrl.text.trim(),
                    'discount_type': discountType,
                    'discount_value': value,
                    'max_uses': int.tryParse(maxUsesCtrl.text) ?? 100,
                    'valid_from': fromCtrl.text.trim(),
                    'valid_to': toCtrl.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  setDialogState(() => error = 'Failed to create promo');
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Campaigns', style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Create promo codes for your pitches to attract more players', style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                onPressed: _showCreateDialog,
                icon: const Icon(Icons.add, color: Colors.black, size: 18),
                label: Text('New Promo', style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Stats summary
          if (_promos.isNotEmpty) ...[
            LayoutBuilder(builder: (ctx, box) {
              final cols = box.maxWidth > 800 ? 3 : 2;
              final w = (box.maxWidth - (cols - 1) * 16) / cols;
              final active = _promos.where((p) => (p as Map)['is_active'] == true).length;
              final totalUsed = _promos.fold<int>(0, (sum, p) => sum + ((p as Map)['used_count'] as int? ?? 0));
              return Wrap(
                spacing: 16, runSpacing: 16,
                children: [
                  SizedBox(width: w, child: StatCard(label: 'Total Promos', value: '${_promos.length}', icon: Icons.local_offer, iconColor: Colors.blueAccent)),
                  SizedBox(width: w, child: StatCard(label: 'Active', value: '$active', icon: Icons.check_circle, iconColor: AppColors.primary)),
                  SizedBox(width: w, child: StatCard(label: 'Total Redemptions', value: '$totalUsed', icon: Icons.redeem, iconColor: Colors.purpleAccent)),
                ],
              );
            }),
            const SizedBox(height: 24),
          ],
          if (_loading)
            const Center(child: CircularProgressIndicator(color: AppColors.primary))
          else if (_promos.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(60),
                child: Column(
                  children: [
                    Icon(Icons.campaign, size: 64, color: AppColors.textSecondary.withOpacity(0.3)),
                    const SizedBox(height: 16),
                    Text('No promo codes yet', style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    Text('Create your first promo code to attract more players', style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            )
          else
            DataTableCard(
              title: 'Promo Codes (${_promos.length})',
              columns: const ['Code', 'Type', 'Value', 'Used / Max', 'Valid From', 'Valid To', 'Status', 'Actions'],
              onRefresh: _load,
              rows: _promos.map((p) {
                final m = p as Map<String, dynamic>;
                final isActive = m['is_active'] == true;
                final discountType = m['discount_type'] ?? '';
                final discountValue = m['discount_value'] ?? 0;
                return [
                  CellText(m['code'] ?? '', bold: true),
                  CellText(discountType == 'percent' ? 'Percent' : 'Fixed'),
                  CellText(discountType == 'percent' ? '$discountValue%' : '$discountValue BDT'),
                  CellText('${m['used_count'] ?? 0} / ${m['max_uses'] ?? '—'}'),
                  CellText(m['valid_from'] ?? ''),
                  CellText(m['valid_to'] ?? ''),
                  StatusBadge(status: isActive ? 'active' : 'cancelled'),
                  isActive
                      ? _SmallAction(
                          icon: Icons.pause,
                          color: Colors.orangeAccent,
                          onTap: () => _deactivate(m['id']),
                        )
                      : const SizedBox.shrink(),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Remove old _MyAnalyticsView and _MyFinancialsView from IndexedStack**

The old `_MyAnalyticsView` and `_MyFinancialsView` classes should be kept in the file (they can remain as dead code for now or be deleted). The key change is that the `IndexedStack` children list (updated in Task F2, Step 1) already references `_AnalyticsProView` and `_FinancialsProView` instead.

- [ ] **Step 3: Verify Flutter analyze**

Run: `cd /Users/fin.com/Projects/brain-systems/turfinn && flutter analyze lib/presentation/screens/manage/`
Expected: No errors (warnings about unused old classes are OK)

- [ ] **Step 4: Verify build**

Run: `cd /Users/fin.com/Projects/brain-systems/turfinn && flutter build web --target lib/main_manage.dart --output /tmp/test_build --dart-define=API_BASE_URL=/api/v1 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/manage/manage_panel_screen.dart
git commit -m "feat(ui): add Campaigns view with manager promo code CRUD"
```

---

## Final Verification

- [ ] **Step 1: Run Go tests**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/backend && go test ./... -v
```
Expected: All tests pass

- [ ] **Step 2: Run Go build**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn/backend && go build ./...
```
Expected: Build succeeds

- [ ] **Step 3: Run Flutter analyze**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn && flutter analyze
```
Expected: No errors

- [ ] **Step 4: Commit final state**

```bash
git add -A
git commit -m "feat: enhanced manager panel — analytics pro, financials pro, campaigns"
```

---

## Summary of New Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/manager/analytics/heatmap` | 7x16 hourly booking heatmap |
| GET | `/api/v1/manager/analytics/peak-hours` | Top 5 busiest + slowest hours |
| GET | `/api/v1/manager/analytics/customers` | Customer insights: new vs returning, top spenders |
| GET | `/api/v1/manager/financials/ledger` | Day-by-day revenue breakdown with commission |
| GET | `/api/v1/manager/financials/pitch-pnl` | Per-pitch profit & loss |
| GET | `/api/v1/manager/promos` | List manager's promo codes |
| POST | `/api/v1/manager/promos` | Create promo scoped to manager's pitches |
| PUT | `/api/v1/manager/promos/:id/deactivate` | Deactivate a promo |

## Summary of New UI Views

| Sidebar Item | Tab | Content |
|---|---|---|
| Analytics Pro | Overview | Summary cards + peak hours + pitch breakdown |
| Analytics Pro | Heatmap | Interactive 7-day x 16-hour heatmap grid with tooltips |
| Analytics Pro | Customers | New vs returning, top 10 customers by spend |
| Financials Pro | Overview | Gross/Net/Commission cards + payment methods |
| Financials Pro | Daily Ledger | Day-by-day table with totals row |
| Financials Pro | Pitch P&L | Per-pitch revenue, hours, occupancy, commission, net |
| Campaigns | — | Promo code CRUD with stats cards + data table |
