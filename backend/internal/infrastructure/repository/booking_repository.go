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

const bookingListCacheTTL = 2 * time.Minute

type bookingRepository struct {
	db    *gorm.DB
	redis *redis.Client
}

func NewBookingRepository(db *gorm.DB, redis *redis.Client) domain.BookingRepository {
	return &bookingRepository{db: db, redis: redis}
}

func (r *bookingRepository) Create(ctx context.Context, booking *entity.Booking) error {
	if err := r.db.WithContext(ctx).Create(booking).Error; err != nil {
		return err
	}
	r.redis.Del(ctx, fmt.Sprintf("booking:user:%s:p1:l20", booking.UserID))
	return nil
}

func (r *bookingRepository) FindByID(ctx context.Context, id uuid.UUID) (*entity.Booking, error) {
	var booking entity.Booking
	err := r.db.WithContext(ctx).
		Preload("Pitch").Preload("User").
		First(&booking, "id = ?", id).Error
	return &booking, err
}

type bookingListCache struct {
	Bookings []*entity.Booking
	Total    int64
}

func (r *bookingRepository) ListByUser(ctx context.Context, userID uuid.UUID, page, limit int) ([]*entity.Booking, int64, error) {
	cacheKey := fmt.Sprintf("booking:user:%s:p%d:l%d", userID, page, limit)
	if cached, err := r.redis.Get(ctx, cacheKey).Bytes(); err == nil {
		var result bookingListCache
		if json.Unmarshal(cached, &result) == nil {
			return result.Bookings, result.Total, nil
		}
	}

	var total int64
	r.db.WithContext(ctx).Model(&entity.Booking{}).Where("user_id = ?", userID).Count(&total)

	var bookings []*entity.Booking
	err := r.db.WithContext(ctx).
		Preload("Pitch").
		Where("user_id = ?", userID).
		Order("starts_at DESC").
		Offset((page - 1) * limit).Limit(limit).
		Find(&bookings).Error
	if err != nil {
		return bookings, total, err
	}

	if data, merr := json.Marshal(bookingListCache{Bookings: bookings, Total: total}); merr == nil {
		r.redis.Set(ctx, cacheKey, data, bookingListCacheTTL)
	}
	return bookings, total, nil
}

type pitchBookingListCache struct {
	Bookings []*entity.Booking
	Total    int64
}

func (r *bookingRepository) ListByPitch(ctx context.Context, pitchID uuid.UUID, page, limit int) ([]*entity.Booking, int64, error) {
	cacheKey := fmt.Sprintf("booking:pitch:%s:p%d:l%d", pitchID, page, limit)
	if cached, err := r.redis.Get(ctx, cacheKey).Bytes(); err == nil {
		var result pitchBookingListCache
		if json.Unmarshal(cached, &result) == nil {
			return result.Bookings, result.Total, nil
		}
	}

	var total int64
	r.db.WithContext(ctx).Model(&entity.Booking{}).Where("pitch_id = ?", pitchID).Count(&total)

	var bookings []*entity.Booking
	err := r.db.WithContext(ctx).
		Preload("User").
		Where("pitch_id = ?", pitchID).
		Order("starts_at DESC").
		Offset((page - 1) * limit).Limit(limit).
		Find(&bookings).Error
	if err != nil {
		return bookings, total, err
	}

	if data, merr := json.Marshal(pitchBookingListCache{Bookings: bookings, Total: total}); merr == nil {
		r.redis.Set(ctx, cacheKey, data, bookingListCacheTTL)
	}
	return bookings, total, nil
}

func (r *bookingRepository) FindConflicts(ctx context.Context, pitchID uuid.UUID, start, end time.Time) ([]*entity.Booking, error) {
	var bookings []*entity.Booking
	// Exclude cancelled bookings and pending bookings whose payment was
	// abandoned (payment_order exists with failed/cancelled status) so that
	// closing the browser without paying frees the slot.
	deadPaymentIDs := r.db.Model(&entity.PaymentOrder{}).
		Select("booking_id").
		Where("status IN ?", []string{entity.PaymentStatusFailed, entity.PaymentStatusCancelled})
	err := r.db.WithContext(ctx).
		Where("pitch_id = ? AND starts_at < ? AND ends_at > ?", pitchID, end, start).
		Where("status NOT IN ?", []entity.BookingStatus{entity.BookingCancelled}).
		Not("id IN (?)", deadPaymentIDs).
		Find(&bookings).Error
	return bookings, err
}

func (r *bookingRepository) UpdateStatus(ctx context.Context, id uuid.UUID, status entity.BookingStatus) error {
	return r.db.WithContext(ctx).
		Model(&entity.Booking{}).
		Where("id = ?", id).
		Update("status", status).Error
}

func (r *bookingRepository) ListAll(ctx context.Context, filter domain.BookingFilter) ([]*entity.Booking, int64, error) {
	query := r.db.WithContext(ctx).Model(&entity.Booking{})
	if filter.PitchID != nil {
		query = query.Where("pitch_id = ?", *filter.PitchID)
	}
	if filter.UserID != nil {
		query = query.Where("user_id = ?", *filter.UserID)
	}
	if filter.Status != "" {
		query = query.Where("status = ?", filter.Status)
	}
	var total int64
	query.Count(&total)

	if filter.Page < 1 {
		filter.Page = 1
	}
	if filter.Limit < 1 || filter.Limit > 100 {
		filter.Limit = 20
	}
	var bookings []*entity.Booking
	err := query.Preload("Pitch").Preload("User").
		Order("starts_at DESC").
		Offset((filter.Page-1)*filter.Limit).Limit(filter.Limit).
		Find(&bookings).Error
	return bookings, total, err
}

func (r *bookingRepository) Count(ctx context.Context) (int64, error) {
	var count int64
	err := r.db.WithContext(ctx).Model(&entity.Booking{}).Count(&count).Error
	return count, err
}

func (r *bookingRepository) Revenue(ctx context.Context, pitchIDs []uuid.UUID) (float64, error) {
	var total float64
	query := r.db.WithContext(ctx).Model(&entity.Booking{}).
		Where("status IN ?", []entity.BookingStatus{entity.BookingConfirmed, entity.BookingCompleted})
	if len(pitchIDs) > 0 {
		query = query.Where("pitch_id IN ?", pitchIDs)
	}
	err := query.Select("COALESCE(SUM(total_cost), 0)").Scan(&total).Error
	return total, err
}

func (r *bookingRepository) ListByPitches(ctx context.Context, pitchIDs []uuid.UUID, page, limit int) ([]*entity.Booking, int64, error) {
	var total int64
	base := r.db.WithContext(ctx).Model(&entity.Booking{}).Where("pitch_id IN ?", pitchIDs)
	base.Count(&total)

	var bookings []*entity.Booking
	err := r.db.WithContext(ctx).Preload("Pitch").Preload("User").
		Where("pitch_id IN ?", pitchIDs).
		Order("starts_at DESC").
		Offset((page-1)*limit).Limit(limit).
		Find(&bookings).Error
	return bookings, total, err
}
