package service

import (
	"context"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/domain/repository"
)

var (
	ErrTeamFull        = errors.New("team is full")
	ErrAlreadyMember   = errors.New("already a member of this team")
	ErrTeamNotFound    = errors.New("team not found")
	ErrNotCaptain      = errors.New("only the captain can do this")
	ErrTeamNotReady    = errors.New("team must be ready to find a match")
	ErrTeamMatchNotFound = errors.New("match not found")
	ErrVenueAlreadySet   = errors.New("venue already set")
)

const (
	TypeMatchFound = "match:found"
	TypeVenueSet   = "match:venue_set"
)

type MatchFoundPayload struct {
	MatchID       string `json:"match_id"`
	HomeCaptainID string `json:"home_captain_id"`
}

type VenueSetPayload struct {
	MatchID        string `json:"match_id"`
	OtherCaptainID string `json:"other_captain_id"`
	ScheduledAt    string `json:"scheduled_at"` // RFC3339 UTC
}

type TeamService struct {
	teamRepo    repository.TeamRepository
	userRepo    repository.UserRepository
	asynqClient *asynq.Client
}

func NewTeamService(teamRepo repository.TeamRepository, userRepo repository.UserRepository, asynqClient *asynq.Client) *TeamService {
	return &TeamService{teamRepo: teamRepo, userRepo: userRepo, asynqClient: asynqClient}
}

func parseMaxPlayers(format string) int {
	// "7 vs 7" → 7
	parts := strings.Fields(format)
	if len(parts) > 0 {
		n, _ := strconv.Atoi(parts[0])
		if n > 0 {
			return n
		}
	}
	return 7
}

func (s *TeamService) CreateTeam(ctx context.Context, userID uuid.UUID, name, format, formation string) (*entity.Team, error) {
	maxPlayers := parseMaxPlayers(format)

	team := entity.NewTeam(name, format, userID, maxPlayers)
	if formation != "" {
		team.Formation = formation
	}

	if err := s.teamRepo.Create(ctx, team); err != nil {
		return nil, err
	}

	// Auto-add captain as first member
	member := &entity.TeamMember{
		ID:       uuid.New(),
		TeamID:   team.ID,
		UserID:   userID,
		Role:     entity.MemberRoleCaptain,
		Number:   1,
		JoinedAt: time.Now(),
	}
	if err := s.teamRepo.AddMember(ctx, member); err != nil {
		return nil, err
	}

	return s.teamRepo.FindByID(ctx, team.ID)
}

func (s *TeamService) GetTeam(ctx context.Context, teamID uuid.UUID) (*entity.Team, error) {
	return s.teamRepo.FindByID(ctx, teamID)
}

func (s *TeamService) GetTeamByCode(ctx context.Context, code string) (*entity.Team, error) {
	return s.teamRepo.FindByCode(ctx, code)
}

func (s *TeamService) ListMyTeams(ctx context.Context, userID uuid.UUID) ([]entity.Team, error) {
	return s.teamRepo.ListByUser(ctx, userID)
}

func (s *TeamService) JoinTeam(ctx context.Context, userID uuid.UUID, code string) (*entity.Team, error) {
	team, err := s.teamRepo.FindByCode(ctx, code)
	if err != nil {
		return nil, ErrTeamNotFound
	}

	// Check already member
	isMember, _ := s.teamRepo.IsMember(ctx, team.ID, userID)
	if isMember {
		return nil, ErrAlreadyMember
	}

	// Check capacity
	count, _ := s.teamRepo.MemberCount(ctx, team.ID)
	if int(count) >= team.MaxPlayers+5 { // +5 for subs
		return nil, ErrTeamFull
	}

	// Assign number
	nextNum := int(count) + 1
	role := entity.MemberRolePlayer
	if int(count) >= team.MaxPlayers {
		role = entity.MemberRoleSub
	}

	member := &entity.TeamMember{
		ID:       uuid.New(),
		TeamID:   team.ID,
		UserID:   userID,
		Role:     role,
		Number:   nextNum,
		JoinedAt: time.Now(),
	}
	if err := s.teamRepo.AddMember(ctx, member); err != nil {
		return nil, err
	}

	// If team is full (starters), mark ready
	newCount := count + 1
	if int(newCount) >= team.MaxPlayers && team.Status == entity.TeamStatusForming {
		team.Status = entity.TeamStatusReady
		s.teamRepo.Update(ctx, team)
	}

	return s.teamRepo.FindByID(ctx, team.ID)
}

func (s *TeamService) LeaveTeam(ctx context.Context, userID uuid.UUID, teamID uuid.UUID) error {
	return s.teamRepo.RemoveMember(ctx, teamID, userID)
}

func (s *TeamService) UpdateFormation(ctx context.Context, userID uuid.UUID, teamID uuid.UUID, formation string) (*entity.Team, error) {
	team, err := s.teamRepo.FindByID(ctx, teamID)
	if err != nil {
		return nil, ErrTeamNotFound
	}
	if team.CaptainID != userID {
		return nil, ErrNotCaptain
	}
	team.Formation = formation
	if err := s.teamRepo.Update(ctx, team); err != nil {
		return nil, err
	}
	return team, nil
}

// ── Matchmaking ──────────────────────────────────────────────────────────────

const defaultRadiusKM = 30.0

func (s *TeamService) FindMatch(ctx context.Context, userID uuid.UUID, teamID uuid.UUID, wantedFormat, city string, lat, lng, radiusKM float64) (*entity.Match, error) {
	team, err := s.teamRepo.FindByID(ctx, teamID)
	if err != nil {
		return nil, ErrTeamNotFound
	}
	if team.CaptainID != userID {
		return nil, ErrNotCaptain
	}

	// Prevent duplicate searching: return existing active match if any
	if active, err := s.teamRepo.FindActiveMatchForTeam(ctx, teamID); err == nil && active != nil {
		return active, nil
	}

	if wantedFormat == "" {
		wantedFormat = "open"
	}
	hasLocation := lat != 0 || lng != 0
	if radiusKM <= 0 {
		radiusKM = defaultRadiusKM
	}

	// Phase 1: radius-based if GPS provided
	// Phase 2: city-scoped if city given
	// Phase 3: global format-only fallback
	var existing *entity.Match
	if hasLocation {
		existing, err = s.teamRepo.FindSearchingMatch(ctx, wantedFormat, lat, lng, radiusKM, "", teamID)
	}
	if existing == nil && city != "" {
		existing, err = s.teamRepo.FindSearchingMatch(ctx, wantedFormat, 0, 0, 0, city, teamID)
	}
	if existing == nil {
		existing, err = s.teamRepo.FindSearchingMatch(ctx, wantedFormat, 0, 0, 0, "", teamID)
	}

	if err == nil && existing != nil {
		existing.AwayTeamID = &teamID
		existing.Status = entity.MatchMatched
		if err := s.teamRepo.UpdateMatch(ctx, existing); err != nil {
			return nil, err
		}
		if existing.HomeTeam != nil && s.asynqClient != nil {
			p, _ := json.Marshal(MatchFoundPayload{
				MatchID:       existing.ID.String(),
				HomeCaptainID: existing.HomeTeam.CaptainID.String(),
			})
			task := asynq.NewTask(TypeMatchFound, p, asynq.MaxRetry(3), asynq.Queue("critical"))
			_, _ = s.asynqClient.Enqueue(task)
		}
		return s.teamRepo.FindMatchByID(ctx, existing.ID)
	}

	// No opponent found — join the queue
	matchFormat := wantedFormat
	if matchFormat == "open" {
		matchFormat = ""
	}
	match := &entity.Match{
		ID:         uuid.New(),
		HomeTeamID: teamID,
		Format:     matchFormat,
		City:       city,
		Latitude:   lat,
		Longitude:  lng,
		Status:     entity.MatchSearching,
	}
	if err := s.teamRepo.CreateMatch(ctx, match); err != nil {
		return nil, err
	}
	return s.teamRepo.FindMatchByID(ctx, match.ID)
}

// TransferCaptain transfers captain role from current captain to a new member.
func (s *TeamService) TransferCaptain(ctx context.Context, userID uuid.UUID, teamID uuid.UUID, newCaptainID uuid.UUID) (*entity.Team, error) {
	team, err := s.teamRepo.FindByID(ctx, teamID)
	if err != nil {
		return nil, ErrTeamNotFound
	}
	if team.CaptainID != userID {
		return nil, ErrNotCaptain
	}

	// Verify new captain is a member
	isMember, _ := s.teamRepo.IsMember(ctx, teamID, newCaptainID)
	if !isMember {
		return nil, errors.New("target user is not a member of this team")
	}

	// Update team captain
	team.CaptainID = newCaptainID
	if err := s.teamRepo.Update(ctx, team); err != nil {
		return nil, err
	}

	// Swap member roles: old captain becomes player, new captain becomes captain
	members, _ := s.teamRepo.GetMembers(ctx, teamID)
	for _, m := range members {
		if m.UserID == userID {
			m.Role = entity.MemberRolePlayer
			s.teamRepo.UpdateMember(ctx, &m)
		}
		if m.UserID == newCaptainID {
			m.Role = entity.MemberRoleCaptain
			s.teamRepo.UpdateMember(ctx, &m)
		}
	}

	return s.teamRepo.FindByID(ctx, teamID)
}

// RemoveMember removes a member from the team. Captain cannot kick themselves.
func (s *TeamService) RemoveMember(ctx context.Context, userID uuid.UUID, teamID uuid.UUID, memberID uuid.UUID) error {
	team, err := s.teamRepo.FindByID(ctx, teamID)
	if err != nil {
		return ErrTeamNotFound
	}
	if team.CaptainID != userID {
		return ErrNotCaptain
	}
	if memberID == userID {
		return errors.New("captain cannot remove themselves")
	}

	// Verify target is actually a member
	isMember, _ := s.teamRepo.IsMember(ctx, teamID, memberID)
	if !isMember {
		return errors.New("user is not a member of this team")
	}

	return s.teamRepo.RemoveMember(ctx, teamID, memberID)
}

func (s *TeamService) GetMatch(ctx context.Context, matchID uuid.UUID) (*entity.Match, error) {
	return s.teamRepo.FindMatchByID(ctx, matchID)
}

func (s *TeamService) ListTeamMatches(ctx context.Context, teamID uuid.UUID) ([]entity.Match, error) {
	return s.teamRepo.ListMatchesByTeam(ctx, teamID)
}

// GetActiveMatch returns the latest searching or matched match for a team.
func (s *TeamService) GetActiveMatch(ctx context.Context, teamID uuid.UUID) (*entity.Match, error) {
	matches, err := s.teamRepo.ListMatchesByTeam(ctx, teamID)
	if err != nil {
		return nil, err
	}
	for _, m := range matches {
		if m.Status == entity.MatchSearching || m.Status == entity.MatchMatched {
			mc := m
			return &mc, nil
		}
	}
	return nil, ErrTeamMatchNotFound
}

// SetVenue sets the pitch and scheduled time for a matched match.
// Either team's captain can call this; first one to confirm wins.
func (s *TeamService) SetVenue(ctx context.Context, userID, matchID, pitchID uuid.UUID, scheduledAt time.Time) (*entity.Match, error) {
	match, err := s.teamRepo.FindMatchByID(ctx, matchID)
	if err != nil {
		return nil, ErrTeamMatchNotFound
	}

	isHomeCaptain := match.HomeTeam != nil && match.HomeTeam.CaptainID == userID
	isAwayCaptain := match.AwayTeam != nil && match.AwayTeam.CaptainID == userID
	if !isHomeCaptain && !isAwayCaptain {
		return nil, ErrNotCaptain
	}
	if match.Status == entity.MatchConfirmed {
		return nil, ErrVenueAlreadySet
	}
	if match.Status != entity.MatchMatched {
		return nil, ErrTeamNotReady
	}

	match.PitchID = &pitchID
	match.ScheduledAt = &scheduledAt
	match.Status = entity.MatchConfirmed
	if err := s.teamRepo.UpdateMatch(ctx, match); err != nil {
		return nil, err
	}

	// Notify the other team's captain via Asynq
	var otherCaptainID uuid.UUID
	if isHomeCaptain && match.AwayTeam != nil {
		otherCaptainID = match.AwayTeam.CaptainID
	} else if isAwayCaptain && match.HomeTeam != nil {
		otherCaptainID = match.HomeTeam.CaptainID
	}
	if otherCaptainID != uuid.Nil && s.asynqClient != nil {
		p, _ := json.Marshal(VenueSetPayload{
			MatchID:        matchID.String(),
			OtherCaptainID: otherCaptainID.String(),
			ScheduledAt:    scheduledAt.UTC().Format(time.RFC3339),
		})
		task := asynq.NewTask(TypeVenueSet, p, asynq.MaxRetry(3), asynq.Queue("critical"))
		_, _ = s.asynqClient.Enqueue(task)
	}

	return s.teamRepo.FindMatchByID(ctx, matchID)
}
