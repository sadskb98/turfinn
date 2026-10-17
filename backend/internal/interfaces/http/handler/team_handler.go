package handler

import (
	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/interfaces/dto"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type TeamHandler struct {
	teamSvc *service.TeamService
}

func NewTeamHandler(teamSvc *service.TeamService) *TeamHandler {
	return &TeamHandler{teamSvc: teamSvc}
}

// POST /api/v1/teams
func (h *TeamHandler) CreateTeam(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	var req dto.CreateTeamRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	team, err := h.teamSvc.CreateTeam(c.Request().Context(), userID, req.Name, req.Format, req.Formation)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, toTeamResponse(team))
}

// GET /api/v1/teams/my
func (h *TeamHandler) ListMyTeams(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	teams, err := h.teamSvc.ListMyTeams(c.Request().Context(), userID)
	if err != nil {
		return response.InternalError(c)
	}
	result := make([]dto.TeamResponse, len(teams))
	for i, t := range teams {
		result[i] = toTeamResponse(&t)
	}
	return response.OK(c, result)
}

// GET /api/v1/teams/:id
func (h *TeamHandler) GetTeam(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid team id")
	}
	team, err := h.teamSvc.GetTeam(c.Request().Context(), id)
	if err != nil {
		return response.NotFound(c, "team not found")
	}
	return response.OK(c, toTeamResponse(team))
}

// POST /api/v1/teams/join
func (h *TeamHandler) JoinTeam(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	var req dto.JoinTeamRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}

	team, err := h.teamSvc.JoinTeam(c.Request().Context(), userID, req.Code)
	if err != nil {
		switch err {
		case service.ErrTeamNotFound:
			return response.NotFound(c, "no team found with that code")
		case service.ErrAlreadyMember:
			return response.BadRequest(c, "you are already on this team")
		case service.ErrTeamFull:
			return response.BadRequest(c, "team is full")
		default:
			return response.InternalError(c)
		}
	}
	return response.OK(c, toTeamResponse(team))
}

// PUT /api/v1/teams/:id/formation
func (h *TeamHandler) UpdateFormation(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	teamID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid team id")
	}

	var req dto.UpdateFormationRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}

	team, err := h.teamSvc.UpdateFormation(c.Request().Context(), userID, teamID, req.Formation)
	if err != nil {
		if err == service.ErrNotCaptain {
			return response.BadRequest(c, "only captain can change formation")
		}
		return response.InternalError(c)
	}
	return response.OK(c, toTeamResponse(team))
}

// POST /api/v1/matchmaking/find
func (h *TeamHandler) FindMatch(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	var req dto.FindMatchRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}

	match, err := h.teamSvc.FindMatch(c.Request().Context(), userID, req.TeamID, req.WantedFormat, req.City, req.Latitude, req.Longitude, req.RadiusKM)
	if err != nil {
		switch err {
		case service.ErrNotCaptain:
			return response.BadRequest(c, "only captain can start matchmaking")
		case service.ErrTeamNotFound:
			return response.NotFound(c, "team not found")
		default:
			return response.InternalError(c)
		}
	}
	return response.OK(c, toMatchResponse(match))
}

// GET /api/v1/matchmaking/:id
func (h *TeamHandler) GetMatch(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid match id")
	}
	match, err := h.teamSvc.GetMatch(c.Request().Context(), id)
	if err != nil {
		return response.NotFound(c, "match not found")
	}
	return response.OK(c, toMatchResponse(match))
}

// GET /api/v1/matchmaking/active/:team_id
func (h *TeamHandler) GetActiveMatch(c echo.Context) error {
	teamID, err := uuid.Parse(c.Param("team_id"))
	if err != nil {
		return response.BadRequest(c, "invalid team id")
	}
	match, err := h.teamSvc.GetActiveMatch(c.Request().Context(), teamID)
	if err != nil {
		return response.NotFound(c, "no active match")
	}
	return response.OK(c, toMatchResponse(match))
}

// PUT /api/v1/matchmaking/:id/venue
func (h *TeamHandler) SetVenue(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	matchID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid match id")
	}
	var req dto.SetVenueRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	match, err := h.teamSvc.SetVenue(c.Request().Context(), userID, matchID, req.PitchID, req.ScheduledAt)
	if err != nil {
		switch err {
		case service.ErrTeamMatchNotFound:
			return response.NotFound(c, "match not found")
		case service.ErrNotCaptain:
			return response.BadRequest(c, "only a team captain can set the venue")
		case service.ErrVenueAlreadySet:
			return response.BadRequest(c, "venue already set")
		case service.ErrTeamNotReady:
			return response.BadRequest(c, "match is not yet in matched status")
		default:
			return response.InternalError(c)
		}
	}
	return response.OK(c, toMatchResponse(match))
}

// POST /api/v1/teams/:id/transfer-captain
func (h *TeamHandler) TransferCaptain(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	teamID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid team id")
	}

	var req struct {
		UserID uuid.UUID `json:"user_id" validate:"required"`
	}
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}

	team, err := h.teamSvc.TransferCaptain(c.Request().Context(), userID, teamID, req.UserID)
	if err != nil {
		switch err {
		case service.ErrTeamNotFound:
			return response.NotFound(c, "team not found")
		case service.ErrNotCaptain:
			return response.BadRequest(c, "only the captain can transfer captaincy")
		default:
			return response.BadRequest(c, err.Error())
		}
	}
	return response.OK(c, toTeamResponse(team))
}

// DELETE /api/v1/teams/:id/members/:uid
func (h *TeamHandler) RemoveMember(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	teamID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid team id")
	}
	memberID, err := uuid.Parse(c.Param("uid"))
	if err != nil {
		return response.BadRequest(c, "invalid member id")
	}

	if err := h.teamSvc.RemoveMember(c.Request().Context(), userID, teamID, memberID); err != nil {
		switch err {
		case service.ErrTeamNotFound:
			return response.NotFound(c, "team not found")
		case service.ErrNotCaptain:
			return response.BadRequest(c, "only the captain can remove members")
		default:
			return response.BadRequest(c, err.Error())
		}
	}
	return response.OK(c, map[string]string{"message": "member removed"})
}

// ── Helpers ──────────────────────────────────────────────────────────────────

func toTeamResponse(t *entity.Team) dto.TeamResponse {
	members := make([]dto.TeamMemberResponse, len(t.Members))
	for i, m := range t.Members {
		name := ""
		phone := ""
		if m.User != nil {
			name = m.User.Name
			if m.User.Phone != nil {
				phone = *m.User.Phone
			}
		}
		members[i] = dto.TeamMemberResponse{
			ID:       m.ID.String(),
			UserID:   m.UserID.String(),
			Name:     name,
			Phone:    phone,
			Position: m.Position,
			Number:   m.Number,
			Role:     string(m.Role),
		}
	}

	return dto.TeamResponse{
		ID:         t.ID.String(),
		Name:       t.Name,
		Code:       t.Code,
		Format:     t.Format,
		Formation:  t.Formation,
		CaptainID:  t.CaptainID.String(),
		MaxPlayers: t.MaxPlayers,
		Status:     string(t.Status),
		Members:    members,
		CreatedAt:  t.CreatedAt.Format("2006-01-02T15:04:05Z"),
	}
}

func toMatchResponse(m *entity.Match) dto.MatchResponse {
	resp := dto.MatchResponse{
		ID:        m.ID.String(),
		Format:    m.Format,
		Status:    string(m.Status),
		CreatedAt: m.CreatedAt.Format("2006-01-02T15:04:05Z"),
	}
	if m.HomeTeam != nil {
		ht := toTeamResponse(m.HomeTeam)
		resp.HomeTeam = &ht
	}
	if m.AwayTeam != nil {
		at := toTeamResponse(m.AwayTeam)
		resp.AwayTeam = &at
	}
	if m.PitchID != nil {
		pid := m.PitchID.String()
		resp.PitchID = &pid
	}
	if m.ScheduledAt != nil {
		s := m.ScheduledAt.Format("2006-01-02T15:04:05Z")
		resp.ScheduledAt = &s
	}
	return resp
}
