package repository

import (
	"context"
	"errors"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
)

// ── News repository ──────────────────────────────────────────────────────────

type newsRepository struct {
	db *gorm.DB
}

func NewNewsRepository(db *gorm.DB) domain.NewsRepository {
	return &newsRepository{db: db}
}

func (r *newsRepository) UpsertMany(ctx context.Context, items []entity.NewsItem) (int, error) {
	if len(items) == 0 {
		return 0, nil
	}
	res := r.db.WithContext(ctx).Clauses(clause.OnConflict{
		Columns: []clause.Column{{Name: "source"}, {Name: "source_id"}},
		DoUpdates: clause.AssignmentColumns([]string{
			"title", "summary", "url", "image_url",
			"source_name", "category", "league_id", "published_at", "payload",
		}),
	}).Create(&items)
	if res.Error != nil {
		return 0, res.Error
	}
	return int(res.RowsAffected), nil
}

func (r *newsRepository) List(ctx context.Context, f domain.NewsFilter) ([]entity.NewsItem, int64, error) {
	page := f.Page
	if page < 1 {
		page = 1
	}
	limit := f.Limit
	if limit < 1 || limit > 100 {
		limit = 20
	}

	q := r.db.WithContext(ctx).Model(&entity.NewsItem{})
	if f.Category != "" {
		q = q.Where("category = ?", f.Category)
	}
	if f.LeagueID != nil {
		q = q.Where("league_id = ?", *f.LeagueID)
	}
	if f.Search != "" {
		like := "%" + f.Search + "%"
		q = q.Where("title ILIKE ? OR summary ILIKE ?", like, like)
	}

	var total int64
	if err := q.Session(&gorm.Session{}).Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var items []entity.NewsItem
	if err := q.Order("published_at DESC").
		Offset((page - 1) * limit).Limit(limit).
		Find(&items).Error; err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

// ── MatchEvent repository ────────────────────────────────────────────────────

type matchEventRepository struct {
	db *gorm.DB
}

func NewMatchEventRepository(db *gorm.DB) domain.MatchEventRepository {
	return &matchEventRepository{db: db}
}

func (r *matchEventRepository) UpsertMany(ctx context.Context, events []entity.MatchEvent) (int, error) {
	if len(events) == 0 {
		return 0, nil
	}
	res := r.db.WithContext(ctx).Clauses(clause.OnConflict{
		Columns: []clause.Column{{Name: "source"}, {Name: "source_id"}},
		DoUpdates: clause.AssignmentColumns([]string{
			"league_id", "league", "league_logo",
			"home_team", "home_logo", "away_team", "away_logo",
			"home_score", "away_score",
			"kickoff_at", "status", "minute_played", "payload", "updated_at",
		}),
	}).Create(&events)
	if res.Error != nil {
		return 0, res.Error
	}
	return int(res.RowsAffected), nil
}

func (r *matchEventRepository) List(ctx context.Context, f domain.MatchEventFilter) ([]entity.MatchEvent, int64, error) {
	page := f.Page
	if page < 1 {
		page = 1
	}
	limit := f.Limit
	if limit < 1 || limit > 100 {
		limit = 20
	}

	q := r.db.WithContext(ctx).Model(&entity.MatchEvent{})
	if f.Status != "" {
		q = q.Where("status = ?", f.Status)
	}
	if f.LeagueID != nil {
		q = q.Where("league_id = ?", *f.LeagueID)
	}

	var total int64
	if err := q.Session(&gorm.Session{}).Count(&total).Error; err != nil {
		return nil, 0, err
	}

	// Live first, then by kickoff descending — gives newest first.
	var items []entity.MatchEvent
	if err := q.Order("CASE status WHEN 'live' THEN 0 WHEN 'scheduled' THEN 1 ELSE 2 END").
		Order("kickoff_at DESC").
		Offset((page - 1) * limit).Limit(limit).
		Find(&items).Error; err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

// ── MatchStanding repository ─────────────────────────────────────────────────

type matchStandingRepository struct {
	db *gorm.DB
}

func NewMatchStandingRepository(db *gorm.DB) domain.MatchStandingRepository {
	return &matchStandingRepository{db: db}
}

func (r *matchStandingRepository) Upsert(ctx context.Context, s *entity.MatchStanding) error {
	s.FetchedAt = time.Now()
	return r.db.WithContext(ctx).Clauses(clause.OnConflict{
		Columns: []clause.Column{{Name: "league_id"}, {Name: "season"}},
		DoUpdates: clause.AssignmentColumns([]string{
			"league_name", "league_logo", "payload", "fetched_at", "updated_at",
		}),
	}).Create(s).Error
}

func (r *matchStandingRepository) Get(ctx context.Context, leagueID, season int) (*entity.MatchStanding, error) {
	var s entity.MatchStanding
	err := r.db.WithContext(ctx).
		Where("league_id = ? AND season = ?", leagueID, season).
		First(&s).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &s, nil
}
