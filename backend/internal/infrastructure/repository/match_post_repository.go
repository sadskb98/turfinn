package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"gorm.io/gorm"

	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
)

const feedListCacheTTL = 5 * time.Minute

type matchPostRepository struct {
	db    *gorm.DB
	redis *redis.Client
}

func NewMatchPostRepository(db *gorm.DB, redis *redis.Client) domain.MatchPostRepository {
	return &matchPostRepository{db: db, redis: redis}
}

func (r *matchPostRepository) Create(ctx context.Context, post *entity.MatchPost) error {
	if err := r.db.WithContext(ctx).Create(post).Error; err != nil {
		return err
	}
	r.redis.Del(ctx, "feed:list:p1:l20")
	return nil
}

type feedListCache struct {
	Posts []entity.MatchPost
	Total int64
}

func (r *matchPostRepository) List(ctx context.Context, f domain.MatchPostFilter) ([]entity.MatchPost, int64, error) {
	useGeo := f.Lat != 0 || f.Lng != 0
	// Only cache non-geo requests (geo varies per user location)
	var cacheKey string
	if !useGeo && f.PostType == "" {
		cacheKey = fmt.Sprintf("feed:list:p%d:l%d", f.Page, f.Limit)
		if cached, err := r.redis.Get(ctx, cacheKey).Bytes(); err == nil {
			var result feedListCache
			if json.Unmarshal(cached, &result) == nil {
				return result.Posts, result.Total, nil
			}
		}
	}

	// Open feed: status open + still has spots + match hasn't started yet.
	// Once filled or kicked off, the post drops off the discovery list — it
	// stays accessible via /feed/:id and the joiner's "My matches" view.
	q := r.db.WithContext(ctx).Model(&entity.MatchPost{}).
		Where("status = 'open'").
		Where("spots_filled < spots_total").
		Where("match_date > NOW()")

	if f.PostType != "" {
		q = q.Where("post_type = ?", f.PostType)
	}

	if useGeo && f.Radius > 0 {
		latDelta := f.Radius / 111.32
		lngDelta := f.Radius / (111.32 * math.Cos(f.Lat*math.Pi/180))
		q = q.Where("latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?",
			f.Lat-latDelta, f.Lat+latDelta,
			f.Lng-lngDelta, f.Lng+lngDelta)
	}

	var total int64
	if err := q.Session(&gorm.Session{}).Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var posts []entity.MatchPost
	offset := (f.Page - 1) * f.Limit

	orderClause := "match_date ASC"
	if useGeo && f.Radius > 0 {
		orderClause = fmt.Sprintf(
			`(6371 * acos(cos(radians(%f)) * cos(radians(latitude)) * cos(radians(longitude) - radians(%f)) + sin(radians(%f)) * sin(radians(latitude)))) ASC`,
			f.Lat, f.Lng, f.Lat,
		)
	}

	if err := q.Session(&gorm.Session{}).
		Preload("Author").Preload("Pitch").
		Order(orderClause).
		Offset(offset).Limit(f.Limit).
		Find(&posts).Error; err != nil {
		return nil, 0, err
	}

	if cacheKey != "" {
		if data, merr := json.Marshal(feedListCache{Posts: posts, Total: total}); merr == nil {
			r.redis.Set(ctx, cacheKey, data, feedListCacheTTL)
		}
	}
	return posts, total, nil
}

func (r *matchPostRepository) FindByID(ctx context.Context, id uuid.UUID) (*entity.MatchPost, error) {
	var post entity.MatchPost
	if err := r.db.WithContext(ctx).Preload("Author").Preload("Pitch").
		First(&post, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &post, nil
}

func (r *matchPostRepository) JoinPost(ctx context.Context, id uuid.UUID, userID uuid.UUID) error {
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		result := tx.Model(&entity.MatchPost{}).
			Where("id = ? AND status = 'open' AND spots_filled < spots_total", id).
			Update("spots_filled", gorm.Expr("spots_filled + 1"))
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected == 0 {
			return fmt.Errorf("match is full or not available")
		}
		join := entity.MatchPostJoin{PostID: id, UserID: userID}
		return tx.Create(&join).Error
	})
	if err != nil {
		return err
	}
	r.redis.Del(ctx, "feed:list:p1:l20")
	return nil
}

func (r *matchPostRepository) LeavePost(ctx context.Context, id uuid.UUID, userID uuid.UUID) error {
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		res := tx.Where("post_id = ? AND user_id = ?", id, userID).
			Delete(&entity.MatchPostJoin{})
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected == 0 {
			return fmt.Errorf("user has not joined this match")
		}
		// GREATEST guards against a stale spots_filled going negative.
		return tx.Model(&entity.MatchPost{}).
			Where("id = ?", id).
			Update("spots_filled", gorm.Expr("GREATEST(spots_filled - 1, 0)")).Error
	})
	if err != nil {
		return err
	}
	r.redis.Del(ctx, "feed:list:p1:l20")
	return nil
}

func (r *matchPostRepository) Delete(ctx context.Context, id uuid.UUID) error {
	return r.db.WithContext(ctx).Delete(&entity.MatchPost{}, "id = ?", id).Error
}

func (r *matchPostRepository) JoinedPostIDs(
	ctx context.Context,
	userID uuid.UUID,
	postIDs []uuid.UUID,
) (map[uuid.UUID]bool, error) {
	out := make(map[uuid.UUID]bool, len(postIDs))
	if len(postIDs) == 0 {
		return out, nil
	}
	var rows []struct {
		PostID uuid.UUID
	}
	err := r.db.WithContext(ctx).
		Model(&entity.MatchPostJoin{}).
		Select("post_id").
		Where("user_id = ? AND post_id IN ?", userID, postIDs).
		Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	for _, r := range rows {
		out[r.PostID] = true
	}
	return out, nil
}

// ListMine returns posts the user authored OR joined, filtered by scope.
// Hosted + joined are unioned via two queries because GORM's join-with-OR
// fights the Preload eager-loading we want for the response shape.
func (r *matchPostRepository) ListMine(
	ctx context.Context,
	userID uuid.UUID,
	scope string,
	page, limit int,
) ([]entity.MatchPost, int64, error) {
	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 50 {
		limit = 20
	}

	q := r.db.WithContext(ctx).Model(&entity.MatchPost{})

	switch scope {
	case "hosted":
		q = q.Where("author_id = ?", userID)
	case "joined":
		q = q.Where("id IN (?)",
			r.db.Model(&entity.MatchPostJoin{}).
				Select("post_id").
				Where("user_id = ?", userID))
	default:
		q = q.Where("author_id = ? OR id IN (?)",
			userID,
			r.db.Model(&entity.MatchPostJoin{}).
				Select("post_id").
				Where("user_id = ?", userID))
	}

	switch scope {
	case "upcoming":
		q = q.Where("match_date > NOW()")
	case "past":
		q = q.Where("match_date <= NOW()")
	}

	var total int64
	if err := q.Session(&gorm.Session{}).Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var posts []entity.MatchPost
	if err := q.Session(&gorm.Session{}).
		Preload("Author").Preload("Pitch").
		Order("match_date DESC").
		Offset((page - 1) * limit).Limit(limit).
		Find(&posts).Error; err != nil {
		return nil, 0, err
	}
	return posts, total, nil
}

// FindNearbyUserIDs returns IDs of users whose last known location is within radius km.
func (r *matchPostRepository) FindNearbyUserIDs(ctx context.Context, lat, lng, radius float64) ([]uuid.UUID, error) {
	latDelta := radius / 111.32
	lngDelta := radius / (111.32 * math.Cos(lat*math.Pi/180))

	var ids []uuid.UUID
	err := r.db.WithContext(ctx).Model(&entity.User{}).
		Select("id").
		Where(`
            last_lat IS NOT NULL AND last_lng IS NOT NULL
            AND last_lat  BETWEEN ? AND ?
            AND last_lng  BETWEEN ? AND ?
            AND fcm_token IS NOT NULL AND fcm_token != ''
            AND location_updated_at > NOW() - INTERVAL '24 hours'
        `, lat-latDelta, lat+latDelta, lng-lngDelta, lng+lngDelta).
		Scan(&ids).Error
	return ids, err
}
