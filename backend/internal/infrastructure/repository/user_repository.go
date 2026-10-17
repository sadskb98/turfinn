package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"gorm.io/gorm"
)

type userRepository struct {
	db    *gorm.DB
	redis *redis.Client
}

func NewUserRepository(db *gorm.DB, redis *redis.Client) domain.UserRepository {
	return &userRepository{db: db, redis: redis}
}

const userCacheTTL = 15 * time.Minute

func (r *userRepository) Create(ctx context.Context, user *entity.User) error {
	return r.db.WithContext(ctx).Create(user).Error
}

func (r *userRepository) FindByID(ctx context.Context, id uuid.UUID) (*entity.User, error) {
	cacheKey := fmt.Sprintf("user:%s", id)

	cached, err := r.redis.Get(ctx, cacheKey).Result()
	if err == nil {
		var user entity.User
		if json.Unmarshal([]byte(cached), &user) == nil {
			return &user, nil
		}
	}

	var user entity.User
	if err := r.db.WithContext(ctx).First(&user, "id = ?", id).Error; err != nil {
		return nil, err
	}

	data, _ := json.Marshal(user)
	r.redis.Set(ctx, cacheKey, data, userCacheTTL)
	return &user, nil
}

func (r *userRepository) FindByPhone(ctx context.Context, phone string) (*entity.User, error) {
	var user entity.User
	if err := r.db.WithContext(ctx).Where("phone = ?", phone).First(&user).Error; err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *userRepository) FindByEmail(ctx context.Context, email string) (*entity.User, error) {
	var user entity.User
	if err := r.db.WithContext(ctx).Where("email = ?", email).First(&user).Error; err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *userRepository) FindByGoogleID(ctx context.Context, googleID string) (*entity.User, error) {
	var user entity.User
	if err := r.db.WithContext(ctx).Where("google_id = ?", googleID).First(&user).Error; err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *userRepository) Update(ctx context.Context, user *entity.User) error {
	if err := r.db.WithContext(ctx).Save(user).Error; err != nil {
		return err
	}
	r.redis.Del(ctx, fmt.Sprintf("user:%s", user.ID))
	return nil
}

func (r *userRepository) Delete(ctx context.Context, id uuid.UUID) error {
	if err := r.db.WithContext(ctx).Delete(&entity.User{}, "id = ?", id).Error; err != nil {
		return err
	}
	r.redis.Del(ctx, fmt.Sprintf("user:%s", id))
	return nil
}

func (r *userRepository) UpdateFCMToken(ctx context.Context, userID uuid.UUID, token string) error {
	now := time.Now()
	err := r.db.WithContext(ctx).Model(&entity.User{}).
		Where("id = ?", userID).
		Updates(map[string]any{
			"fcm_token":            token,
			"fcm_token_updated_at": now,
		}).Error
	if err != nil {
		return err
	}
	r.redis.Del(ctx, fmt.Sprintf("user:%s", userID))
	return nil
}

func (r *userRepository) List(ctx context.Context, filter domain.UserFilter) ([]*entity.User, int64, error) {
	query := r.db.WithContext(ctx).Model(&entity.User{})
	if filter.Search != "" {
		query = query.Where("name ILIKE ? OR phone ILIKE ?", "%"+filter.Search+"%", "%"+filter.Search+"%")
	}
	if filter.Role != "" {
		query = query.Where("role = ?", filter.Role)
	}

	var total int64
	query.Count(&total)

	if filter.Page < 1 {
		filter.Page = 1
	}
	if filter.Limit < 1 || filter.Limit > 100 {
		filter.Limit = 20
	}

	var users []*entity.User
	err := query.Order("created_at DESC").
		Offset((filter.Page - 1) * filter.Limit).Limit(filter.Limit).
		Find(&users).Error
	return users, total, err
}

func (r *userRepository) Count(ctx context.Context) (int64, error) {
	var count int64
	err := r.db.WithContext(ctx).Model(&entity.User{}).Count(&count).Error
	return count, err
}
