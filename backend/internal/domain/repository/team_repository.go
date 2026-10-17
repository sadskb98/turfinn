package repository

import (
	"context"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
)

type TeamRepository interface {
	Create(ctx context.Context, team *entity.Team) error
	FindByID(ctx context.Context, id uuid.UUID) (*entity.Team, error)
	FindByCode(ctx context.Context, code string) (*entity.Team, error)
	ListByUser(ctx context.Context, userID uuid.UUID) ([]entity.Team, error)
	Update(ctx context.Context, team *entity.Team) error

	AddMember(ctx context.Context, member *entity.TeamMember) error
	RemoveMember(ctx context.Context, teamID, userID uuid.UUID) error
	UpdateMember(ctx context.Context, member *entity.TeamMember) error
	GetMembers(ctx context.Context, teamID uuid.UUID) ([]entity.TeamMember, error)
	IsMember(ctx context.Context, teamID, userID uuid.UUID) (bool, error)
	MemberCount(ctx context.Context, teamID uuid.UUID) (int64, error)

	// Admin
	ListAll(ctx context.Context, page, limit int) ([]entity.Team, int64, error)
	Count(ctx context.Context) (int64, error)

	// Match
	CreateMatch(ctx context.Context, match *entity.Match) error
	FindMatchByID(ctx context.Context, id uuid.UUID) (*entity.Match, error)
	FindSearchingMatch(ctx context.Context, wantedFormat string, lat, lng, radiusKM float64, city string, excludeTeamID uuid.UUID) (*entity.Match, error)
	FindActiveMatchForTeam(ctx context.Context, teamID uuid.UUID) (*entity.Match, error)
	UpdateMatch(ctx context.Context, match *entity.Match) error
	ListMatchesByTeam(ctx context.Context, teamID uuid.UUID) ([]entity.Match, error)
	ListAllMatches(ctx context.Context, page, limit int) ([]entity.Match, int64, error)
	MatchCount(ctx context.Context) (int64, error)
}
