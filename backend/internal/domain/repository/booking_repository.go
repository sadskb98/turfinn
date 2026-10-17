package repository

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
)

type BookingFilter struct {
	PitchID *uuid.UUID
	UserID  *uuid.UUID
	Status  string
	Page    int
	Limit   int
}

type BookingRepository interface {
	Create(ctx context.Context, booking *entity.Booking) error
	FindByID(ctx context.Context, id uuid.UUID) (*entity.Booking, error)
	ListByUser(ctx context.Context, userID uuid.UUID, page, limit int) ([]*entity.Booking, int64, error)
	ListByPitch(ctx context.Context, pitchID uuid.UUID, page, limit int) ([]*entity.Booking, int64, error)
	ListAll(ctx context.Context, filter BookingFilter) ([]*entity.Booking, int64, error)
	FindConflicts(ctx context.Context, pitchID uuid.UUID, start, end time.Time) ([]*entity.Booking, error)
	UpdateStatus(ctx context.Context, id uuid.UUID, status entity.BookingStatus) error
	Count(ctx context.Context) (int64, error)
	Revenue(ctx context.Context, pitchIDs []uuid.UUID) (float64, error)
	ListByPitches(ctx context.Context, pitchIDs []uuid.UUID, page, limit int) ([]*entity.Booking, int64, error)
}
