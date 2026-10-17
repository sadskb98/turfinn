package handler

import (
	"context"
	"html"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"github.com/turfinn/backend/internal/interfaces/dto"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type MatchPostHandler struct {
	svc     *service.MatchPostService
	paySvc  *service.MatchJoinPaymentService
}

func NewMatchPostHandler(svc *service.MatchPostService, paySvc *service.MatchJoinPaymentService) *MatchPostHandler {
	return &MatchPostHandler{svc: svc, paySvc: paySvc}
}

// POST /api/v1/feed
//
// Creates a match post anchored to a Turfinn pitch + slot. The service:
//   - validates the pitch exists and is active
//   - rejects if any confirmed booking overlaps the requested slot
//   - computes per-head cost from pitch rate × duration ÷ spots
//   - applies the Consul-tunable join fee
func (h *MatchPostHandler) Create(c echo.Context) error {
	var req dto.CreateMatchPostRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	pitchID, err := uuid.Parse(req.PitchID)
	if err != nil {
		return response.BadRequest(c, "invalid pitch_id")
	}

	userID := c.Get(authmw.UserIDKey).(uuid.UUID)

	post, err := h.svc.CreateForPitch(c.Request().Context(), service.CreateMatchPostInput{
		AuthorID:        userID,
		PitchID:         pitchID,
		Title:           html.EscapeString(strings.TrimSpace(req.Title)),
		Description:     html.EscapeString(strings.TrimSpace(req.Description)),
		MatchDate:       req.MatchDate,
		DurationMinutes: req.DurationMinutes,
		Format:          req.Format,
		SpotsTotal:      req.SpotsTotal,
		PostType:        req.PostType,
	})
	if err != nil {
		return response.BadRequest(c, err.Error())
	}
	return response.Created(c, map[string]string{"id": post.ID.String()})
}

// GET /api/v1/feed
func (h *MatchPostHandler) List(c echo.Context) error {
	page, limit := 1, 20
	if p := c.QueryParam("page"); p != "" {
		if v, err := strconv.Atoi(p); err == nil && v > 0 {
			page = v
		}
	}
	if l := c.QueryParam("limit"); l != "" {
		if v, err := strconv.Atoi(l); err == nil && v > 0 {
			limit = v
		}
	}

	var lat, lng, radius float64
	if v, err := strconv.ParseFloat(c.QueryParam("lat"), 64); err == nil {
		lat = v
	}
	if v, err := strconv.ParseFloat(c.QueryParam("lng"), 64); err == nil {
		lng = v
	}
	if v, err := strconv.ParseFloat(c.QueryParam("radius"), 64); err == nil && v > 0 {
		radius = v
	} else {
		radius = 10
	}
	postType := c.QueryParam("post_type")

	// Update caller's last known location (fire-and-forget)
	if lat != 0 && lng != 0 {
		if userID, ok := c.Get(authmw.UserIDKey).(uuid.UUID); ok {
			go h.svc.UpdateUserLocation(context.Background(), userID, lat, lng)
		}
	}

	posts, total, err := h.svc.List(c.Request().Context(), domain.MatchPostFilter{
		Lat:      lat,
		Lng:      lng,
		Radius:   radius,
		PostType: postType,
		Page:     page,
		Limit:    limit,
	})
	if err != nil {
		return response.InternalError(c)
	}

	currentUserID, _ := c.Get(authmw.UserIDKey).(uuid.UUID)
	joinedSet := h.joinedSet(c.Request().Context(), currentUserID, posts)

	resp := make([]dto.MatchPostResponse, 0, len(posts))
	for _, p := range posts {
		venueKind := "custom"
		if p.PitchID != nil {
			venueKind = "turfinn"
		} else if p.ExternalPitchID != nil {
			venueKind = "external"
		}
		r := dto.MatchPostResponse{
			ID:              p.ID.String(),
			AuthorID:        p.AuthorID.String(),
			AuthorName:      p.Author.Name,
			VenueKind:       venueKind,
			Title:           p.Title,
			Description:     p.Description,
			MatchDate:       p.MatchDate.Format(time.RFC3339),
			DurationMinutes: p.DurationMinutes,
			Format:          p.Format,
			SpotsTotal:      p.SpotsTotal,
			SpotsFilled:     p.SpotsFilled,
			JoinFeeBDT:      p.JoinFeeBDT,
			PerHeadCostBDT:  p.PerHeadCostBDT,
			Status:          p.Status,
			PostType:        p.PostType,
			Latitude:        p.Latitude,
			Longitude:       p.Longitude,
			CreatedAt:       p.CreatedAt.Format(time.RFC3339),
		}
		if p.PitchID != nil {
			pid := p.PitchID.String()
			r.PitchID = &pid
			if p.Pitch != nil {
				name := p.Pitch.Name
				r.PitchName = &name
			}
		}
		if p.ExternalPitchID != nil && p.ExternalPitch != nil {
			r.ExternalPitch = &dto.ExternalPitchResponse{
				ID:        p.ExternalPitch.ID.String(),
				Name:      p.ExternalPitch.Name,
				Address:   p.ExternalPitch.Address,
				Latitude:  p.ExternalPitch.Latitude,
				Longitude: p.ExternalPitch.Longitude,
				RefCount:  p.ExternalPitch.RefCount,
				Verified:  p.ExternalPitch.Verified,
			}
		}
		if lat != 0 && lng != 0 && p.Latitude != 0 {
			d := haversine(lat, lng, p.Latitude, p.Longitude)
			r.DistanceKm = &d
		}
		r.IsHost = currentUserID != uuid.Nil && p.AuthorID == currentUserID
		r.IsJoined = joinedSet[p.ID]
		resp = append(resp, r)
	}
	return response.OKPaginated(c, resp, response.Meta{Page: page, Limit: limit, Total: total})
}

// joinedSet returns a map of post-IDs the user has joined, scoped to the
// posts in this batch. Empty for unauthenticated callers.
func (h *MatchPostHandler) joinedSet(
	ctx context.Context,
	userID uuid.UUID,
	posts []entity.MatchPost,
) map[uuid.UUID]bool {
	if userID == uuid.Nil || len(posts) == 0 {
		return map[uuid.UUID]bool{}
	}
	ids := make([]uuid.UUID, 0, len(posts))
	for _, p := range posts {
		ids = append(ids, p.ID)
	}
	got, err := h.svc.JoinedPostIDs(ctx, userID, ids)
	if err != nil {
		return map[uuid.UUID]bool{}
	}
	return got
}

// GET /api/v1/feed/:id — single match detail.
func (h *MatchPostHandler) GetByID(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	post, err := h.svc.FindByID(c.Request().Context(), id)
	if err != nil || post == nil {
		return response.NotFound(c, "match not found")
	}
	venueKind := "custom"
	if post.PitchID != nil {
		venueKind = "turfinn"
	} else if post.ExternalPitchID != nil {
		venueKind = "external"
	}
	r := dto.MatchPostResponse{
		ID:              post.ID.String(),
		AuthorID:        post.AuthorID.String(),
		AuthorName:      post.Author.Name,
		VenueKind:       venueKind,
		Title:           post.Title,
		Description:     post.Description,
		MatchDate:       post.MatchDate.Format(time.RFC3339),
		DurationMinutes: post.DurationMinutes,
		Format:          post.Format,
		SpotsTotal:      post.SpotsTotal,
		SpotsFilled:     post.SpotsFilled,
		JoinFeeBDT:      post.JoinFeeBDT,
		PerHeadCostBDT:  post.PerHeadCostBDT,
		Status:          post.Status,
		PostType:        post.PostType,
		Latitude:        post.Latitude,
		Longitude:       post.Longitude,
		CreatedAt:       post.CreatedAt.Format(time.RFC3339),
	}
	if post.PitchID != nil {
		pid := post.PitchID.String()
		r.PitchID = &pid
		if post.Pitch != nil {
			name := post.Pitch.Name
			r.PitchName = &name
		}
	}
	if currentUserID, ok := c.Get(authmw.UserIDKey).(uuid.UUID); ok {
		r.IsHost = post.AuthorID == currentUserID
		joined, _ := h.svc.JoinedPostIDs(c.Request().Context(), currentUserID, []uuid.UUID{post.ID})
		r.IsJoined = joined[post.ID]
		payInfo, _ := h.paySvc.PaymentStatusFor(c.Request().Context(), currentUserID, []uuid.UUID{post.ID})
		if info, ok := payInfo[post.ID]; ok {
			r.MyPaymentStatus = info.Status
			r.MyRefundStatus = info.RefundStatus
		}
	}
	return response.OK(c, r)
}

// GET /api/v1/feed/mine?scope=upcoming  — matches the caller hosts or joined.
func (h *MatchPostHandler) ListMine(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	scope := c.QueryParam("scope")
	page, limit := 1, 20
	if p := c.QueryParam("page"); p != "" {
		if v, err := strconv.Atoi(p); err == nil && v > 0 {
			page = v
		}
	}
	if l := c.QueryParam("limit"); l != "" {
		if v, err := strconv.Atoi(l); err == nil && v > 0 && v <= 50 {
			limit = v
		}
	}
	posts, total, err := h.svc.ListMine(c.Request().Context(), userID, scope, page, limit)
	if err != nil {
		return response.InternalError(c)
	}
	postIDs := make([]uuid.UUID, len(posts))
	for i, p := range posts {
		postIDs[i] = p.ID
	}
	payInfo, _ := h.paySvc.PaymentStatusFor(c.Request().Context(), userID, postIDs)
	resp := make([]dto.MatchPostResponse, 0, len(posts))
	for _, p := range posts {
		venueKind := "custom"
		if p.PitchID != nil {
			venueKind = "turfinn"
		} else if p.ExternalPitchID != nil {
			venueKind = "external"
		}
		r := dto.MatchPostResponse{
			ID:              p.ID.String(),
			AuthorID:        p.AuthorID.String(),
			AuthorName:      p.Author.Name,
			VenueKind:       venueKind,
			Title:           p.Title,
			Description:     p.Description,
			MatchDate:       p.MatchDate.Format(time.RFC3339),
			DurationMinutes: p.DurationMinutes,
			Format:          p.Format,
			SpotsTotal:      p.SpotsTotal,
			SpotsFilled:     p.SpotsFilled,
			JoinFeeBDT:      p.JoinFeeBDT,
			PerHeadCostBDT:  p.PerHeadCostBDT,
			Status:          p.Status,
			PostType:        p.PostType,
			Latitude:        p.Latitude,
			Longitude:       p.Longitude,
			CreatedAt:       p.CreatedAt.Format(time.RFC3339),
		}
		if p.PitchID != nil {
			pid := p.PitchID.String()
			r.PitchID = &pid
			if p.Pitch != nil {
				name := p.Pitch.Name
				r.PitchName = &name
			}
		}
		r.IsHost = p.AuthorID == userID
		r.IsJoined = !r.IsHost // anything in /feed/mine that isn't hosted is joined
		if info, ok := payInfo[p.ID]; ok {
			r.MyPaymentStatus = info.Status
			r.MyRefundStatus = info.RefundStatus
		}
		resp = append(resp, r)
	}
	return response.OKPaginated(c, resp, response.Meta{Page: page, Limit: limit, Total: total})
}

// POST /api/v1/feed/:id/join
func (h *MatchPostHandler) Join(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	if err := h.svc.Join(c.Request().Context(), id, userID); err != nil {
		return response.BadRequest(c, err.Error())
	}
	return response.OK(c, map[string]string{"status": "joined"})
}

// POST /api/v1/feed/:id/report
func (h *MatchPostHandler) Report(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	var req dto.ReportMatchPostRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	if err := h.svc.Report(c.Request().Context(), id, userID, req.TargetKind, req.Reason, req.Note); err != nil {
		return response.BadRequest(c, err.Error())
	}
	return response.OK(c, map[string]string{"status": "reported"})
}

// GET /api/v1/external-pitches?q=&lat=&lng=&limit=
func (h *MatchPostHandler) SearchExternalPitches(c echo.Context) error {
	repo := h.svc.ExternalPitchRepo()
	if repo == nil {
		return response.OK(c, []dto.ExternalPitchResponse{})
	}
	q := c.QueryParam("q")
	limit := 10
	if l := c.QueryParam("limit"); l != "" {
		if v, err := strconv.Atoi(l); err == nil && v > 0 && v <= 50 {
			limit = v
		}
	}
	var lat, lng float64
	if v, err := strconv.ParseFloat(c.QueryParam("lat"), 64); err == nil {
		lat = v
	}
	if v, err := strconv.ParseFloat(c.QueryParam("lng"), 64); err == nil {
		lng = v
	}
	items, err := repo.Search(c.Request().Context(), q, lat, lng, limit)
	if err != nil {
		return response.InternalError(c)
	}
	out := make([]dto.ExternalPitchResponse, 0, len(items))
	for _, p := range items {
		out = append(out, dto.ExternalPitchResponse{
			ID:        p.ID.String(),
			Name:      p.Name,
			Address:   p.Address,
			Latitude:  p.Latitude,
			Longitude: p.Longitude,
			RefCount:  p.RefCount,
			Verified:  p.Verified,
		})
	}
	return response.OK(c, out)
}

// POST /api/v1/external-pitches
func (h *MatchPostHandler) CreateExternalPitch(c echo.Context) error {
	repo := h.svc.ExternalPitchRepo()
	if repo == nil {
		return response.InternalError(c)
	}
	var req dto.CreateExternalPitchRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	userID, _ := c.Get(authmw.UserIDKey).(uuid.UUID)
	p := &entity.ExternalPitch{
		Name:      strings.TrimSpace(req.Name),
		Address:   strings.TrimSpace(req.Address),
		Latitude:  req.Latitude,
		Longitude: req.Longitude,
		CreatedBy: &userID,
	}
	saved, err := repo.FindOrCreate(c.Request().Context(), p)
	if err != nil {
		return response.BadRequest(c, err.Error())
	}
	return response.OK(c, dto.ExternalPitchResponse{
		ID:        saved.ID.String(),
		Name:      saved.Name,
		Address:   saved.Address,
		Latitude:  saved.Latitude,
		Longitude: saved.Longitude,
		RefCount:  saved.RefCount,
		Verified:  saved.Verified,
	})
}

func haversine(lat1, lng1, lat2, lng2 float64) float64 {
	const R = 6371
	dLat := (lat2 - lat1) * math.Pi / 180
	dLng := (lng2 - lng1) * math.Pi / 180
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*math.Pi/180)*math.Cos(lat2*math.Pi/180)*
		math.Sin(dLng/2)*math.Sin(dLng/2)
	return R * 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}
