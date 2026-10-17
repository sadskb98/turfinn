package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"gorm.io/gorm"
)

var _ domain.PitchRepository = (*pitchRepository)(nil)

type pitchRepository struct {
	db    *gorm.DB
	redis *redis.Client
}

func NewPitchRepository(db *gorm.DB, redis *redis.Client) domain.PitchRepository {
	return &pitchRepository{db: db, redis: redis}
}

const pitchCacheTTL = 10 * time.Minute
const pitchListCacheTTL = 5 * time.Minute

type pitchListCache struct {
	Pitches []*entity.Pitch `json:"pitches"`
	Total   int64           `json:"total"`
}

func (r *pitchRepository) pitchListVer(ctx context.Context) string {
	v, _ := r.redis.Get(ctx, "pitch:list:ver").Result()
	if v == "" {
		return "0"
	}
	return v
}

func (r *pitchRepository) incPitchListVer(ctx context.Context) {
	r.redis.Incr(ctx, "pitch:list:ver")
}

func pitchListCacheKey(ver string, f domain.PitchFilter) string {
	lat := math.Round(f.Lat*100) / 100
	lng := math.Round(f.Lng*100) / 100
	return fmt.Sprintf("pitch:list:%s:%s:%.2f:%.2f:%.0f:%s:%d:%d",
		ver, f.City, lat, lng, f.Radius, f.Search, f.Page, f.Limit)
}

func (r *pitchRepository) Create(ctx context.Context, pitch *entity.Pitch) error {
	if err := r.db.WithContext(ctx).Create(pitch).Error; err != nil {
		return err
	}
	r.incPitchListVer(ctx)
	return nil
}

func (r *pitchRepository) FindByID(ctx context.Context, id uuid.UUID) (*entity.Pitch, error) {
	cacheKey := fmt.Sprintf("pitch:%s", id)

	cached, err := r.redis.Get(ctx, cacheKey).Result()
	if err == nil {
		var pitch entity.Pitch
		if json.Unmarshal([]byte(cached), &pitch) == nil {
			return &pitch, nil
		}
	}

	var pitch entity.Pitch
	if err := r.db.WithContext(ctx).First(&pitch, "id = ?", id).Error; err != nil {
		return nil, err
	}

	data, _ := json.Marshal(pitch)
	r.redis.Set(ctx, cacheKey, data, pitchCacheTTL)
	return &pitch, nil
}

func (r *pitchRepository) List(ctx context.Context, filter domain.PitchFilter) ([]*entity.Pitch, int64, error) {
	// Cache lookup
	ver := r.pitchListVer(ctx)
	cacheKey := pitchListCacheKey(ver, filter)
	if cached, err := r.redis.Get(ctx, cacheKey).Result(); err == nil {
		var entry pitchListCache
		if json.Unmarshal([]byte(cached), &entry) == nil {
			return entry.Pitches, entry.Total, nil
		}
	}

	query := r.db.WithContext(ctx).Model(&entity.Pitch{}).Where("is_active = true")

	if filter.City != "" {
		query = query.Where("city = ?", filter.City)
	}

	if filter.Search != "" {
		term := "%" + filter.Search + "%"
		query = query.Where("(name ILIKE ? OR address ILIKE ? OR city ILIKE ?)", term, term, term)
	}

	useDistance := filter.Lat != 0 || filter.Lng != 0
	haversine := "(6371 * acos(LEAST(1.0, cos(radians(?)) * cos(radians(latitude)) * cos(radians(longitude) - radians(?)) + sin(radians(?)) * sin(radians(latitude)))))"

	// Bounding-box pre-filter to avoid full Haversine table scan
	if useDistance && filter.Radius > 0 {
		latDelta := filter.Radius / 111.32
		lngDelta := filter.Radius / (111.32 * math.Cos(filter.Lat*math.Pi/180))
		query = query.Where(
			"latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?",
			filter.Lat-latDelta, filter.Lat+latDelta,
			filter.Lng-lngDelta, filter.Lng+lngDelta,
		)
	}

	if useDistance {
		if filter.Radius > 0 {
			query = query.Where(haversine+" <= ?", filter.Lat, filter.Lng, filter.Lat, filter.Radius)
		}
	}

	var total int64
	countQ := query.Session(&gorm.Session{})
	countQ.Count(&total)

	offset := (filter.Page - 1) * filter.Limit
	q := query
	if useDistance {
		priorityExpr := fmt.Sprintf("CASE WHEN service_radius_km IS NOT NULL AND %s <= service_radius_km THEN 0 ELSE 1 END", haversine)
		q = q.Order(gorm.Expr(priorityExpr+" ASC, "+haversine+" ASC", filter.Lat, filter.Lng, filter.Lat, filter.Lat, filter.Lng, filter.Lat))
	} else {
		q = q.Order("created_at DESC")
	}

	var pitches []*entity.Pitch
	if err := q.Offset(offset).Limit(filter.Limit).Find(&pitches).Error; err != nil {
		return nil, 0, err
	}

	// Store result in cache
	if data, err := json.Marshal(pitchListCache{Pitches: pitches, Total: total}); err == nil {
		r.redis.Set(ctx, cacheKey, data, pitchListCacheTTL)
	}

	return pitches, total, nil
}

func (r *pitchRepository) Update(ctx context.Context, pitch *entity.Pitch) error {
	if err := r.db.WithContext(ctx).Save(pitch).Error; err != nil {
		return err
	}
	r.redis.Del(ctx, fmt.Sprintf("pitch:%s", pitch.ID))
	r.incPitchListVer(ctx)
	return nil
}

func (r *pitchRepository) Delete(ctx context.Context, id uuid.UUID) error {
	if err := r.db.WithContext(ctx).Delete(&entity.Pitch{}, "id = ?", id).Error; err != nil {
		return err
	}
	r.redis.Del(ctx, fmt.Sprintf("pitch:%s", id))
	r.incPitchListVer(ctx)
	return nil
}

func (r *pitchRepository) ListByOwner(ctx context.Context, ownerID uuid.UUID) ([]*entity.Pitch, error) {
	var pitches []*entity.Pitch
	err := r.db.WithContext(ctx).Where("owner_id = ?", ownerID).Order("created_at DESC").Find(&pitches).Error
	return pitches, err
}

func (r *pitchRepository) ListAll(ctx context.Context, page, limit int) ([]*entity.Pitch, int64, error) {
	var total int64
	r.db.WithContext(ctx).Model(&entity.Pitch{}).Count(&total)

	var pitches []*entity.Pitch
	err := r.db.WithContext(ctx).Order("created_at DESC").
		Offset((page - 1) * limit).Limit(limit).
		Find(&pitches).Error
	return pitches, total, err
}

func (r *pitchRepository) Count(ctx context.Context) (int64, error) {
	var count int64
	err := r.db.WithContext(ctx).Model(&entity.Pitch{}).Where("is_active = true").Count(&count).Error
	return count, err
}

func (r *pitchRepository) FindBookingsInRange(ctx context.Context, pitchID uuid.UUID, from, to time.Time) ([]*entity.Booking, error) {
	var bookings []*entity.Booking
	err := r.db.WithContext(ctx).
		Where("pitch_id = ? AND starts_at < ? AND ends_at > ? AND status IN ('pending', 'confirmed')", pitchID, to, from).
		Find(&bookings).Error
	return bookings, err
}
