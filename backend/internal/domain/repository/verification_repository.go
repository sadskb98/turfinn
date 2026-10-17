// Package repository defines interfaces for turf onboarding & verification.
package repository

import (
	"context"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
)

type VerificationRepository interface {
	// KYC
	ListKYC(ctx context.Context, status string, page, limit int) ([]entity.ManagerKYC, int64, error)
	GetKYC(ctx context.Context, id uuid.UUID) (*entity.ManagerKYC, error)
	GetKYCByUser(ctx context.Context, userID uuid.UUID) (*entity.ManagerKYC, error)
	CreateKYC(ctx context.Context, k *entity.ManagerKYC) error
	UpdateKYC(ctx context.Context, k *entity.ManagerKYC) error

	// Reviews
	ListFlaggedReviews(ctx context.Context, page, limit int) ([]entity.Review, int64, error)
	ListReviewsByPitch(ctx context.Context, pitchID uuid.UUID, page, limit int) ([]entity.Review, int64, error)
	GetReview(ctx context.Context, id uuid.UUID) (*entity.Review, error)
	CreateReview(ctx context.Context, r *entity.Review) error
	UpdateReview(ctx context.Context, r *entity.Review) error
	PitchAvgRating(ctx context.Context, pitchID uuid.UUID) (float64, int64, error)
}
