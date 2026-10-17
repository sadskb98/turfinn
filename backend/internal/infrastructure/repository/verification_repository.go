// Package repository provides GORM implementations for verification & reviews.
package repository

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"gorm.io/gorm"
)

type verificationRepository struct {
	db    *gorm.DB
	redis *redis.Client
}

func NewVerificationRepository(db *gorm.DB, redis *redis.Client) domain.VerificationRepository {
	return &verificationRepository{db: db, redis: redis}
}

// ── KYC ──────────────────────────────────────────────────────────────────────

func (r *verificationRepository) ListKYC(ctx context.Context, status string, page, limit int) ([]entity.ManagerKYC, int64, error) {
	var total int64
	q := r.db.WithContext(ctx).Model(&entity.ManagerKYC{})
	if status != "" {
		q = q.Where("status = ?", status)
	}
	q.Count(&total)

	var items []entity.ManagerKYC
	err := q.Preload("User").Order("created_at DESC").Offset((page - 1) * limit).Limit(limit).Find(&items).Error
	return items, total, err
}

func (r *verificationRepository) GetKYC(ctx context.Context, id uuid.UUID) (*entity.ManagerKYC, error) {
	var k entity.ManagerKYC
	if err := r.db.WithContext(ctx).Preload("User").First(&k, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &k, nil
}

func (r *verificationRepository) GetKYCByUser(ctx context.Context, userID uuid.UUID) (*entity.ManagerKYC, error) {
	var k entity.ManagerKYC
	if err := r.db.WithContext(ctx).Where("user_id = ?", userID).First(&k).Error; err != nil {
		return nil, err
	}
	return &k, nil
}

func (r *verificationRepository) CreateKYC(ctx context.Context, k *entity.ManagerKYC) error {
	k.ID = uuid.New()
	k.CreatedAt = time.Now()
	k.UpdatedAt = time.Now()
	return r.db.WithContext(ctx).Create(k).Error
}

func (r *verificationRepository) UpdateKYC(ctx context.Context, k *entity.ManagerKYC) error {
	k.UpdatedAt = time.Now()
	return r.db.WithContext(ctx).Save(k).Error
}

// ── Reviews ──────────────────────────────────────────────────────────────────

func (r *verificationRepository) ListFlaggedReviews(ctx context.Context, page, limit int) ([]entity.Review, int64, error) {
	var total int64
	r.db.WithContext(ctx).Model(&entity.Review{}).Where("status = 'flagged'").Count(&total)

	var items []entity.Review
	err := r.db.WithContext(ctx).Preload("User").Preload("Pitch").Where("status = 'flagged'").
		Order("created_at DESC").Offset((page - 1) * limit).Limit(limit).Find(&items).Error
	return items, total, err
}

func (r *verificationRepository) ListReviewsByPitch(ctx context.Context, pitchID uuid.UUID, page, limit int) ([]entity.Review, int64, error) {
	var total int64
	r.db.WithContext(ctx).Model(&entity.Review{}).Where("pitch_id = ? AND status = 'active'", pitchID).Count(&total)

	var items []entity.Review
	err := r.db.WithContext(ctx).Preload("User").Where("pitch_id = ? AND status = 'active'", pitchID).
		Order("created_at DESC").Offset((page - 1) * limit).Limit(limit).Find(&items).Error
	return items, total, err
}

func (r *verificationRepository) GetReview(ctx context.Context, id uuid.UUID) (*entity.Review, error) {
	var rv entity.Review
	if err := r.db.WithContext(ctx).Preload("User").Preload("Pitch").First(&rv, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &rv, nil
}

func (r *verificationRepository) CreateReview(ctx context.Context, rv *entity.Review) error {
	rv.ID = uuid.New()
	rv.CreatedAt = time.Now()
	rv.UpdatedAt = time.Now()
	return r.db.WithContext(ctx).Create(rv).Error
}

func (r *verificationRepository) UpdateReview(ctx context.Context, rv *entity.Review) error {
	rv.UpdatedAt = time.Now()
	return r.db.WithContext(ctx).Save(rv).Error
}

func (r *verificationRepository) PitchAvgRating(ctx context.Context, pitchID uuid.UUID) (float64, int64, error) {
	var result struct {
		Avg   float64
		Count int64
	}
	err := r.db.WithContext(ctx).Model(&entity.Review{}).
		Select("COALESCE(AVG(rating), 0) as avg, COUNT(*) as count").
		Where("pitch_id = ? AND status = 'active'", pitchID).
		Scan(&result).Error
	return result.Avg, result.Count, err
}
