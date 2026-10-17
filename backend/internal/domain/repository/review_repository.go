package repository

import (
	"context"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
)

type ReviewRepository interface {
	Create(ctx context.Context, review *entity.Review) error
	ListByPitch(ctx context.Context, pitchID uuid.UUID, limit, offset int) ([]entity.Review, int64, error)
	GetAverageRating(ctx context.Context, pitchID uuid.UUID) (float64, error)
}
