package repository

import (
	"context"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
)

type ExternalPitchRepository interface {
	// FindOrCreate matches by normalized_name within a small geo radius.
	// Increments ref_count on existing rows, creates new on miss.
	FindOrCreate(ctx context.Context, p *entity.ExternalPitch) (*entity.ExternalPitch, error)
	Search(ctx context.Context, query string, lat, lng float64, limit int) ([]entity.ExternalPitch, error)
	FindByID(ctx context.Context, id uuid.UUID) (*entity.ExternalPitch, error)
}

type MatchReportRepository interface {
	Create(ctx context.Context, r *entity.MatchReport) error
	CountForPost(ctx context.Context, matchPostID uuid.UUID) (int64, error)
}

type MatchCancellationRepository interface {
	Create(ctx context.Context, c *entity.MatchCancellation) error
	CountLateForUser(ctx context.Context, userID uuid.UUID, withinDays int) (int64, error)
}
