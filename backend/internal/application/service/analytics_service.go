package service

import (
	"context"
	"fmt"
	"sort"
	"time"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/interfaces/dto"
	"gorm.io/gorm"
)

// operatingHoursPerDay is the turf operating window (08:00–00:00).
const operatingHoursPerDay = 16.0

type AnalyticsService struct {
	db      *gorm.DB
	ledger  *LedgerService
	pricing *PricingService
	settle  *WeeklySettlementService
}

func NewAnalyticsService(db *gorm.DB) *AnalyticsService {
	return &AnalyticsService{
		db:      db,
		ledger:  NewLedgerService(db),
		pricing: NewPricingService(db),
		settle:  NewWeeklySettlementService(db),
	}
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
	now := time.Now().UTC()
	result := make([]dto.DailyRevenue, days)
	for i := range result {
		d := now.AddDate(0, 0, -(days-1-i)).Format("2006-01-02")
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
	if err := s.db.WithContext(ctx).Raw(`
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
	`, managerID, from, to).Scan(&row).Error; err != nil {
		return dto.AnalyticsSummaryResponse{}, err
	}

	var avgRating float64
	if err := s.db.WithContext(ctx).Raw(`
		SELECT COALESCE(AVG(r.rating), 0)
		FROM reviews r
		JOIN pitches p ON r.pitch_id = p.id
		WHERE p.owner_id = ?
	`, managerID).Scan(&avgRating).Error; err != nil {
		return dto.AnalyticsSummaryResponse{}, err
	}

	occupancy := 0.0
	if row.PitchCount > 0 {
		days := to.Sub(from).Hours() / 24
		totalHours := operatingHoursPerDay * days * float64(row.PitchCount)
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
	if err := s.db.WithContext(ctx).Raw(`
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
	`, managerID, days).Scan(&rows).Error; err != nil {
		return dto.RevenueChartResponse{}, err
	}

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
	if err := s.db.WithContext(ctx).Raw(`
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
	`, from, to, managerID).Scan(&rows).Error; err != nil {
		return nil, err
	}

	stats := make([]dto.PitchStats, 0, len(rows))
	for _, r := range rows {
		occupancy := 0.0
		if days > 0 {
			occupancy = r.BookedHours / (operatingHoursPerDay * days) * 100
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
	if filter.Page < 1 {
		filter.Page = 1
	}
	if filter.Limit < 1 {
		filter.Limit = 20
	}

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

	// count on a clean clone
	var total int64
	countQ := q.Session(&gorm.Session{})
	if err := countQ.Count(&total).Error; err != nil {
		return nil, 0, err
	}

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

	// Walk-in ledger entry. Walks through the same PricingService as app
	// bookings so trial / override / cash-handling toggle all flow
	// through one resolver. Best-effort — never block the booking on
	// ledger failures (matches the booking-service pattern).
	if s.ledger != nil && s.pricing != nil {
		walkinBps := s.pricing.ResolveCommissionBps(ctx, &pitch, "walk_in", 0)
		totalPaisa := int64(totalCost * 100)
		_ = s.ledger.RecordBookingPayment(ctx, nil, booking.ID, totalPaisa, walkinBps)
		// Walk-ins still credit the owner — at 0% commission they get
		// the full amount. At 2% (cash-handling on) they get 98%.
		if s.settle != nil {
			ownerShare := totalPaisa - (totalPaisa * int64(walkinBps) / 10000)
			if ownerShare > 0 && pitch.OwnerID != uuid.Nil {
				_ = s.settle.CreditOwner(s.db.WithContext(ctx), pitch.OwnerID, ownerShare)
			}
		}
	}
	return booking, nil
}

// UpdateBookingStatus confirms or cancels a booking — ownership-checked atomically.
func (s *AnalyticsService) UpdateBookingStatus(ctx context.Context, managerID, bookingID uuid.UUID, status entity.BookingStatus) error {
	result := s.db.WithContext(ctx).
		Model(&entity.Booking{}).
		Joins("JOIN pitches ON bookings.pitch_id = pitches.id").
		Where("bookings.id = ? AND pitches.owner_id = ?", bookingID, managerID).
		Update("status", status)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return fmt.Errorf("booking not found or not owned by you")
	}
	return nil
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
	if err := s.db.WithContext(ctx).Raw(`
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
	`, managerID, from, to).Scan(&rows).Error; err != nil {
		return dto.FinancialsResponse{}, err
	}

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
	sort.Slice(pmList, func(i, j int) bool { return pmList[i].Method < pmList[j].Method })

	return dto.FinancialsResponse{
		From:            from.Format("2006-01-02"),
		To:              to.Format("2006-01-02"),
		TotalRevenue:    totalRevenue,
		TurfinnRevenue:  turfinnRevenue,
		WalkInRevenue:   walkinRevenue,
		ByPaymentMethod: pmList,
	}, nil
}
