// Package repository provides GORM implementations for super-admin features.
package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"gorm.io/gorm"
)

type superAdminRepository struct {
	db    *gorm.DB
	redis *redis.Client
}

func NewSuperAdminRepository(db *gorm.DB, redis *redis.Client) domain.SuperAdminRepository {
	return &superAdminRepository{db: db, redis: redis}
}

// ── Business Intelligence ────────────────────────────────────────────────────

func (r *superAdminRepository) GetNorthStarMetrics(ctx context.Context) (*domain.NorthStarMetrics, error) {
	m := &domain.NorthStarMetrics{}
	now := time.Now()
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())

	// GMV all time
	r.db.WithContext(ctx).Raw(`SELECT COALESCE(SUM(total_cost), 0) FROM bookings WHERE status IN ('confirmed','completed')`).Scan(&m.GMV)
	// GMV MTD
	r.db.WithContext(ctx).Raw(`SELECT COALESCE(SUM(total_cost), 0) FROM bookings WHERE status IN ('confirmed','completed') AND created_at >= ?`, monthStart).Scan(&m.GMVMTD)

	// Net revenue (platform fee)
	var feePct float64
	r.db.WithContext(ctx).Raw(`SELECT COALESCE(value::numeric, 10) FROM platform_settings WHERE key = 'platform_fee_percent'`).Scan(&feePct)
	if feePct == 0 {
		feePct = 10
	}
	m.NetRevenue = m.GMV * feePct / 100
	m.NetRevenueMTD = m.GMVMTD * feePct / 100

	// Active turfs (≥1 booking in last 30 days)
	thirtyDaysAgo := now.AddDate(0, 0, -30)
	r.db.WithContext(ctx).Raw(`SELECT COUNT(DISTINCT pitch_id) FROM bookings WHERE created_at >= ?`, thirtyDaysAgo).Scan(&m.ActiveTurfs)

	// Active players
	r.db.WithContext(ctx).Raw(`SELECT COUNT(DISTINCT user_id) FROM bookings WHERE created_at >= ?`, thirtyDaysAgo).Scan(&m.ActivePlayers)

	// Total bookings
	r.db.WithContext(ctx).Raw(`SELECT COUNT(*) FROM bookings`).Scan(&m.TotalBookings)
	r.db.WithContext(ctx).Raw(`SELECT COUNT(*) FROM bookings WHERE created_at >= ?`, monthStart).Scan(&m.BookingsMTD)

	return m, nil
}

func (r *superAdminRepository) GetCohortRetention(ctx context.Context, months int) ([]domain.CohortRow, error) {
	query := `
		WITH cohorts AS (
			SELECT id AS user_id, date_trunc('month', created_at) AS cohort_month
			FROM users WHERE deleted_at IS NULL
		),
		activity AS (
			SELECT user_id, date_trunc('month', created_at) AS activity_month
			FROM bookings GROUP BY user_id, date_trunc('month', created_at)
		),
		retention AS (
			SELECT
				c.cohort_month,
				EXTRACT(MONTH FROM age(a.activity_month, c.cohort_month))::int AS month_offset,
				COUNT(DISTINCT a.user_id) AS retained,
				(SELECT COUNT(*) FROM cohorts WHERE cohort_month = c.cohort_month) AS cohort_size
			FROM cohorts c
			LEFT JOIN activity a ON c.user_id = a.user_id AND a.activity_month >= c.cohort_month
			WHERE c.cohort_month >= date_trunc('month', NOW() - interval '%d months')
			GROUP BY c.cohort_month, month_offset
			ORDER BY c.cohort_month, month_offset
		)
		SELECT
			to_char(cohort_month, 'YYYY-MM') AS cohort_month,
			month_offset,
			retained,
			cohort_size
		FROM retention WHERE month_offset IS NOT NULL
	`
	var rows []domain.CohortRow
	err := r.db.WithContext(ctx).Raw(fmt.Sprintf(query, months)).Scan(&rows).Error
	return rows, err
}

func (r *superAdminRepository) GetFunnel(ctx context.Context, from, to time.Time) ([]domain.FunnelStep, error) {
	var steps []domain.FunnelStep
	err := r.db.WithContext(ctx).Raw(`
		SELECT event_type, COUNT(*) AS count
		FROM booking_events
		WHERE created_at BETWEEN ? AND ?
		GROUP BY event_type
		ORDER BY CASE event_type
			WHEN 'app_open' THEN 1
			WHEN 'pitch_search' THEN 2
			WHEN 'pitch_view' THEN 3
			WHEN 'slot_selected' THEN 4
			WHEN 'checkout_started' THEN 5
			WHEN 'payment_initiated' THEN 6
			WHEN 'booking_confirmed' THEN 7
			ELSE 8
		END
	`, from, to).Scan(&steps).Error
	return steps, err
}

func (r *superAdminRepository) GetRevenueTimeSeries(ctx context.Context, period string, from, to time.Time) ([]domain.RevenuePoint, error) {
	trunc := "day"
	switch period {
	case "week":
		trunc = "week"
	case "month":
		trunc = "month"
	}

	var points []domain.RevenuePoint
	err := r.db.WithContext(ctx).Raw(fmt.Sprintf(`
		SELECT
			to_char(date_trunc('%s', created_at), 'YYYY-MM-DD') AS date,
			COALESCE(SUM(total_cost), 0) AS revenue
		FROM bookings
		WHERE status IN ('confirmed','completed') AND created_at BETWEEN ? AND ?
		GROUP BY date_trunc('%s', created_at)
		ORDER BY date_trunc('%s', created_at)
	`, trunc, trunc, trunc), from, to).Scan(&points).Error
	return points, err
}

// ── Booking Events ───────────────────────────────────────────────────────────

func (r *superAdminRepository) CreateBookingEvent(ctx context.Context, e *entity.BookingEvent) error {
	e.ID = uuid.New()
	e.CreatedAt = time.Now()
	return r.db.WithContext(ctx).Create(e).Error
}

// ── Marketing Spend ──────────────────────────────────────────────────────────

func (r *superAdminRepository) GetMarketingSpend(ctx context.Context, month time.Time) (*entity.MarketingSpend, error) {
	var s entity.MarketingSpend
	if err := r.db.WithContext(ctx).Where("month = ?", month).First(&s).Error; err != nil {
		return nil, err
	}
	return &s, nil
}

func (r *superAdminRepository) UpsertMarketingSpend(ctx context.Context, s *entity.MarketingSpend) error {
	return r.db.WithContext(ctx).Save(s).Error
}

// ── Audit Log ────────────────────────────────────────────────────────────────

func (r *superAdminRepository) ListAuditLog(ctx context.Context, actorID *uuid.UUID, entityType, action string, from, to *time.Time, page, limit int) ([]entity.AuditLog, int64, error) {
	var total int64
	q := r.db.WithContext(ctx).Model(&entity.AuditLog{})
	if actorID != nil {
		q = q.Where("actor_id = ?", *actorID)
	}
	if entityType != "" {
		q = q.Where("entity_type = ?", entityType)
	}
	if action != "" {
		q = q.Where("action ILIKE ?", "%"+action+"%")
	}
	if from != nil {
		q = q.Where("created_at >= ?", *from)
	}
	if to != nil {
		q = q.Where("created_at <= ?", *to)
	}
	q.Count(&total)

	var items []entity.AuditLog
	err := q.Order("created_at DESC").Offset((page - 1) * limit).Limit(limit).Find(&items).Error
	return items, total, err
}

func (r *superAdminRepository) CreateAuditLog(ctx context.Context, log *entity.AuditLog) error {
	log.CreatedAt = time.Now()
	return r.db.WithContext(ctx).Create(log).Error
}

// ── Ledger ───────────────────────────────────────────────────────────────────

func (r *superAdminRepository) ListLedgerEntries(ctx context.Context, entryType string, from, to *time.Time, page, limit int) ([]entity.LedgerEntry, int64, error) {
	var total int64
	q := r.db.WithContext(ctx).Model(&entity.LedgerEntry{})
	if entryType != "" {
		q = q.Where("entry_type = ?", entryType)
	}
	if from != nil {
		q = q.Where("created_at >= ?", *from)
	}
	if to != nil {
		q = q.Where("created_at <= ?", *to)
	}
	q.Count(&total)

	var items []entity.LedgerEntry
	err := q.Order("created_at DESC").Offset((page - 1) * limit).Limit(limit).Find(&items).Error
	return items, total, err
}

func (r *superAdminRepository) CreateLedgerEntry(ctx context.Context, e *entity.LedgerEntry) error {
	e.ID = uuid.New()
	e.CreatedAt = time.Now()
	return r.db.WithContext(ctx).Create(e).Error
}

func (r *superAdminRepository) GetTrialBalance(ctx context.Context) (map[string]int64, error) {
	type row struct {
		Account string
		Net     int64
	}
	var debits, credits []row
	r.db.WithContext(ctx).Raw(`SELECT debit_account AS account, COALESCE(SUM(amount_paisa), 0) AS net FROM ledger_entries GROUP BY debit_account`).Scan(&debits)
	r.db.WithContext(ctx).Raw(`SELECT credit_account AS account, COALESCE(SUM(amount_paisa), 0) AS net FROM ledger_entries GROUP BY credit_account`).Scan(&credits)

	balance := make(map[string]int64)
	for _, d := range debits {
		balance[d.Account] += d.Net
	}
	for _, c := range credits {
		balance[c.Account] -= c.Net
	}
	return balance, nil
}

func (r *superAdminRepository) GetIncomeStatement(ctx context.Context, from, to time.Time) (int64, int64, int64, error) {
	var revenue, refunds, promoExpense int64
	r.db.WithContext(ctx).Raw(`SELECT COALESCE(SUM(amount_paisa), 0) FROM ledger_entries WHERE credit_account = 'platform_revenue' AND created_at BETWEEN ? AND ?`, from, to).Scan(&revenue)
	r.db.WithContext(ctx).Raw(`SELECT COALESCE(SUM(amount_paisa), 0) FROM ledger_entries WHERE entry_type = 'refund' AND created_at BETWEEN ? AND ?`, from, to).Scan(&refunds)
	r.db.WithContext(ctx).Raw(`SELECT COALESCE(SUM(amount_paisa), 0) FROM ledger_entries WHERE entry_type = 'promo_expense' AND created_at BETWEEN ? AND ?`, from, to).Scan(&promoExpense)
	return revenue, refunds, promoExpense, nil
}

func (r *superAdminRepository) GetVATReport(ctx context.Context, year int) ([]map[string]any, error) {
	var results []map[string]any
	err := r.db.WithContext(ctx).Raw(`
		SELECT
			to_char(date_trunc('month', b.created_at), 'YYYY-MM') AS month,
			COUNT(*) AS total_bookings,
			COALESCE(SUM(b.total_cost), 0) AS total_gmv,
			COALESCE(SUM(b.total_cost), 0) * COALESCE((SELECT value::numeric FROM platform_settings WHERE key = 'platform_fee_percent'), 10) / 100 AS total_platform_fee,
			COALESCE(SUM(b.total_cost), 0) * COALESCE((SELECT value::numeric FROM platform_settings WHERE key = 'platform_fee_percent'), 10) / 100 * 0.15 AS vat_amount
		FROM bookings b
		WHERE b.status IN ('confirmed','completed') AND EXTRACT(YEAR FROM b.created_at) = ?
		GROUP BY date_trunc('month', b.created_at)
		ORDER BY date_trunc('month', b.created_at)
	`, year).Scan(&results).Error
	return results, err
}

// ── Fraud Flags ──────────────────────────────────────────────────────────────

func (r *superAdminRepository) ListFraudFlags(ctx context.Context, status string, page, limit int) ([]entity.FraudFlag, int64, error) {
	var total int64
	q := r.db.WithContext(ctx).Model(&entity.FraudFlag{})
	if status != "" {
		q = q.Where("status = ?", status)
	}
	q.Count(&total)

	var items []entity.FraudFlag
	err := q.Order("created_at DESC").Offset((page - 1) * limit).Limit(limit).Find(&items).Error
	return items, total, err
}

func (r *superAdminRepository) CreateFraudFlag(ctx context.Context, f *entity.FraudFlag) error {
	f.ID = uuid.New()
	f.CreatedAt = time.Now()
	return r.db.WithContext(ctx).Create(f).Error
}

func (r *superAdminRepository) UpdateFraudFlag(ctx context.Context, f *entity.FraudFlag) error {
	return r.db.WithContext(ctx).Save(f).Error
}

// ── System Control ───────────────────────────────────────────────────────────

func (r *superAdminRepository) ListRateLimits(ctx context.Context) ([]entity.RateLimitConfig, error) {
	var items []entity.RateLimitConfig
	err := r.db.WithContext(ctx).Find(&items).Error
	return items, err
}

func (r *superAdminRepository) UpdateRateLimit(ctx context.Context, group string, rpm, burst int) error {
	return r.db.WithContext(ctx).Model(&entity.RateLimitConfig{}).Where("endpoint_group = ?", group).Updates(map[string]any{
		"requests_per_minute": rpm,
		"burst":               burst,
		"updated_at":          time.Now(),
	}).Error
}

func (r *superAdminRepository) ListAPIKeys(ctx context.Context, page, limit int) ([]entity.APIKey, int64, error) {
	var total int64
	r.db.WithContext(ctx).Model(&entity.APIKey{}).Count(&total)

	var items []entity.APIKey
	err := r.db.WithContext(ctx).Order("created_at DESC").Offset((page - 1) * limit).Limit(limit).Find(&items).Error
	return items, total, err
}

func (r *superAdminRepository) CreateAPIKey(ctx context.Context, k *entity.APIKey) error {
	k.ID = uuid.New()
	k.CreatedAt = time.Now()
	return r.db.WithContext(ctx).Create(k).Error
}

func (r *superAdminRepository) UpdateAPIKey(ctx context.Context, k *entity.APIKey) error {
	return r.db.WithContext(ctx).Save(k).Error
}

func (r *superAdminRepository) DeleteAPIKey(ctx context.Context, id uuid.UUID) error {
	return r.db.WithContext(ctx).Delete(&entity.APIKey{}, "id = ?", id).Error
}

// ── Zones ────────────────────────────────────────────────────────────────────

func (r *superAdminRepository) ListZones(ctx context.Context) ([]entity.Zone, error) {
	var items []entity.Zone
	err := r.db.WithContext(ctx).Preload("ZoneManager").Order("name ASC").Find(&items).Error
	return items, err
}

func (r *superAdminRepository) GetZone(ctx context.Context, id uuid.UUID) (*entity.Zone, error) {
	var z entity.Zone
	if err := r.db.WithContext(ctx).Preload("ZoneManager").First(&z, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &z, nil
}

func (r *superAdminRepository) CreateZone(ctx context.Context, z *entity.Zone) error {
	z.ID = uuid.New()
	z.CreatedAt = time.Now()
	z.UpdatedAt = time.Now()
	return r.db.WithContext(ctx).Create(z).Error
}

func (r *superAdminRepository) UpdateZone(ctx context.Context, z *entity.Zone) error {
	z.UpdatedAt = time.Now()
	return r.db.WithContext(ctx).Save(z).Error
}

// ── Organizations ────────────────────────────────────────────────────────────

func (r *superAdminRepository) ListOrganizations(ctx context.Context, page, limit int) ([]entity.Organization, int64, error) {
	var total int64
	r.db.WithContext(ctx).Model(&entity.Organization{}).Count(&total)

	var items []entity.Organization
	err := r.db.WithContext(ctx).Order("name ASC").Offset((page - 1) * limit).Limit(limit).Find(&items).Error
	return items, total, err
}

func (r *superAdminRepository) GetOrganization(ctx context.Context, id uuid.UUID) (*entity.Organization, error) {
	var o entity.Organization
	if err := r.db.WithContext(ctx).First(&o, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &o, nil
}

func (r *superAdminRepository) CreateOrganization(ctx context.Context, o *entity.Organization) error {
	o.ID = uuid.New()
	o.CreatedAt = time.Now()
	o.UpdatedAt = time.Now()
	return r.db.WithContext(ctx).Create(o).Error
}

func (r *superAdminRepository) UpdateOrganization(ctx context.Context, o *entity.Organization) error {
	o.UpdatedAt = time.Now()
	return r.db.WithContext(ctx).Save(o).Error
}

// ── Resellers ────────────────────────────────────────────────────────────────

func (r *superAdminRepository) ListResellers(ctx context.Context, page, limit int) ([]entity.Reseller, int64, error) {
	var total int64
	r.db.WithContext(ctx).Model(&entity.Reseller{}).Count(&total)

	var items []entity.Reseller
	err := r.db.WithContext(ctx).Preload("User").Order("created_at DESC").Offset((page - 1) * limit).Limit(limit).Find(&items).Error
	return items, total, err
}

func (r *superAdminRepository) GetReseller(ctx context.Context, id uuid.UUID) (*entity.Reseller, error) {
	var rs entity.Reseller
	if err := r.db.WithContext(ctx).Preload("User").First(&rs, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &rs, nil
}

func (r *superAdminRepository) CreateReseller(ctx context.Context, rs *entity.Reseller) error {
	rs.ID = uuid.New()
	rs.CreatedAt = time.Now()
	rs.UpdatedAt = time.Now()
	return r.db.WithContext(ctx).Create(rs).Error
}

func (r *superAdminRepository) UpdateReseller(ctx context.Context, rs *entity.Reseller) error {
	rs.UpdatedAt = time.Now()
	return r.db.WithContext(ctx).Save(rs).Error
}

func (r *superAdminRepository) ListUsersByRole(ctx context.Context, role string) ([]entity.User, error) {
	var users []entity.User
	err := r.db.WithContext(ctx).
		Where("role = ?", role).
		Order("created_at DESC").
		Find(&users).Error
	return users, err
}
