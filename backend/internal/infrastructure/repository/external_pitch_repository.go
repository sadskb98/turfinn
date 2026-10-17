package repository

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
)

// ── ExternalPitchRepository ─────────────────────────────────────────────────

type externalPitchRepository struct {
	db *gorm.DB
}

func NewExternalPitchRepository(db *gorm.DB) domain.ExternalPitchRepository {
	return &externalPitchRepository{db: db}
}

// normalizePitchName: lowercase, collapse whitespace, strip common suffixes.
// Conservative — better to over-merge "GreenField" with "GreenField Turf" than
// to fragment counts across spelling variations.
func normalizePitchName(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	for _, suffix := range []string{" turf", " arena", " ground", " field", " fc", " sports club"} {
		s = strings.TrimSuffix(s, suffix)
	}
	return strings.Join(strings.Fields(s), " ")
}

// approxDistanceKm — rough box-distance for dedupe, ~111km per degree lat.
func approxBoxOverlap(lat1, lng1, lat2, lng2, km float64) bool {
	deg := km / 111.0
	return abs(lat1-lat2) <= deg && abs(lng1-lng2) <= deg
}

func abs(f float64) float64 {
	if f < 0 {
		return -f
	}
	return f
}

func (r *externalPitchRepository) FindOrCreate(ctx context.Context, p *entity.ExternalPitch) (*entity.ExternalPitch, error) {
	p.NormalizedName = normalizePitchName(p.Name)
	if p.NormalizedName == "" {
		return nil, errors.New("name required")
	}

	// Look for existing rows with same normalized_name within ~500m.
	var candidates []entity.ExternalPitch
	if err := r.db.WithContext(ctx).
		Where("normalized_name = ?", p.NormalizedName).
		Limit(20).Find(&candidates).Error; err != nil {
		return nil, err
	}
	for _, c := range candidates {
		if approxBoxOverlap(c.Latitude, c.Longitude, p.Latitude, p.Longitude, 0.5) {
			// Hit — bump ref_count, return existing.
			if err := r.db.WithContext(ctx).Model(&c).
				UpdateColumn("ref_count", gorm.Expr("ref_count + 1")).Error; err != nil {
				return nil, err
			}
			c.RefCount++
			return &c, nil
		}
	}

	// Miss — create.
	p.RefCount = 1
	p.CreatedAt = time.Now()
	p.UpdatedAt = time.Now()
	if err := r.db.WithContext(ctx).Create(p).Error; err != nil {
		return nil, err
	}
	return p, nil
}

func (r *externalPitchRepository) Search(ctx context.Context, query string, lat, lng float64, limit int) ([]entity.ExternalPitch, error) {
	if limit <= 0 || limit > 50 {
		limit = 10
	}
	q := r.db.WithContext(ctx).Model(&entity.ExternalPitch{})
	if query != "" {
		like := "%" + strings.ToLower(query) + "%"
		q = q.Where("LOWER(name) LIKE ? OR normalized_name LIKE ?", like, like)
	}
	// Order: verified pitches first, then by ref_count.
	var items []entity.ExternalPitch
	if err := q.Order("verified DESC, ref_count DESC").
		Limit(limit).Find(&items).Error; err != nil {
		return nil, err
	}
	return items, nil
}

func (r *externalPitchRepository) FindByID(ctx context.Context, id uuid.UUID) (*entity.ExternalPitch, error) {
	var p entity.ExternalPitch
	if err := r.db.WithContext(ctx).First(&p, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &p, nil
}

// ── MatchReportRepository ───────────────────────────────────────────────────

type matchReportRepository struct {
	db *gorm.DB
}

func NewMatchReportRepository(db *gorm.DB) domain.MatchReportRepository {
	return &matchReportRepository{db: db}
}

func (r *matchReportRepository) Create(ctx context.Context, mr *entity.MatchReport) error {
	mr.CreatedAt = time.Now()
	return r.db.WithContext(ctx).Create(mr).Error
}

func (r *matchReportRepository) CountForPost(ctx context.Context, postID uuid.UUID) (int64, error) {
	var n int64
	err := r.db.WithContext(ctx).Model(&entity.MatchReport{}).
		Where("match_post_id = ?", postID).Count(&n).Error
	return n, err
}

// ── MatchCancellationRepository ─────────────────────────────────────────────

type matchCancellationRepository struct {
	db *gorm.DB
}

func NewMatchCancellationRepository(db *gorm.DB) domain.MatchCancellationRepository {
	return &matchCancellationRepository{db: db}
}

func (r *matchCancellationRepository) Create(ctx context.Context, c *entity.MatchCancellation) error {
	if c.CancelledAt.IsZero() {
		c.CancelledAt = time.Now()
	}
	return r.db.WithContext(ctx).Create(c).Error
}

func (r *matchCancellationRepository) CountLateForUser(ctx context.Context, userID uuid.UUID, withinDays int) (int64, error) {
	var n int64
	since := time.Now().AddDate(0, 0, -withinDays)
	err := r.db.WithContext(ctx).Model(&entity.MatchCancellation{}).
		Where("user_id = ? AND fee_forfeited = TRUE AND cancelled_at >= ?", userID, since).
		Count(&n).Error
	return n, err
}
