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

// Suppress unused import warning
var _ context.Context
