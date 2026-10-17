package repository

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"gorm.io/gorm"
)

type reviewRepository struct {
	db    *gorm.DB
	redis *redis.Client
}

func NewReviewRepository(db *gorm.DB, redis *redis.Client) domain.ReviewRepository {
	return &reviewRepository{db: db, redis: redis}
}

func (r *reviewRepository) Create(ctx context.Context, review *entity.Review) error {
	if err := r.db.WithContext(ctx).Create(review).Error; err != nil {
		return err
	}
	// Invalidate cached average rating for this pitch
	r.redis.Del(ctx, fmt.Sprintf("avg_rating:%s", review.PitchID))
	return nil
}

func (r *reviewRepository) ListByPitch(ctx context.Context, pitchID uuid.UUID, limit, offset int) ([]entity.Review, int64, error) {
	var total int64
	var reviews []entity.Review

	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&entity.Review{}).Where("pitch_id = ?", pitchID).Count(&total).Error; err != nil {
			return err
		}
		return tx.Where("pitch_id = ?", pitchID).Order("created_at DESC").Limit(limit).Offset(offset).Find(&reviews).Error
	})
	return reviews, total, err
}

func (r *reviewRepository) GetAverageRating(ctx context.Context, pitchID uuid.UUID) (float64, error) {
	cacheKey := fmt.Sprintf("avg_rating:%s", pitchID)

	// 1. Try Redis cache
	cached, err := r.redis.Get(ctx, cacheKey).Result()
	if err == nil {
		avg, parseErr := strconv.ParseFloat(cached, 64)
		if parseErr == nil {
			return avg, nil
		}
	}

	// 2. Fallback to Postgres
	var avg float64
	row := r.db.WithContext(ctx).
		Model(&entity.Review{}).
		Select("COALESCE(AVG(rating), 0)").
		Where("pitch_id = ?", pitchID).
		Row()
	if err := row.Scan(&avg); err != nil {
		return 0, err
	}

	// 3. Cache with explicit TTL of 5 minutes
	r.redis.Set(ctx, cacheKey, strconv.FormatFloat(avg, 'f', -1, 64), 5*time.Minute)

	return avg, nil
}
