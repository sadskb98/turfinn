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

type teamRepository struct {
	db    *gorm.DB
	redis *redis.Client
}

func NewTeamRepository(db *gorm.DB, redis *redis.Client) domain.TeamRepository {
	return &teamRepository{db: db, redis: redis}
}

func (r *teamRepository) Create(ctx context.Context, team *entity.Team) error {
	return r.db.WithContext(ctx).Create(team).Error
}

func (r *teamRepository) FindByID(ctx context.Context, id uuid.UUID) (*entity.Team, error) {
	cacheKey := fmt.Sprintf("team:%s", id)
	if cached, err := r.redis.Get(ctx, cacheKey).Result(); err == nil {
		var team entity.Team
		if json.Unmarshal([]byte(cached), &team) == nil {
			return &team, nil
		}
	}

	var team entity.Team
	if err := r.db.WithContext(ctx).Preload("Members").Preload("Members.User").Preload("Captain").First(&team, "id = ?", id).Error; err != nil {
		return nil, err
	}

	data, _ := json.Marshal(team)
	r.redis.Set(ctx, cacheKey, data, 5*time.Minute)
	return &team, nil
}

func (r *teamRepository) FindByCode(ctx context.Context, code string) (*entity.Team, error) {
	var team entity.Team
	if err := r.db.WithContext(ctx).Preload("Members").Preload("Members.User").Preload("Captain").First(&team, "code = ?", code).Error; err != nil {
		return nil, err
	}
	return &team, nil
}

func (r *teamRepository) ListByUser(ctx context.Context, userID uuid.UUID) ([]entity.Team, error) {
	var teamIDs []uuid.UUID
	if err := r.db.WithContext(ctx).Model(&entity.TeamMember{}).Where("user_id = ?", userID).Pluck("team_id", &teamIDs).Error; err != nil {
		return nil, err
	}
	if len(teamIDs) == 0 {
		return []entity.Team{}, nil
	}
	var teams []entity.Team
	if err := r.db.WithContext(ctx).Preload("Members").Preload("Captain").Where("id IN ?", teamIDs).Order("created_at DESC").Find(&teams).Error; err != nil {
		return nil, err
	}
	return teams, nil
}

func (r *teamRepository) Update(ctx context.Context, team *entity.Team) error {
	if err := r.db.WithContext(ctx).Save(team).Error; err != nil {
		return err
	}
	r.redis.Del(ctx, fmt.Sprintf("team:%s", team.ID))
	return nil
}

func (r *teamRepository) AddMember(ctx context.Context, member *entity.TeamMember) error {
	if err := r.db.WithContext(ctx).Create(member).Error; err != nil {
		return err
	}
	r.redis.Del(ctx, fmt.Sprintf("team:%s", member.TeamID))
	return nil
}

func (r *teamRepository) RemoveMember(ctx context.Context, teamID, userID uuid.UUID) error {
	if err := r.db.WithContext(ctx).Where("team_id = ? AND user_id = ?", teamID, userID).Delete(&entity.TeamMember{}).Error; err != nil {
		return err
	}
	r.redis.Del(ctx, fmt.Sprintf("team:%s", teamID))
	return nil
}

func (r *teamRepository) UpdateMember(ctx context.Context, member *entity.TeamMember) error {
	if err := r.db.WithContext(ctx).Save(member).Error; err != nil {
		return err
	}
	r.redis.Del(ctx, fmt.Sprintf("team:%s", member.TeamID))
	return nil
}

func (r *teamRepository) GetMembers(ctx context.Context, teamID uuid.UUID) ([]entity.TeamMember, error) {
	var members []entity.TeamMember
	if err := r.db.WithContext(ctx).Preload("User").Where("team_id = ?", teamID).Order("number ASC").Find(&members).Error; err != nil {
		return nil, err
	}
	return members, nil
}

func (r *teamRepository) IsMember(ctx context.Context, teamID, userID uuid.UUID) (bool, error) {
	var count int64
	if err := r.db.WithContext(ctx).Model(&entity.TeamMember{}).Where("team_id = ? AND user_id = ?", teamID, userID).Count(&count).Error; err != nil {
		return false, err
	}
	return count > 0, nil
}

func (r *teamRepository) MemberCount(ctx context.Context, teamID uuid.UUID) (int64, error) {
	var count int64
	if err := r.db.WithContext(ctx).Model(&entity.TeamMember{}).Where("team_id = ?", teamID).Count(&count).Error; err != nil {
		return 0, err
	}
	return count, nil
}

// ── Admin ────────────────────────────────────────────────────────────────────

func (r *teamRepository) ListAll(ctx context.Context, page, limit int) ([]entity.Team, int64, error) {
	var total int64
	r.db.WithContext(ctx).Model(&entity.Team{}).Count(&total)

	var teams []entity.Team
	err := r.db.WithContext(ctx).Preload("Members").Preload("Captain").
		Order("created_at DESC").
		Offset((page - 1) * limit).Limit(limit).
		Find(&teams).Error
	return teams, total, err
}

func (r *teamRepository) Count(ctx context.Context) (int64, error) {
	var count int64
	err := r.db.WithContext(ctx).Model(&entity.Team{}).Count(&count).Error
	return count, err
}

func (r *teamRepository) ListAllMatches(ctx context.Context, page, limit int) ([]entity.Match, int64, error) {
	var total int64
	r.db.WithContext(ctx).Model(&entity.Match{}).Count(&total)

	var matches []entity.Match
	err := r.db.WithContext(ctx).Preload("HomeTeam").Preload("AwayTeam").
		Order("created_at DESC").
		Offset((page - 1) * limit).Limit(limit).
		Find(&matches).Error
	return matches, total, err
}

func (r *teamRepository) MatchCount(ctx context.Context) (int64, error) {
	var count int64
	err := r.db.WithContext(ctx).Model(&entity.Match{}).Count(&count).Error
	return count, err
}

// ── Match ────────────────────────────────────────────────────────────────────

func (r *teamRepository) CreateMatch(ctx context.Context, match *entity.Match) error {
	return r.db.WithContext(ctx).Create(match).Error
}

func (r *teamRepository) FindMatchByID(ctx context.Context, id uuid.UUID) (*entity.Match, error) {
	var match entity.Match
	err := r.db.WithContext(ctx).
		Preload("HomeTeam").Preload("HomeTeam.Members").Preload("HomeTeam.Members.User").Preload("HomeTeam.Captain").
		Preload("AwayTeam").Preload("AwayTeam.Members").Preload("AwayTeam.Members.User").Preload("AwayTeam.Captain").
		First(&match, "id = ?", id).Error
	if err != nil {
		return nil, err
	}
	return &match, nil
}

// haversineSQL returns a SQL expression (with positional args) for the
// great-circle distance in km between (lat,lng) and a row's (latitude,longitude).
const haversineSQL = `(6371 * acos(
  cos(radians(?)) * cos(radians(latitude)) *
  cos(radians(longitude) - radians(?)) +
  sin(radians(?)) * sin(radians(latitude))
))`

func (r *teamRepository) FindSearchingMatch(ctx context.Context, wantedFormat string, lat, lng, radiusKM float64, city string, excludeTeamID uuid.UUID) (*entity.Match, error) {
	var match entity.Match
	q := r.db.WithContext(ctx).
		Preload("HomeTeam").Preload("HomeTeam.Members").Preload("HomeTeam.Members.User").Preload("HomeTeam.Captain").
		Where("status = ? AND home_team_id != ? AND created_at > NOW() - INTERVAL '2 hours'",
			entity.MatchSearching, excludeTeamID)
	if wantedFormat != "" && wantedFormat != "open" {
		q = q.Where("(format = ? OR format = '')", wantedFormat)
	}
	if radiusKM > 0 && (lat != 0 || lng != 0) {
		// Only consider queued matches that also have a location set
		q = q.Where("latitude != 0 OR longitude != 0").
			Where(haversineSQL+" <= ?", lat, lng, lat, radiusKM)
	} else if city != "" {
		q = q.Where("city = ?", city)
	}
	if err := q.Order("created_at ASC").First(&match).Error; err != nil {
		return nil, err
	}
	return &match, nil
}

func (r *teamRepository) FindActiveMatchForTeam(ctx context.Context, teamID uuid.UUID) (*entity.Match, error) {
	var match entity.Match
	err := r.db.WithContext(ctx).
		Preload("HomeTeam").Preload("HomeTeam.Members").Preload("HomeTeam.Members.User").Preload("HomeTeam.Captain").
		Preload("AwayTeam").Preload("AwayTeam.Members").Preload("AwayTeam.Members.User").Preload("AwayTeam.Captain").
		Where("status IN ? AND (home_team_id = ? OR away_team_id = ?)",
			[]entity.MatchStatus{entity.MatchSearching, entity.MatchMatched, entity.MatchConfirmed},
			teamID, teamID).
		Order("created_at DESC").
		First(&match).Error
	if err != nil {
		return nil, err
	}
	return &match, nil
}

func (r *teamRepository) UpdateMatch(ctx context.Context, match *entity.Match) error {
	return r.db.WithContext(ctx).Save(match).Error
}

func (r *teamRepository) ListMatchesByTeam(ctx context.Context, teamID uuid.UUID) ([]entity.Match, error) {
	var matches []entity.Match
	if err := r.db.WithContext(ctx).
		Preload("HomeTeam").Preload("HomeTeam.Members").Preload("HomeTeam.Members.User").Preload("HomeTeam.Captain").
		Preload("AwayTeam").Preload("AwayTeam.Members").Preload("AwayTeam.Members.User").Preload("AwayTeam.Captain").
		Where("home_team_id = ? OR away_team_id = ?", teamID, teamID).
		Order("created_at DESC").Find(&matches).Error; err != nil {
		return nil, err
	}
	return matches, nil
}
