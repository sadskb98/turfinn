package handler

import (
	"encoding/json"
	"html"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/interfaces/dto"
	"github.com/turfinn/backend/internal/pkg/response"
	"gorm.io/gorm"
)

type ManagerCampaignsHandler struct {
	db *gorm.DB
}

func NewManagerCampaignsHandler(db *gorm.DB) *ManagerCampaignsHandler {
	return &ManagerCampaignsHandler{db: db}
}

// GET /api/v1/manager/promos
func (h *ManagerCampaignsHandler) ListPromos(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}

	var promos []entity.PromoCode
	if err := h.db.WithContext(c.Request().Context()).
		Where("owner_id = ?", managerID).
		Order("created_at DESC").
		Find(&promos).Error; err != nil {
		return response.InternalError(c)
	}

	out := make([]dto.ManagerPromoResponse, len(promos))
	for i, p := range promos {
		out[i] = dto.ManagerPromoResponse{
			ID:            p.ID.String(),
			Code:          p.Code,
			DiscountType:  p.DiscountType,
			DiscountValue: p.DiscountValue,
			MaxUses:       p.MaxUses,
			UsedCount:     p.UsedCount,
			ValidFrom:     p.ValidFrom.Format("2006-01-02"),
			ValidTo:       p.ValidTo.Format("2006-01-02"),
			IsActive:      p.IsActive,
			CreatedAt:     p.CreatedAt.Format("2006-01-02T15:04:05Z"),
		}
	}
	return response.OK(c, out)
}

// POST /api/v1/manager/promos
func (h *ManagerCampaignsHandler) CreatePromo(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}

	var req dto.CreateManagerPromoRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	validFrom, err := time.Parse("2006-01-02", req.ValidFrom)
	if err != nil {
		return response.BadRequest(c, "invalid valid_from date")
	}
	validTo, err := time.Parse("2006-01-02", req.ValidTo)
	if err != nil {
		return response.BadRequest(c, "invalid valid_to date")
	}
	if validTo.Before(validFrom) {
		return response.BadRequest(c, "valid_to must be after valid_from")
	}

	code := html.EscapeString(strings.ToUpper(strings.TrimSpace(req.Code)))

	// Check uniqueness
	var count int64
	h.db.WithContext(c.Request().Context()).
		Model(&entity.PromoCode{}).
		Where("UPPER(code) = ?", code).
		Count(&count)
	if count > 0 {
		return response.Conflict(c, "promo code already exists")
	}

	// Get manager's pitch IDs to scope the promo
	var pitchIDs []string
	h.db.WithContext(c.Request().Context()).
		Model(&entity.Pitch{}).
		Where("owner_id = ?", managerID).
		Pluck("id::text", &pitchIDs)

	// pitch_ids is JSONB — must be a valid JSON array
	pitchIDsJSON, _ := json.Marshal(pitchIDs)

	promo := entity.PromoCode{
		ID:            uuid.New(),
		Code:          code,
		DiscountType:  req.DiscountType,
		DiscountValue: req.DiscountValue,
		MaxUses:       req.MaxUses,
		PerUserLimit:  1,
		PitchIDs:      string(pitchIDsJSON),
		ValidFrom:     validFrom,
		ValidTo:       validTo,
		CreatedBy:     managerID,
		IsActive:      true,
		OwnerID:       &managerID,
	}
	if err := h.db.WithContext(c.Request().Context()).Create(&promo).Error; err != nil {
		return response.InternalError(c)
	}

	return response.Created(c, dto.ManagerPromoResponse{
		ID:            promo.ID.String(),
		Code:          promo.Code,
		DiscountType:  promo.DiscountType,
		DiscountValue: promo.DiscountValue,
		MaxUses:       promo.MaxUses,
		UsedCount:     0,
		ValidFrom:     promo.ValidFrom.Format("2006-01-02"),
		ValidTo:       promo.ValidTo.Format("2006-01-02"),
		IsActive:      true,
		CreatedAt:     promo.CreatedAt.Format("2006-01-02T15:04:05Z"),
	})
}

// PUT /api/v1/manager/promos/:id/deactivate
func (h *ManagerCampaignsHandler) DeactivatePromo(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}

	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid promo id")
	}

	result := h.db.WithContext(c.Request().Context()).
		Model(&entity.PromoCode{}).
		Where("id = ? AND owner_id = ?", id, managerID).
		Update("is_active", false)
	if result.Error != nil {
		return response.InternalError(c)
	}
	if result.RowsAffected == 0 {
		return response.NotFound(c, "promo not found or not owned by you")
	}
	return response.OK(c, map[string]string{"message": "promo deactivated"})
}
