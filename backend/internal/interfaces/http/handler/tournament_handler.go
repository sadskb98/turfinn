package handler

import (
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/domain/entity"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type TournamentHandler struct {
	svc *service.TournamentService
}

func NewTournamentHandler(svc *service.TournamentService) *TournamentHandler {
	return &TournamentHandler{svc: svc}
}

// POST /api/v1/tournaments
func (h *TournamentHandler) Create(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)

	var req struct {
		Name        string  `json:"name" validate:"required"`
		Description string  `json:"description"`
		Format      string  `json:"format" validate:"required"`
		MaxTeams    int     `json:"max_teams" validate:"required,min=2,max=64"`
		EntryFee    int     `json:"entry_fee"`
		MinCoins    int     `json:"min_coins"`
		Visibility  string  `json:"visibility"`
		StartsAt    *string `json:"starts_at"`
	}
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	if req.Visibility == "" {
		req.Visibility = "public"
	}
	if req.Visibility != "public" && req.Visibility != "private" {
		return response.BadRequest(c, "visibility must be 'public' or 'private'")
	}

	var startsAt *time.Time
	if req.StartsAt != nil {
		t, err := time.Parse(time.RFC3339, *req.StartsAt)
		if err != nil {
			return response.BadRequest(c, "invalid starts_at format, use RFC3339")
		}
		startsAt = &t
	}

	tournament, err := h.svc.Create(c.Request().Context(), userID, req.Name, req.Description, req.Format, req.Visibility, req.MaxTeams, req.EntryFee, req.MinCoins, startsAt)
	if err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, toTournamentResponse(tournament))
}

// GET /api/v1/tournaments
func (h *TournamentHandler) List(c echo.Context) error {
	page, _ := strconv.Atoi(c.QueryParam("page"))
	if page < 1 {
		page = 1
	}
	limit, _ := strconv.Atoi(c.QueryParam("limit"))
	if limit < 1 || limit > 50 {
		limit = 20
	}

	tournaments, total, err := h.svc.List(c.Request().Context(), page, limit)
	if err != nil {
		return response.InternalError(c)
	}

	result := make([]map[string]interface{}, len(tournaments))
	for i, t := range tournaments {
		result[i] = toTournamentResponse(&t)
	}
	return response.OKPaginated(c, result, response.Meta{Page: page, Limit: limit, Total: total})
}

// GET /api/v1/tournaments/:id
func (h *TournamentHandler) Get(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid tournament id")
	}

	t, err := h.svc.Get(c.Request().Context(), id)
	if err != nil {
		return response.NotFound(c, "tournament not found")
	}
	return response.OK(c, toTournamentDetailResponse(t))
}

// POST /api/v1/tournaments/:id/join
func (h *TournamentHandler) Join(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	tournamentID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid tournament id")
	}

	var req struct {
		TeamID     uuid.UUID `json:"team_id" validate:"required"`
		InviteCode string    `json:"invite_code"`
	}
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}

	if err := h.svc.Join(c.Request().Context(), userID, tournamentID, req.TeamID, req.InviteCode); err != nil {
		switch err {
		case service.ErrTournamentNotFound:
			return response.NotFound(c, "tournament not found")
		case service.ErrTournamentNotOpen:
			return response.BadRequest(c, "tournament is not open for registration")
		case service.ErrNotCaptain:
			return response.BadRequest(c, "only the team captain can register")
		case service.ErrTeamAlreadyRegistered:
			return response.Conflict(c, "team is already registered")
		case service.ErrTournamentFull:
			return response.BadRequest(c, "tournament is full")
		case service.ErrFormatMismatch:
			return response.BadRequest(c, "team format does not match tournament format")
		case service.ErrInsufficientBalance:
			return response.BadRequest(c, "insufficient wallet balance for entry fee")
		case service.ErrTeamCoinsInsufficient:
			return response.BadRequest(c, "team does not meet minimum coins requirement")
		case service.ErrInvalidInviteCode:
			return response.BadRequest(c, "invalid invite code")
		case service.ErrTeamNotFound:
			return response.NotFound(c, "team not found")
		default:
			return response.InternalError(c)
		}
	}
	return response.OK(c, map[string]string{"message": "team registered successfully"})
}

// POST /api/v1/tournaments/:id/start
func (h *TournamentHandler) Start(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	tournamentID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid tournament id")
	}

	if err := h.svc.Start(c.Request().Context(), userID, tournamentID); err != nil {
		switch err {
		case service.ErrTournamentNotFound:
			return response.NotFound(c, "tournament not found")
		case service.ErrNotTournamentCreator:
			return response.BadRequest(c, "only the tournament creator can start it")
		case service.ErrTournamentNotOpen:
			return response.BadRequest(c, "tournament is not open for registration")
		case service.ErrNotEnoughTeams:
			return response.BadRequest(c, "need at least 2 teams to start")
		default:
			return response.InternalError(c)
		}
	}
	return response.OK(c, map[string]string{"message": "tournament started, bracket generated"})
}

// POST /api/v1/tournaments/:id/cancel
func (h *TournamentHandler) Cancel(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	tournamentID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid tournament id")
	}

	if err := h.svc.Cancel(c.Request().Context(), userID, tournamentID); err != nil {
		switch err {
		case service.ErrTournamentNotFound:
			return response.NotFound(c, "tournament not found")
		case service.ErrNotTournamentCreator:
			return response.BadRequest(c, "only the creator can cancel")
		case service.ErrTournamentAlreadyStarted:
			return response.BadRequest(c, "cannot cancel a tournament that has already started")
		default:
			return response.InternalError(c)
		}
	}
	return response.OK(c, map[string]string{"message": "tournament cancelled, entry fees refunded"})
}

// POST /api/v1/tournaments/:id/leave
func (h *TournamentHandler) Leave(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	tournamentID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid tournament id")
	}

	var req struct {
		TeamID uuid.UUID `json:"team_id" validate:"required"`
	}
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}

	if err := h.svc.Leave(c.Request().Context(), userID, tournamentID, req.TeamID); err != nil {
		switch err {
		case service.ErrTournamentNotFound:
			return response.NotFound(c, "tournament not found")
		case service.ErrTournamentAlreadyStarted:
			return response.BadRequest(c, "cannot leave after tournament started")
		case service.ErrNotCaptain:
			return response.BadRequest(c, "only the captain can withdraw the team")
		case service.ErrTeamNotFound:
			return response.NotFound(c, "team not registered in this tournament")
		default:
			return response.InternalError(c)
		}
	}
	return response.OK(c, map[string]string{"message": "team withdrawn, entry fee refunded"})
}

// POST /api/v1/tournaments/:id/matches/:mid/report
func (h *TournamentHandler) ReportScore(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	tournamentID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid tournament id")
	}
	matchID, err := uuid.Parse(c.Param("mid"))
	if err != nil {
		return response.BadRequest(c, "invalid match id")
	}

	var req struct {
		HomeScore int `json:"home_score" validate:"min=0"`
		AwayScore int `json:"away_score" validate:"min=0"`
	}
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}

	if err := h.svc.ReportScore(c.Request().Context(), userID, tournamentID, matchID, req.HomeScore, req.AwayScore); err != nil {
		switch err {
		case service.ErrMatchNotFound:
			return response.NotFound(c, "match not found")
		case service.ErrMatchNotReadyToReport:
			return response.BadRequest(c, "match is not ready for score reporting")
		case service.ErrNotMatchParticipant:
			return response.BadRequest(c, "you are not a captain of either team")
		default:
			return response.InternalError(c)
		}
	}
	return response.OK(c, map[string]string{"message": "score reported, awaiting confirmation"})
}

// POST /api/v1/tournaments/:id/matches/:mid/confirm
func (h *TournamentHandler) ConfirmScore(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	tournamentID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid tournament id")
	}
	matchID, err := uuid.Parse(c.Param("mid"))
	if err != nil {
		return response.BadRequest(c, "invalid match id")
	}

	if err := h.svc.ConfirmScore(c.Request().Context(), userID, tournamentID, matchID); err != nil {
		switch err {
		case service.ErrMatchNotFound:
			return response.NotFound(c, "match not found")
		case service.ErrMatchNotReported:
			return response.BadRequest(c, "match score has not been reported yet")
		case service.ErrNotMatchParticipant:
			return response.BadRequest(c, "you are not a captain of either team")
		case service.ErrCannotConfirmOwnReport:
			return response.BadRequest(c, "the reporting captain cannot confirm their own report")
		case service.ErrMatchAlreadyConfirmed:
			return response.BadRequest(c, "match result is already confirmed")
		default:
			return response.InternalError(c)
		}
	}
	return response.OK(c, map[string]string{"message": "score confirmed"})
}

// POST /api/v1/tournaments/:id/matches/:mid/dispute
func (h *TournamentHandler) DisputeScore(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	tournamentID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid tournament id")
	}
	matchID, err := uuid.Parse(c.Param("mid"))
	if err != nil {
		return response.BadRequest(c, "invalid match id")
	}

	var req struct {
		Reason string `json:"reason" validate:"required"`
	}
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	if err := h.svc.DisputeScore(c.Request().Context(), userID, tournamentID, matchID, req.Reason); err != nil {
		switch err {
		case service.ErrMatchNotFound:
			return response.NotFound(c, "match not found")
		case service.ErrMatchNotReported:
			return response.BadRequest(c, "match score has not been reported yet")
		case service.ErrNotMatchParticipant:
			return response.BadRequest(c, "you are not a captain of either team")
		case service.ErrCannotConfirmOwnReport:
			return response.BadRequest(c, "you cannot dispute your own report")
		default:
			return response.InternalError(c)
		}
	}
	return response.OK(c, map[string]string{"message": "score disputed"})
}

// ── Response Mappers ─────────────────────────────────────────────────────────

func toTournamentResponse(t *entity.Tournament) map[string]interface{} {
	resp := map[string]interface{}{
		"id":          t.ID.String(),
		"creator_id":  t.CreatorID.String(),
		"name":        t.Name,
		"description": t.Description,
		"format":      t.Format,
		"max_teams":   t.MaxTeams,
		"entry_fee":   t.EntryFee,
		"min_coins":   t.MinCoins,
		"prize_pool":  t.PrizePool,
		"visibility":  t.Visibility,
		"status":      string(t.Status),
		"team_count":  len(t.Teams),
		"created_at":  t.CreatedAt.Format(time.RFC3339),
		"updated_at":  t.UpdatedAt.Format(time.RFC3339),
	}
	if t.InviteCode != nil {
		resp["invite_code"] = *t.InviteCode
	}
	if t.StartsAt != nil {
		resp["starts_at"] = t.StartsAt.Format(time.RFC3339)
	}
	if t.Creator != nil {
		resp["creator_name"] = t.Creator.Name
	}
	return resp
}

func toTournamentDetailResponse(t *entity.Tournament) map[string]interface{} {
	resp := toTournamentResponse(t)

	// Teams
	teams := make([]map[string]interface{}, len(t.Teams))
	for i, tt := range t.Teams {
		team := map[string]interface{}{
			"id":            tt.ID.String(),
			"team_id":       tt.TeamID.String(),
			"eliminated":    tt.Eliminated,
			"registered_at": tt.RegisteredAt.Format(time.RFC3339),
		}
		if tt.Seed != nil {
			team["seed"] = *tt.Seed
		}
		if tt.Team != nil {
			team["team_name"] = tt.Team.Name
			team["team_format"] = tt.Team.Format
			team["captain_id"] = tt.Team.CaptainID.String()
		}
		teams[i] = team
	}
	resp["teams"] = teams

	// Matches (bracket)
	matches := make([]map[string]interface{}, len(t.Matches))
	for i, m := range t.Matches {
		match := map[string]interface{}{
			"id":          m.ID.String(),
			"round":       m.Round,
			"match_order": m.MatchOrder,
			"status":      string(m.Status),
			"created_at":  m.CreatedAt.Format(time.RFC3339),
		}
		if m.HomeTeamID != nil {
			match["home_team_id"] = m.HomeTeamID.String()
		}
		if m.HomeTeam != nil {
			match["home_team_name"] = m.HomeTeam.Name
		}
		if m.AwayTeamID != nil {
			match["away_team_id"] = m.AwayTeamID.String()
		}
		if m.AwayTeam != nil {
			match["away_team_name"] = m.AwayTeam.Name
		}
		if m.HomeScore != nil {
			match["home_score"] = *m.HomeScore
		}
		if m.AwayScore != nil {
			match["away_score"] = *m.AwayScore
		}
		if m.WinnerID != nil {
			match["winner_id"] = m.WinnerID.String()
		}
		if m.Winner != nil {
			match["winner_name"] = m.Winner.Name
		}
		if m.ScheduledAt != nil {
			match["scheduled_at"] = m.ScheduledAt.Format(time.RFC3339)
		}
		matches[i] = match
	}
	resp["matches"] = matches

	return resp
}
