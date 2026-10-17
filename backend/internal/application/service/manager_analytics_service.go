package service

import (
	"context"
	"sort"
	"time"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/interfaces/dto"
	"gorm.io/gorm"
)

// ManagerAnalyticsService provides enhanced analytics for the manager dashboard.
type ManagerAnalyticsService struct {
	db *gorm.DB
}

// NewManagerAnalyticsService creates a new ManagerAnalyticsService.
func NewManagerAnalyticsService(db *gorm.DB) *ManagerAnalyticsService {
	return &ManagerAnalyticsService{db: db}
}

// FillHeatmapGrid takes sparse hourly booking data and returns a full 7×16 grid
// (days 0–6, hours 8–23 = 112 cells). Missing cells receive zero values.
func FillHeatmapGrid(raw []dto.HourlyBookingCount) []dto.HourlyBookingCount {
	// Build a lookup map from the sparse input.
	lookup := make(map[[2]int]dto.HourlyBookingCount, len(raw))
	for _, r := range raw {
		lookup[[2]int{r.DayOfWeek, r.Hour}] = r
	}

	grid := make([]dto.HourlyBookingCount, 0, 7*16)
	for day := 0; day <= 6; day++ {
		for hour := 8; hour <= 23; hour++ {
			key := [2]int{day, hour}
			if cell, ok := lookup[key]; ok {
				grid = append(grid, cell)
			} else {
				grid = append(grid, dto.HourlyBookingCount{
					DayOfWeek: day,
					Hour:      hour,
					Count:     0,
					Revenue:   0,
				})
			}
		}
	}
	return grid
}

// TopAndBottom returns the top-N busiest hours (desc by count) and bottom-N
// slowest hours (asc by count) from the provided slice. The input slice is
// not modified (copies are made internally).
func TopAndBottom(hours []dto.PeakHour, n int) (top, bottom []dto.PeakHour) {
	if len(hours) == 0 {
		return nil, nil
	}

	// Sort descending by count for the top list.
	desc := make([]dto.PeakHour, len(hours))
	copy(desc, hours)
	sort.Slice(desc, func(i, j int) bool {
		return desc[i].Count > desc[j].Count
	})

	// Sort ascending by count for the bottom list.
	asc := make([]dto.PeakHour, len(hours))
	copy(asc, hours)
	sort.Slice(asc, func(i, j int) bool {
		return asc[i].Count < asc[j].Count
	})

	if n > len(hours) {
		n = len(hours)
	}
	return desc[:n], asc[:n]
}

// GetHeatmap returns a 7×16 booking-count grid (day × hour) for the manager's
// pitches over the given period.
func (s *ManagerAnalyticsService) GetHeatmap(ctx context.Context, managerID uuid.UUID, period string) (dto.HeatmapResponse, error) {
	from, to := PeriodRange(period)

	type row struct {
		DayOfWeek int     `gorm:"column:dow"`
		Hour      int     `gorm:"column:hour"`
		Count     int64   `gorm:"column:count"`
		Revenue   float64 `gorm:"column:revenue"`
	}
	var rows []row
	if err := s.db.WithContext(ctx).Raw(`
		SELECT
			EXTRACT(DOW FROM b.starts_at)::int         AS dow,
			EXTRACT(HOUR FROM b.starts_at)::int        AS hour,
			COUNT(b.id)                                AS count,
			COALESCE(SUM(b.total_cost), 0)             AS revenue
		FROM bookings b
		JOIN pitches p ON b.pitch_id = p.id
		WHERE p.owner_id = ?
		  AND b.status IN ('confirmed','completed')
		  AND b.starts_at >= ? AND b.starts_at < ?
		GROUP BY dow, hour
		ORDER BY dow, hour
	`, managerID, from, to).Scan(&rows).Error; err != nil {
		return dto.HeatmapResponse{}, err
	}

	raw := make([]dto.HourlyBookingCount, 0, len(rows))
	for _, r := range rows {
		raw = append(raw, dto.HourlyBookingCount{
			DayOfWeek: r.DayOfWeek,
			Hour:      r.Hour,
			Count:     r.Count,
			Revenue:   r.Revenue,
		})
	}

	return dto.HeatmapResponse{
		Period: period,
		Data:   FillHeatmapGrid(raw),
	}, nil
}

// GetPeakHours returns the 5 busiest and 5 slowest hours plus average bookings
// per day for the manager's pitches over the given period.
func (s *ManagerAnalyticsService) GetPeakHours(ctx context.Context, managerID uuid.UUID, period string) (dto.PeakHoursResponse, error) {
	from, to := PeriodRange(period)

	type row struct {
		Hour    int     `gorm:"column:hour"`
		Count   int64   `gorm:"column:count"`
		Revenue float64 `gorm:"column:revenue"`
	}
	var rows []row
	if err := s.db.WithContext(ctx).Raw(`
		SELECT
			EXTRACT(HOUR FROM b.starts_at)::int AS hour,
			COUNT(b.id)                         AS count,
			COALESCE(SUM(b.total_cost), 0)      AS revenue
		FROM bookings b
		JOIN pitches p ON b.pitch_id = p.id
		WHERE p.owner_id = ?
		  AND b.status IN ('confirmed','completed')
		  AND b.starts_at >= ? AND b.starts_at < ?
		GROUP BY hour
		ORDER BY hour
	`, managerID, from, to).Scan(&rows).Error; err != nil {
		return dto.PeakHoursResponse{}, err
	}

	hours := make([]dto.PeakHour, 0, len(rows))
	var totalBookings int64
	for _, r := range rows {
		hours = append(hours, dto.PeakHour{Hour: r.Hour, Count: r.Count, Revenue: r.Revenue})
		totalBookings += r.Count
	}

	top, bottom := TopAndBottom(hours, 5)

	days := to.Sub(from).Hours() / 24
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

// GetCustomerInsights returns unique customer counts, new-vs-returning split,
// and the top 10 customers by spend for the given period.
func (s *ManagerAnalyticsService) GetCustomerInsights(ctx context.Context, managerID uuid.UUID, period string) (dto.CustomerInsightsResponse, error) {
	from, to := PeriodRange(period)

	// Total unique customers in period.
	var totalCustomers int64
	if err := s.db.WithContext(ctx).Raw(`
		SELECT COUNT(DISTINCT b.user_id)
		FROM bookings b
		JOIN pitches p ON b.pitch_id = p.id
		WHERE p.owner_id = ?
		  AND b.status IN ('confirmed','completed')
		  AND b.starts_at >= ? AND b.starts_at < ?
	`, managerID, from, to).Scan(&totalCustomers).Error; err != nil {
		return dto.CustomerInsightsResponse{}, err
	}

	// New customers: users whose very first booking at these pitches is within
	// the period (no confirmed/completed booking before `from`).
	var newCustomers int64
	if err := s.db.WithContext(ctx).Raw(`
		SELECT COUNT(DISTINCT b.user_id)
		FROM bookings b
		JOIN pitches p ON b.pitch_id = p.id
		WHERE p.owner_id = ?
		  AND b.status IN ('confirmed','completed')
		  AND b.starts_at >= ? AND b.starts_at < ?
		  AND NOT EXISTS (
			SELECT 1
			FROM bookings b2
			JOIN pitches p2 ON b2.pitch_id = p2.id
			WHERE p2.owner_id = ?
			  AND b2.user_id = b.user_id
			  AND b2.status IN ('confirmed','completed')
			  AND b2.starts_at < ?
		  )
	`, managerID, from, to, managerID, from).Scan(&newCustomers).Error; err != nil {
		return dto.CustomerInsightsResponse{}, err
	}

	returningPct := 0.0
	if totalCustomers > 0 {
		returningPct = float64(totalCustomers-newCustomers) / float64(totalCustomers) * 100
	}

	// Top 10 customers by spend.
	type topRow struct {
		UserID       string  `gorm:"column:user_id"`
		Name         string  `gorm:"column:name"`
		Phone        string  `gorm:"column:phone"`
		BookingCount int64   `gorm:"column:booking_count"`
		TotalSpent   float64 `gorm:"column:total_spent"`
		LastVisit    string  `gorm:"column:last_visit"`
	}
	var topRows []topRow
	if err := s.db.WithContext(ctx).Raw(`
		SELECT
			u.id::text                                  AS user_id,
			u.name                                      AS name,
			COALESCE(u.phone, '')                       AS phone,
			COUNT(b.id)                                 AS booking_count,
			COALESCE(SUM(b.total_cost), 0)              AS total_spent,
			TO_CHAR(MAX(b.starts_at), 'YYYY-MM-DD')     AS last_visit
		FROM bookings b
		JOIN pitches p ON b.pitch_id = p.id
		JOIN users u ON b.user_id = u.id
		WHERE p.owner_id = ?
		  AND b.status IN ('confirmed','completed')
		  AND b.starts_at >= ? AND b.starts_at < ?
		GROUP BY u.id, u.name, u.phone
		ORDER BY total_spent DESC
		LIMIT 10
	`, managerID, from, to).Scan(&topRows).Error; err != nil {
		return dto.CustomerInsightsResponse{}, err
	}

	top := make([]dto.CustomerInsight, 0, len(topRows))
	for _, r := range topRows {
		top = append(top, dto.CustomerInsight{
			UserID:       r.UserID,
			Name:         r.Name,
			Phone:        r.Phone,
			BookingCount: r.BookingCount,
			TotalSpent:   r.TotalSpent,
			LastVisit:    r.LastVisit,
		})
	}

	return dto.CustomerInsightsResponse{
		Period:         period,
		TotalCustomers: totalCustomers,
		NewCustomers:   newCustomers,
		ReturningPct:   returningPct,
		TopCustomers:   top,
	}, nil
}

// GetDailyLedger returns a day-by-day breakdown of bookings and revenue between
// from and to (inclusive), plus a summary totals row.
func (s *ManagerAnalyticsService) GetDailyLedger(ctx context.Context, managerID uuid.UUID, from, to time.Time) (dto.DailyLedgerResponse, error) {
	// Extend `to` to end-of-day so the date range is inclusive.
	toExclusive := time.Date(to.Year(), to.Month(), to.Day()+1, 0, 0, 0, 0, to.Location())

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
			TO_CHAR(DATE(b.starts_at), 'YYYY-MM-DD')                          AS date,
			COUNT(b.id)                                                        AS booking_count,
			COALESCE(SUM(b.total_cost), 0)                                     AS total_revenue,
			COALESCE(SUM(CASE WHEN b.source = 'turfinn' THEN b.total_cost ELSE 0 END), 0) AS app_revenue,
			COALESCE(SUM(CASE WHEN b.source != 'turfinn' THEN b.total_cost ELSE 0 END), 0) AS walkin_revenue
		FROM bookings b
		JOIN pitches p ON b.pitch_id = p.id
		WHERE p.owner_id = ?
		  AND b.status IN ('confirmed','completed')
		  AND b.starts_at >= ? AND b.starts_at < ?
		GROUP BY DATE(b.starts_at)
		ORDER BY date ASC
	`, managerID, from, toExclusive).Scan(&rows).Error; err != nil {
		return dto.DailyLedgerResponse{}, err
	}

	const commissionRate = 0.05

	entries := make([]dto.DailyLedgerEntry, 0, len(rows))
	var summary dto.DailyLedgerEntry
	summary.Date = "total"

	for _, r := range rows {
		commission := r.AppRevenue * commissionRate
		entry := dto.DailyLedgerEntry{
			Date:          r.Date,
			BookingCount:  r.BookingCount,
			TotalRevenue:  r.TotalRevenue,
			AppRevenue:    r.AppRevenue,
			WalkInRevenue: r.WalkInRevenue,
			Commission:    commission,
		}
		entries = append(entries, entry)

		summary.BookingCount += r.BookingCount
		summary.TotalRevenue += r.TotalRevenue
		summary.AppRevenue += r.AppRevenue
		summary.WalkInRevenue += r.WalkInRevenue
		summary.Commission += commission
	}

	return dto.DailyLedgerResponse{
		From:    from.Format("2006-01-02"),
		To:      to.Format("2006-01-02"),
		Entries: entries,
		Summary: summary,
	}, nil
}

// GetPitchPnL returns per-pitch P&L for the given date range.
func (s *ManagerAnalyticsService) GetPitchPnL(ctx context.Context, managerID uuid.UUID, from, to time.Time) ([]dto.PitchPnLEntry, error) {
	toExclusive := time.Date(to.Year(), to.Month(), to.Day()+1, 0, 0, 0, 0, to.Location())

	days := toExclusive.Sub(from).Hours() / 24

	type pnlRow struct {
		PitchID      string  `gorm:"column:pitch_id"`
		PitchName    string  `gorm:"column:pitch_name"`
		Revenue      float64 `gorm:"column:revenue"`
		AppRevenue   float64 `gorm:"column:app_revenue"`
		BookingCount int64   `gorm:"column:booking_count"`
		BookedHours  float64 `gorm:"column:booked_hours"`
	}
	var rows []pnlRow
	if err := s.db.WithContext(ctx).Raw(`
		SELECT
			p.id::text                                                              AS pitch_id,
			p.name                                                                  AS pitch_name,
			COALESCE(SUM(b.total_cost), 0)                                          AS revenue,
			COALESCE(SUM(CASE WHEN b.source = 'turfinn' THEN b.total_cost ELSE 0 END), 0) AS app_revenue,
			COUNT(b.id)                                                             AS booking_count,
			COALESCE(SUM(EXTRACT(EPOCH FROM (b.ends_at - b.starts_at)) / 3600), 0) AS booked_hours
		FROM pitches p
		LEFT JOIN bookings b ON b.pitch_id = p.id
			AND b.status IN ('confirmed','completed')
			AND b.starts_at >= ? AND b.starts_at < ?
		WHERE p.owner_id = ?
		GROUP BY p.id, p.name
		ORDER BY revenue DESC
	`, from, toExclusive, managerID).Scan(&rows).Error; err != nil {
		return nil, err
	}

	const commissionRate = 0.05

	entries := make([]dto.PitchPnLEntry, 0, len(rows))
	for _, r := range rows {
		occupancy := 0.0
		if days > 0 {
			totalAvailableHours := operatingHoursPerDay * days
			if totalAvailableHours > 0 {
				occupancy = r.BookedHours / totalAvailableHours * 100
			}
		}
		commission := r.AppRevenue * commissionRate
		entries = append(entries, dto.PitchPnLEntry{
			PitchID:      r.PitchID,
			PitchName:    r.PitchName,
			Revenue:      r.Revenue,
			BookingCount: r.BookingCount,
			BookedHours:  r.BookedHours,
			OccupancyPct: occupancy,
			Commission:   commission,
			NetRevenue:   r.Revenue - commission,
		})
	}
	return entries, nil
}
