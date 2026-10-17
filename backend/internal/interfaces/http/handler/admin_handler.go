package handler

import (
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/config"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"github.com/turfinn/backend/internal/interfaces/dto"
	mw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type AdminHandler struct {
	userRepo    domain.UserRepository
	pitchRepo   domain.PitchRepository
	bookingRepo domain.BookingRepository
	teamRepo    domain.TeamRepository
}

func NewAdminHandler(
	ur domain.UserRepository,
	pr domain.PitchRepository,
	br domain.BookingRepository,
	tr domain.TeamRepository,
) *AdminHandler {
	return &AdminHandler{userRepo: ur, pitchRepo: pr, bookingRepo: br, teamRepo: tr}
}

func (h *AdminHandler) Dashboard(c echo.Context) error {
	ctx := c.Request().Context()

	users, _ := h.userRepo.Count(ctx)
	pitches, _ := h.pitchRepo.Count(ctx)
	bookings, _ := h.bookingRepo.Count(ctx)
	revenue, _ := h.bookingRepo.Revenue(ctx, nil)
	teams, _ := h.teamRepo.Count(ctx)
	matches, _ := h.teamRepo.MatchCount(ctx)

	return response.OK(c, dto.DashboardStats{
		TotalUsers:    users,
		TotalPitches:  pitches,
		TotalBookings: bookings,
		TotalRevenue:  revenue,
		TotalTeams:    teams,
		TotalMatches:  matches,
	})
}

func (h *AdminHandler) ListUsers(c echo.Context) error {
	page, _ := strconv.Atoi(c.QueryParam("page"))
	limit, _ := strconv.Atoi(c.QueryParam("limit"))
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = 20
	}

	users, total, err := h.userRepo.List(c.Request().Context(), domain.UserFilter{
		Search: c.QueryParam("search"),
		Role:   c.QueryParam("role"),
		Page:   page,
		Limit:  limit,
	})
	if err != nil {
		return response.InternalError(c)
	}

	items := make([]dto.AdminUserResponse, len(users))
	for i, u := range users {
		phone := ""
		if u.Phone != nil {
			phone = *u.Phone
		}
		items[i] = dto.AdminUserResponse{
			ID:         u.ID.String(),
			Phone:      phone,
			Name:       u.Name,
			AvatarURL:  u.AvatarURL,
			Position:   u.Position,
			SkillLevel: u.SkillLevel,
			Role:       string(u.Role),
			IsActive:   u.IsActive,
			CreatedAt:  u.CreatedAt.Format("2006-01-02T15:04:05Z"),
		}
	}
	return response.OKPaginated(c, items, response.Meta{Page: page, Limit: limit, Total: total})
}

// UpdateUserRole is intentionally locked. Role mutations were removed from
// the operator panel — moderation runs through SetUserActive instead.
// Kept as a 410 Gone so any clients still calling it get a clear signal
// rather than mysterious silent failures.
func (h *AdminHandler) UpdateUserRole(c echo.Context) error {
	return response.BadRequest(c,
		"role changes are no longer supported — deactivate the user instead")
}

// SetUserActive flips a user's is_active flag. Hard-blocks for super_admin
// users (the platform's last line of access — operators must not be able
// to lock themselves or each other out via the panel) and for the caller's
// own account (no self-deactivation either). Inactive users are rejected
// at auth-middleware on their next request.
func (h *AdminHandler) SetUserActive(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid user id")
	}
	var req struct {
		Active bool `json:"active"`
	}
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)
	if callerID == id {
		return response.BadRequest(c, "you cannot deactivate your own account")
	}
	user, err := h.userRepo.FindByID(c.Request().Context(), id)
	if err != nil || user == nil {
		return response.NotFound(c, "user not found")
	}
	if user.Role == entity.RoleSuperAdmin {
		return response.BadRequest(c,
			"super-admin accounts cannot be deactivated from the panel")
	}
	if user.IsActive == req.Active {
		// Idempotent — return 200 either way so the UI can refresh state.
		return response.OK(c, map[string]any{
			"id": id.String(), "is_active": user.IsActive,
		})
	}
	user.IsActive = req.Active
	if err := h.userRepo.Update(c.Request().Context(), user); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]any{
		"id": id.String(), "is_active": user.IsActive,
	})
}

func (h *AdminHandler) ListPitches(c echo.Context) error {
	page, _ := strconv.Atoi(c.QueryParam("page"))
	limit, _ := strconv.Atoi(c.QueryParam("limit"))
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = 20
	}

	pitches, total, err := h.pitchRepo.ListAll(c.Request().Context(), page, limit)
	if err != nil {
		return response.InternalError(c)
	}

	pricing := service.NewPricingService(nil)
	items := make([]dto.AdminPitchResponse, len(pitches))
	for i, p := range pitches {
		// Resolve owner name
		ownerName := ""
		if owner, err := h.userRepo.FindByID(c.Request().Context(), p.OwnerID); err == nil {
			ownerName = owner.Name
		}
		var trialStr *string
		if p.TrialEndsAt != nil {
			s := p.TrialEndsAt.UTC().Format("2006-01-02T15:04:05Z")
			trialStr = &s
		}
		var premiumStr *string
		if p.PremiumActiveUntil != nil {
			s := p.PremiumActiveUntil.UTC().Format("2006-01-02T15:04:05Z")
			premiumStr = &s
		}
		items[i] = dto.AdminPitchResponse{
			ID:           p.ID.String(),
			Name:         p.Name,
			Address:      p.Address,
			City:         p.City,
			PricePerHour: p.PricePerHour,
			Surface:      p.Surface,
			Capacity:     p.Capacity,
			OwnerID:      p.OwnerID.String(),
			OwnerName:    ownerName,
			IsActive:     p.IsActive,
			CreatedAt:    p.CreatedAt.Format("2006-01-02T15:04:05Z"),

			Plan:                      p.Plan,
			MarketplaceFeeBpsOverride: p.MarketplaceFeeBpsOverride,
			WalkinFeeBpsOverride:      p.WalkinFeeBpsOverride,
			EffectiveCommissionBps:    pricing.ResolveCommissionBps(c.Request().Context(), p, "turfinn", 0),
			TrialEndsAt:               trialStr,
			PremiumActiveUntil:        premiumStr,
			MarketingBoostActive:      p.MarketingBoostActive,
		}
	}
	return response.OKPaginated(c, items, response.Meta{Page: page, Limit: limit, Total: total})
}

func (h *AdminHandler) TogglePitch(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid pitch id")
	}
	var req dto.TogglePitchRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}

	pitch, err := h.pitchRepo.FindByID(c.Request().Context(), id)
	if err != nil {
		return response.NotFound(c, "pitch not found")
	}
	pitch.IsActive = req.IsActive
	if err := h.pitchRepo.Update(c.Request().Context(), pitch); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]any{"id": id.String(), "is_active": req.IsActive})
}

func (h *AdminHandler) ListBookings(c echo.Context) error {
	page, _ := strconv.Atoi(c.QueryParam("page"))
	limit, _ := strconv.Atoi(c.QueryParam("limit"))
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = 20
	}

	filter := domain.BookingFilter{
		Status: c.QueryParam("status"),
		Page:   page,
		Limit:  limit,
	}
	if pid := c.QueryParam("pitch_id"); pid != "" {
		if id, err := uuid.Parse(pid); err == nil {
			filter.PitchID = &id
		}
	}

	bookings, total, err := h.bookingRepo.ListAll(c.Request().Context(), filter)
	if err != nil {
		return response.InternalError(c)
	}

	items := make([]dto.AdminBookingResponse, len(bookings))
	for i, b := range bookings {
		userPhone := ""
		if b.User.Phone != nil {
			userPhone = *b.User.Phone
		}
		items[i] = dto.AdminBookingResponse{
			ID:        b.ID.String(),
			PitchName: b.Pitch.Name,
			PitchID:   b.PitchID.String(),
			UserName:  b.User.Name,
			UserPhone: userPhone,
			UserID:    b.UserID.String(),
			StartsAt:  b.StartsAt.Format("2006-01-02T15:04:05Z"),
			EndsAt:    b.EndsAt.Format("2006-01-02T15:04:05Z"),
			TotalCost: b.TotalCost,
			Status:    string(b.Status),
			CreatedAt: b.CreatedAt.Format("2006-01-02T15:04:05Z"),
		}
	}
	return response.OKPaginated(c, items, response.Meta{Page: page, Limit: limit, Total: total})
}

func (h *AdminHandler) UpdateBookingStatus(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid booking id")
	}
	var req struct {
		Status string `json:"status" validate:"required,oneof=pending confirmed cancelled completed"`
	}
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	if err := h.bookingRepo.UpdateStatus(c.Request().Context(), id, entity.BookingStatus(req.Status)); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"id": id.String(), "status": req.Status})
}

func (h *AdminHandler) ListTeams(c echo.Context) error {
	page, _ := strconv.Atoi(c.QueryParam("page"))
	limit, _ := strconv.Atoi(c.QueryParam("limit"))
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = 20
	}

	teams, total, err := h.teamRepo.ListAll(c.Request().Context(), page, limit)
	if err != nil {
		return response.InternalError(c)
	}

	items := make([]dto.TeamResponse, len(teams))
	for i, t := range teams {
		items[i] = toTeamResp(t)
	}
	return response.OKPaginated(c, items, response.Meta{Page: page, Limit: limit, Total: total})
}

func (h *AdminHandler) ListMatches(c echo.Context) error {
	page, _ := strconv.Atoi(c.QueryParam("page"))
	limit, _ := strconv.Atoi(c.QueryParam("limit"))
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = 20
	}

	matches, total, err := h.teamRepo.ListAllMatches(c.Request().Context(), page, limit)
	if err != nil {
		return response.InternalError(c)
	}

	items := make([]dto.MatchResponse, len(matches))
	for i, m := range matches {
		mr := dto.MatchResponse{
			ID:        m.ID.String(),
			Format:    m.Format,
			Status:    string(m.Status),
			CreatedAt: m.CreatedAt.Format("2006-01-02T15:04:05Z"),
		}
		if m.ScheduledAt != nil {
			s := m.ScheduledAt.Format("2006-01-02T15:04:05Z")
			mr.ScheduledAt = &s
		}
		if m.HomeTeam != nil {
			ht := toTeamResp(*m.HomeTeam)
			mr.HomeTeam = &ht
		}
		if m.AwayTeam != nil {
			at := toTeamResp(*m.AwayTeam)
			mr.AwayTeam = &at
		}
		items[i] = mr
	}
	return response.OKPaginated(c, items, response.Meta{Page: page, Limit: limit, Total: total})
}

// helper shared with team_handler
func toTeamResp(t entity.Team) dto.TeamResponse {
	members := make([]dto.TeamMemberResponse, len(t.Members))
	for j, m := range t.Members {
		name := ""
		phone := ""
		if m.User != nil {
			name = m.User.Name
			if m.User.Phone != nil {
				phone = *m.User.Phone
			}
		}
		members[j] = dto.TeamMemberResponse{
			ID:       m.ID.String(),
			UserID:   m.UserID.String(),
			Name:     name,
			Phone:    phone,
			Position: m.Position,
			Number:   m.Number,
			Role:     string(m.Role),
		}
	}
	captainName := ""
	if t.Captain != nil {
		captainName = t.Captain.Name
	}
	_ = captainName
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

// AdminCreatePitch is the super-admin "Onboard New Turf" path. Accepts
// owner_id in the body (manager picked from a dropdown) — distinct from
// ManageHandler.CreatePitch which uses the caller's own user id as owner.
//
// owner_id is optional: if blank, the pitch is created unassigned and
// can be assigned later. lat/lng come from the map picker in the panel.
func (h *AdminHandler) CreatePitch(c echo.Context) error {
	var req struct {
		Name         string  `json:"name" validate:"required"`
		Description  string  `json:"description"`
		Address      string  `json:"address"`
		City         string  `json:"city" validate:"required"`
		Latitude     float64 `json:"latitude"`
		Longitude    float64 `json:"longitude"`
		PricePerHour float64 `json:"price_per_hour" validate:"required,gt=0"`
		Surface      string  `json:"surface"`
		Capacity     int     `json:"capacity"`
		ImageURL     string  `json:"image_url"`
		OwnerID      string  `json:"owner_id"`
	}
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	// Owner: explicit owner_id from the picker, or fall back to the caller
	// (super-admin). Either way the row gets a valid foreign key.
	var ownerID uuid.UUID
	if req.OwnerID != "" {
		id, err := uuid.Parse(req.OwnerID)
		if err != nil {
			return response.BadRequest(c, "invalid owner_id")
		}
		ownerID = id
	} else {
		ownerID = c.Get(mw.UserIDKey).(uuid.UUID)
	}

	pitch := entity.NewPitch(req.Name, req.Address, req.City, ownerID, req.PricePerHour)
	pitch.Description = req.Description
	pitch.Latitude = req.Latitude
	pitch.Longitude = req.Longitude
	pitch.Surface = req.Surface
	pitch.Capacity = req.Capacity
	pitch.ImageURLs = req.ImageURL
	// 60-day free trial (configurable via AVIV_TRIAL_DAYS) — applied on
	// every fresh onboarding so owners get to try the platform before
	// paying any commission.
	cfg := config.LoadMatchConfig()
	trialDays := cfg.TrialDays
	if trialDays <= 0 {
		trialDays = 60
	}
	trialEnd := time.Now().Add(time.Duration(trialDays) * 24 * time.Hour)
	pitch.TrialEndsAt = &trialEnd

	if err := h.pitchRepo.Create(c.Request().Context(), pitch); err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, map[string]any{
		"id":            pitch.ID.String(),
		"trial_ends_at": trialEnd.UTC().Format("2006-01-02T15:04:05Z"),
	})
}
