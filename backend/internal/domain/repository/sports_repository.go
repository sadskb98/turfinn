package repository

import (
	"context"

	"github.com/turfinn/backend/internal/domain/entity"
)

type NewsFilter struct {
	Category string // "" = any
	Search   string // "" = any
	LeagueID *int   // nil = any
	Page     int
	Limit    int
}

type NewsRepository interface {
	UpsertMany(ctx context.Context, items []entity.NewsItem) (int, error)
	List(ctx context.Context, f NewsFilter) ([]entity.NewsItem, int64, error)
}

type MatchEventFilter struct {
	Status   string // "live"|"scheduled"|"finished"|"" = any
	LeagueID *int   // nil = any
	Page     int
	Limit    int
}

type MatchEventRepository interface {
	UpsertMany(ctx context.Context, events []entity.MatchEvent) (int, error)
	List(ctx context.Context, f MatchEventFilter) ([]entity.MatchEvent, int64, error)
}

type MatchStandingRepository interface {
	Upsert(ctx context.Context, standing *entity.MatchStanding) error
	Get(ctx context.Context, leagueID, season int) (*entity.MatchStanding, error)
}
