package repository

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
)

type PitchFilter struct {
	City   string
	Search string
	Lat    float64
	Lng    float64
	Radius float64 // max distance in km, 0 = no limit
	Page   int
	Limit  int
}

type PitchRepository interface {
	Create(ctx context.Context, pitch *entity.Pitch) error
	FindByID(ctx context.Context, id uuid.UUID) (*entity.Pitch, error)
	List(ctx context.Context, filter PitchFilter) ([]*entity.Pitch, int64, error)
	ListByOwner(ctx context.Context, ownerID uuid.UUID) ([]*entity.Pitch, error)
	ListAll(ctx context.Context, page, limit int) ([]*entity.Pitch, int64, error)
	Update(ctx context.Context, pitch *entity.Pitch) error
	Delete(ctx context.Context, id uuid.UUID) error
	Count(ctx context.Context) (int64, error)
	FindBookingsInRange(ctx context.Context, pitchID uuid.UUID, from, to time.Time) ([]*entity.Booking, error)
}
