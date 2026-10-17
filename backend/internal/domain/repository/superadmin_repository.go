// Package repository defines interfaces for super-admin data access.
package repository

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
)

// NorthStarMetrics holds headline KPIs for super-admin dashboard.
type NorthStarMetrics struct {
	GMV              float64 `json:"gmv"`
	GMVMTD           float64 `json:"gmv_mtd"`
	NetRevenue       float64 `json:"net_revenue"`
	NetRevenueMTD    float64 `json:"net_revenue_mtd"`
	ActiveTurfs      int64   `json:"active_turfs"`
	ActivePlayers    int64   `json:"active_players"`
	TotalBookings    int64   `json:"total_bookings"`
	BookingsMTD      int64   `json:"bookings_mtd"`
}

type CohortRow struct {
	CohortMonth string    `json:"cohort_month"`
	MonthOffset int       `json:"month_offset"`
	Retained    int64     `json:"retained"`
	CohortSize  int64     `json:"cohort_size"`
}

type FunnelStep struct {
	EventType string `json:"event_type"`
	Count     int64  `json:"count"`
}

type RevenuePoint struct {
	Date    string  `json:"date"`
	Revenue float64 `json:"revenue"`
}

type SuperAdminRepository interface {
	// Business Intelligence
	GetNorthStarMetrics(ctx context.Context) (*NorthStarMetrics, error)
	GetCohortRetention(ctx context.Context, months int) ([]CohortRow, error)
	GetFunnel(ctx context.Context, from, to time.Time) ([]FunnelStep, error)
	GetRevenueTimeSeries(ctx context.Context, period string, from, to time.Time) ([]RevenuePoint, error)

	// Booking Events (analytics ingestion)
	CreateBookingEvent(ctx context.Context, e *entity.BookingEvent) error

	// Marketing Spend
	GetMarketingSpend(ctx context.Context, month time.Time) (*entity.MarketingSpend, error)
	UpsertMarketingSpend(ctx context.Context, s *entity.MarketingSpend) error

	// Audit Log
	ListAuditLog(ctx context.Context, actorID *uuid.UUID, entityType, action string, from, to *time.Time, page, limit int) ([]entity.AuditLog, int64, error)
	CreateAuditLog(ctx context.Context, log *entity.AuditLog) error

	// Ledger
	ListLedgerEntries(ctx context.Context, entryType string, from, to *time.Time, page, limit int) ([]entity.LedgerEntry, int64, error)
	CreateLedgerEntry(ctx context.Context, e *entity.LedgerEntry) error
	GetTrialBalance(ctx context.Context) (map[string]int64, error) // account -> net balance
	GetIncomeStatement(ctx context.Context, from, to time.Time) (revenue, refunds, promoExpense int64, err error)
	GetVATReport(ctx context.Context, year int) ([]map[string]interface{}, error)

	// Fraud Flags
	ListFraudFlags(ctx context.Context, status string, page, limit int) ([]entity.FraudFlag, int64, error)
	CreateFraudFlag(ctx context.Context, f *entity.FraudFlag) error
	UpdateFraudFlag(ctx context.Context, f *entity.FraudFlag) error

	// System Control
	ListRateLimits(ctx context.Context) ([]entity.RateLimitConfig, error)
	UpdateRateLimit(ctx context.Context, group string, rpm, burst int) error
	ListAPIKeys(ctx context.Context, page, limit int) ([]entity.APIKey, int64, error)
	CreateAPIKey(ctx context.Context, k *entity.APIKey) error
	UpdateAPIKey(ctx context.Context, k *entity.APIKey) error
	DeleteAPIKey(ctx context.Context, id uuid.UUID) error

	// Zones
	ListZones(ctx context.Context) ([]entity.Zone, error)
	GetZone(ctx context.Context, id uuid.UUID) (*entity.Zone, error)
	CreateZone(ctx context.Context, z *entity.Zone) error
	UpdateZone(ctx context.Context, z *entity.Zone) error

	// Organizations
	ListOrganizations(ctx context.Context, page, limit int) ([]entity.Organization, int64, error)
	GetOrganization(ctx context.Context, id uuid.UUID) (*entity.Organization, error)
	CreateOrganization(ctx context.Context, o *entity.Organization) error
	UpdateOrganization(ctx context.Context, o *entity.Organization) error

	// Resellers
	ListResellers(ctx context.Context, page, limit int) ([]entity.Reseller, int64, error)
	GetReseller(ctx context.Context, id uuid.UUID) (*entity.Reseller, error)
	CreateReseller(ctx context.Context, r *entity.Reseller) error
	UpdateReseller(ctx context.Context, r *entity.Reseller) error

	// User filtering — used by the panel's "Turf Admins" view to list every
	// user with role=manager. We could lean on the existing /admin/users
	// endpoint but it doesn't filter by role and pagination would push the
	// caller to scan the full user table.
	ListUsersByRole(ctx context.Context, role string) ([]entity.User, error)
}
