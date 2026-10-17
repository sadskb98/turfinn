package handler

import (
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"github.com/turfinn/backend/internal/interfaces/dto"
	mw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type MarketingHandler struct {
	repo domain.MarketingRepository
}

func NewMarketingHandler(r domain.MarketingRepository) *MarketingHandler {
	return &MarketingHandler{repo: r}
}

func paginationDefaults(c echo.Context) (int, int) {
	page, _ := strconv.Atoi(c.QueryParam("page"))
	limit, _ := strconv.Atoi(c.QueryParam("limit"))
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = 20
	}
	return page, limit
}

// ── Promo Codes ──────────────────────────────────────────────────────────────

func (h *MarketingHandler) ListPromoCodes(c echo.Context) error {
	page, limit := paginationDefaults(c)
	items, total, err := h.repo.ListPromoCodes(c.Request().Context(), page, limit)
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.PromoCodeResponse, len(items))
	for i, p := range items {
		resp[i] = dto.PromoCodeResponse{
			ID: p.ID.String(), Code: p.Code, DiscountType: p.DiscountType,
			DiscountValue: p.DiscountValue, MinBookingAmount: p.MinBookingAmount,
			MaxUses: p.MaxUses, UsedCount: p.UsedCount, PerUserLimit: p.PerUserLimit,
			PitchIDs: p.PitchIDs, ValidFrom: p.ValidFrom.Format("2006-01-02T15:04:05Z"),
			ValidTo: p.ValidTo.Format("2006-01-02T15:04:05Z"), IsActive: p.IsActive,
			CreatedAt: p.CreatedAt.Format("2006-01-02T15:04:05Z"),
		}
	}
	return response.OKPaginated(c, resp, response.Meta{Page: page, Limit: limit, Total: total})
}

func (h *MarketingHandler) CreatePromoCode(c echo.Context) error {
	var req dto.CreatePromoCodeRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)
	validFrom, _ := time.Parse("2006-01-02T15:04:05Z", req.ValidFrom)
	validTo, _ := time.Parse("2006-01-02T15:04:05Z", req.ValidTo)

	p := &entity.PromoCode{
		Code: req.Code, DiscountType: req.DiscountType, DiscountValue: req.DiscountValue,
		MinBookingAmount: req.MinBookingAmount, MaxUses: req.MaxUses, PerUserLimit: req.PerUserLimit,
		PitchIDs: req.PitchIDs, ValidFrom: validFrom, ValidTo: validTo,
		CreatedBy: callerID, IsActive: true,
	}
	if err := h.repo.CreatePromoCode(c.Request().Context(), p); err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, map[string]string{"id": p.ID.String()})
}

func (h *MarketingHandler) DeactivatePromoCode(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	p, err := h.repo.GetPromoCode(c.Request().Context(), id)
	if err != nil {
		return response.NotFound(c, "promo code not found")
	}
	p.IsActive = false
	if err := h.repo.UpdatePromoCode(c.Request().Context(), p); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"id": id.String(), "status": "deactivated"})
}

func (h *MarketingHandler) GetPromoUsage(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	page, limit := paginationDefaults(c)
	items, total, err := h.repo.ListPromoUsage(c.Request().Context(), id, page, limit)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OKPaginated(c, items, response.Meta{Page: page, Limit: limit, Total: total})
}

// ── Campaigns ────────────────────────────────────────────────────────────────

func (h *MarketingHandler) ListCampaigns(c echo.Context) error {
	page, limit := paginationDefaults(c)
	items, total, err := h.repo.ListCampaigns(c.Request().Context(), page, limit)
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.CampaignResponse, len(items))
	for i, cm := range items {
		r := dto.CampaignResponse{
			ID: cm.ID.String(), Title: cm.Title, Body: cm.Body,
			SegmentType: cm.SegmentType, SegmentParams: cm.SegmentParams,
			SentCount: cm.SentCount, CreatedAt: cm.CreatedAt.Format("2006-01-02T15:04:05Z"),
		}
		if cm.ScheduledAt != nil {
			r.ScheduledAt = cm.ScheduledAt.Format("2006-01-02T15:04:05Z")
		}
		if cm.SentAt != nil {
			r.SentAt = cm.SentAt.Format("2006-01-02T15:04:05Z")
		}
		resp[i] = r
	}
	return response.OKPaginated(c, resp, response.Meta{Page: page, Limit: limit, Total: total})
}

func (h *MarketingHandler) CreateCampaign(c echo.Context) error {
	var req dto.CreateCampaignRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)
	cm := &entity.NotificationCampaign{
		Title: req.Title, Body: req.Body, SegmentType: req.SegmentType,
		SegmentParams: req.SegmentParams, CreatedBy: callerID,
	}
	if req.ScheduledAt != "" {
		t, _ := time.Parse("2006-01-02T15:04:05Z", req.ScheduledAt)
		cm.ScheduledAt = &t
	}
	if err := h.repo.CreateCampaign(c.Request().Context(), cm); err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, map[string]string{"id": cm.ID.String()})
}

func (h *MarketingHandler) SendCampaign(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	cm, err := h.repo.GetCampaign(c.Request().Context(), id)
	if err != nil {
		return response.NotFound(c, "campaign not found")
	}
	now := time.Now()
	cm.SentAt = &now
	if err := h.repo.UpdateCampaign(c.Request().Context(), cm); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"id": id.String(), "status": "sent"})
}

// ── Featured Pitches ─────────────────────────────────────────────────────────

func (h *MarketingHandler) ListFeaturedPitches(c echo.Context) error {
	items, err := h.repo.ListFeaturedPitches(c.Request().Context())
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.FeaturedPitchResponse, len(items))
	for i, f := range items {
		pitchName := ""
		if f.Pitch != nil {
			pitchName = f.Pitch.Name
		}
		resp[i] = dto.FeaturedPitchResponse{
			ID: f.ID.String(), PitchID: f.PitchID.String(), PitchName: pitchName,
			Position: f.Position, StartsAt: f.StartsAt.Format("2006-01-02T15:04:05Z"),
			EndsAt: f.EndsAt.Format("2006-01-02T15:04:05Z"), AmountPaid: f.AmountPaid,
		}
	}
	return response.OK(c, resp)
}

func (h *MarketingHandler) CreateFeaturedPitch(c echo.Context) error {
	var req dto.CreateFeaturedPitchRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	pitchID, _ := uuid.Parse(req.PitchID)
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)
	startsAt, _ := time.Parse("2006-01-02T15:04:05Z", req.StartsAt)
	endsAt, _ := time.Parse("2006-01-02T15:04:05Z", req.EndsAt)

	f := &entity.FeaturedPitch{
		PitchID: pitchID, Position: req.Position, StartsAt: startsAt,
		EndsAt: endsAt, AmountPaid: req.AmountPaid, CreatedBy: callerID,
	}
	if err := h.repo.CreateFeaturedPitch(c.Request().Context(), f); err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, map[string]string{"id": f.ID.String()})
}

func (h *MarketingHandler) DeleteFeaturedPitch(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	if err := h.repo.DeleteFeaturedPitch(c.Request().Context(), id); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"status": "deleted"})
}

// ── Referrals ────────────────────────────────────────────────────────────────

func (h *MarketingHandler) GetReferralStats(c echo.Context) error {
	total, rewarded, rewardsPaisa, err := h.repo.GetReferralStats(c.Request().Context())
	if err != nil {
		return response.InternalError(c)
	}
	var rate float64
	if total > 0 {
		rate = float64(rewarded) / float64(total) * 100
	}
	return response.OK(c, dto.ReferralStatsResponse{
		TotalReferrals: total, TotalRewarded: rewarded,
		TotalRewardsPaisa: rewardsPaisa, ConversionRate: rate,
	})
}

// ── Banners ──────────────────────────────────────────────────────────────────

func (h *MarketingHandler) ListBanners(c echo.Context) error {
	items, err := h.repo.ListBanners(c.Request().Context())
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.BannerResponse, len(items))
	for i, b := range items {
		r := dto.BannerResponse{
			ID: b.ID.String(), ImageURL: b.ImageURL, Title: b.Title,
			CtaURL: b.CtaURL, DisplayOrder: b.DisplayOrder, IsActive: b.IsActive,
		}
		if b.StartsAt != nil {
			r.StartsAt = b.StartsAt.Format("2006-01-02T15:04:05Z")
		}
		if b.EndsAt != nil {
			r.EndsAt = b.EndsAt.Format("2006-01-02T15:04:05Z")
		}
		resp[i] = r
	}
	return response.OK(c, resp)
}

func (h *MarketingHandler) ListActiveBanners(c echo.Context) error {
	items, err := h.repo.ListActiveBanners(c.Request().Context())
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.BannerResponse, len(items))
	for i, b := range items {
		resp[i] = dto.BannerResponse{
			ID: b.ID.String(), ImageURL: b.ImageURL, Title: b.Title,
			CtaURL: b.CtaURL, DisplayOrder: b.DisplayOrder, IsActive: b.IsActive,
		}
	}
	return response.OK(c, resp)
}

func (h *MarketingHandler) CreateBanner(c echo.Context) error {
	var req dto.CreateBannerRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	b := &entity.Banner{
		ImageURL: req.ImageURL, Title: req.Title, CtaURL: req.CtaURL,
		DisplayOrder: req.DisplayOrder, IsActive: true,
	}
	if req.StartsAt != "" {
		t, _ := time.Parse("2006-01-02T15:04:05Z", req.StartsAt)
		b.StartsAt = &t
	}
	if req.EndsAt != "" {
		t, _ := time.Parse("2006-01-02T15:04:05Z", req.EndsAt)
		b.EndsAt = &t
	}
	if err := h.repo.CreateBanner(c.Request().Context(), b); err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, map[string]string{"id": b.ID.String()})
}

func (h *MarketingHandler) DeleteBanner(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	if err := h.repo.DeleteBanner(c.Request().Context(), id); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"status": "deleted"})
}
