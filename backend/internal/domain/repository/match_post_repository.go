package repository

import (
	"context"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
)

type MatchPostFilter struct {
	Lat      float64
	Lng      float64
	Radius   float64 // km, 0 = no geo filter
	PostType string  // "" = all
	Page     int
	Limit    int
}

type MatchPostRepository interface {
	Create(ctx context.Context, post *entity.MatchPost) error
	List(ctx context.Context, f MatchPostFilter) ([]entity.MatchPost, int64, error)
	FindByID(ctx context.Context, id uuid.UUID) (*entity.MatchPost, error)
	JoinPost(ctx context.Context, id uuid.UUID, userID uuid.UUID) error
	// LeavePost is the inverse of JoinPost: deletes the join row and atomically
	// decrements spots_filled (clamped at 0). Returns an error if the user
	// hadn't joined.
	LeavePost(ctx context.Context, id uuid.UUID, userID uuid.UUID) error
	Delete(ctx context.Context, id uuid.UUID) error
	FindNearbyUserIDs(ctx context.Context, lat, lng, radius float64) ([]uuid.UUID, error)

	// JoinedPostIDs returns the set of match-post IDs the user has joined.
	// Used to mark `is_joined` on list/detail responses.
	JoinedPostIDs(ctx context.Context, userID uuid.UUID, postIDs []uuid.UUID) (map[uuid.UUID]bool, error)

	// ListMine returns matches the user is involved in: hosted OR joined.
	// `scope`:
	//   "all"      — everything I'm involved in (default)
	//   "hosted"   — only matches I created
	//   "joined"   — only matches I joined as a player
	//   "upcoming" — kickoff in the future
	//   "past"     — kickoff already passed
	ListMine(ctx context.Context, userID uuid.UUID, scope string, page, limit int) ([]entity.MatchPost, int64, error)
}
