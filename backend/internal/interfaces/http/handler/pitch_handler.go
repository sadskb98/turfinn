package handler

import (
	"context"
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

type PitchHandler struct {
	pitchSvc *service.PitchService
}

func NewPitchHandler(pitchSvc *service.PitchService) *PitchHandler {
	return &PitchHandler{pitchSvc: pitchSvc}
}

// GET /api/v1/pitches
func (h *PitchHandler) List(c echo.Context) error {
	var q dto.ListPitchesQuery
	if err := c.Bind(&q); err != nil {
		return response.BadRequest(c, "invalid query params")
	}
	if q.Page < 1 {
		q.Page = 1
	}
	if q.Limit < 1 {
		q.Limit = 20
	}
	pitches, total, err := h.pitchSvc.List(c.Request().Context(), domain.PitchFilter{
		City:   q.City,
		Search: q.Search,
		Lat:    q.Lat,
		Lng:    q.Lng,
		Radius: q.Radius,
		Page:   q.Page,
		Limit:  q.Limit,
	})
	if err != nil {
		return response.InternalError(c)
	}
	return response.OKPaginated(c, toPitchResponses(pitches), response.Meta{
		Page: q.Page, Limit: q.Limit, Total: total,
	})
}

// GET /api/v1/pitches/:id
func (h *PitchHandler) GetByID(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid pitch id")
	}
	pitch, err := h.pitchSvc.GetByID(c.Request().Context(), id)
	if err != nil {
		return response.NotFound(c, "pitch not found")
	}
	return response.OK(c, toPitchResponse(pitch))
}

// POST /api/v1/pitches  (auth required)
func (h *PitchHandler) Create(c echo.Context) error {
	ownerID := c.Get(authmw.UserIDKey).(uuid.UUID)
	var req dto.CreatePitchRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	pitch, err := h.pitchSvc.Create(c.Request().Context(), ownerID, req)
	if err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, toPitchResponse(pitch))
}

// GET /api/v1/pitches/:id/slots?date=2026-04-15
func (h *PitchHandler) GetSlots(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid pitch id")
	}

	dateStr := c.QueryParam("date")
	if dateStr == "" {
		dateStr = time.Now().UTC().Format("2006-01-02")
	}
	date, err := time.Parse("2006-01-02", dateStr)
	if err != nil {
		return response.BadRequest(c, "invalid date format, use YYYY-MM-DD")
	}

	// Get all confirmed/pending bookings for this pitch on this date
	startOfDay := time.Date(date.Year(), date.Month(), date.Day(), 8, 0, 0, 0, time.UTC)
	endOfDay := time.Date(date.Year(), date.Month(), date.Day()+1, 0, 0, 0, 0, time.UTC)

	bookings, err := h.pitchSvc.GetBookingsForSlots(c.Request().Context(), id, startOfDay, endOfDay)
	if err != nil {
		return response.InternalError(c)
	}

	type Slot struct {
		Start     string `json:"start"`
		End       string `json:"end"`
		Available bool   `json:"available"`
	}

	var slots []Slot
	for hour := 8; hour < 24; hour++ {
		slotStart := time.Date(date.Year(), date.Month(), date.Day(), hour, 0, 0, 0, time.UTC)
		slotEnd := slotStart.Add(time.Hour)

		available := true
		for _, b := range bookings {
			if b.StartsAt.Before(slotEnd) && b.EndsAt.After(slotStart) {
				available = false
				break
			}
		}

		slots = append(slots, Slot{
			Start:     slotStart.Format(time.RFC3339),
			End:       slotEnd.Format(time.RFC3339),
			Available: available,
		})
	}

	return response.OK(c, slots)
}

func toPitchResponse(p *entity.Pitch) dto.PitchResponse {
	resp := dto.PitchResponse{
		ID:              p.ID.String(),
		Name:            p.Name,
		Description:     p.Description,
		Address:         p.Address,
		City:            p.City,
		Latitude:        p.Latitude,
		Longitude:       p.Longitude,
		PricePerHour:    p.PricePerHour,
		Surface:         p.Surface,
		Capacity:        p.Capacity,
		ImageURLs:       p.ImageURLs,
		IsActive:        p.IsActive,
		ServiceRadiusKM: p.ServiceRadiusKM,
		AllowsPartialPayment: p.AllowsPartialPayment,
		AllowsFullPayment:    p.AllowsFullPayment,
		DefaultPaymentMode:   p.DefaultPaymentMode,

		Plan:                      p.Plan,
		MarketplaceFeeBpsOverride: p.MarketplaceFeeBpsOverride,
		WalkinFeeBpsOverride:      p.WalkinFeeBpsOverride,
		MarketingBoostActive:      p.MarketingBoostActive,
	}
	if p.TrialEndsAt != nil {
		s := p.TrialEndsAt.UTC().Format("2006-01-02T15:04:05Z")
		resp.TrialEndsAt = &s
	}
	if p.PremiumActiveUntil != nil {
		s := p.PremiumActiveUntil.UTC().Format("2006-01-02T15:04:05Z")
		resp.PremiumActiveUntil = &s
	}
	// EffectiveCommissionBps: what a brand-new marketplace booking
	// would be charged right now. Computed via PricingService — kept
	// here as a quick UI hint without forcing the caller to do it.
	pricing := service.NewPricingService(nil) // resolver works without db
	resp.EffectiveCommissionBps = pricing.ResolveCommissionBps(context.TODO(), p, "turfinn", 0)
	return resp
}

func toPitchResponses(pitches []*entity.Pitch) []dto.PitchResponse {
	out := make([]dto.PitchResponse, len(pitches))
	for i, p := range pitches {
		out[i] = toPitchResponse(p)
	}
	return out
}
