package service

import (
	"testing"

	"github.com/turfinn/backend/internal/interfaces/dto"
)

func TestFillHeatmapGrid(t *testing.T) {
	raw := []dto.HourlyBookingCount{
		{DayOfWeek: 1, Hour: 18, Count: 5, Revenue: 2500},
		{DayOfWeek: 5, Hour: 20, Count: 8, Revenue: 4000},
	}
	grid := FillHeatmapGrid(raw)
	if len(grid) != 112 {
		t.Fatalf("expected 112 cells, got %d", len(grid))
	}
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
