package handler

import (
	"strconv"
	"strings"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"github.com/turfinn/backend/internal/interfaces/dto"
	mw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type PlatformHandler struct {
	repo domain.PlatformRepository
}

func NewPlatformHandler(r domain.PlatformRepository) *PlatformHandler {
	return &PlatformHandler{repo: r}
}

func (h *PlatformHandler) GetSettings(c echo.Context) error {
	settings, err := h.repo.GetAllSettings(c.Request().Context())
	if err != nil {
		return response.InternalError(c)
	}
	items := make([]dto.SettingsResponse, len(settings))
	for i, s := range settings {
		items[i] = dto.SettingsResponse{
			Key:         s.Key,
			Value:       s.Value,
			Description: s.Description,
			UpdatedAt:   s.UpdatedAt.Format("2006-01-02T15:04:05Z"),
		}
	}
	return response.OK(c, items)
}

func (h *PlatformHandler) UpdateSettings(c echo.Context) error {
	var req dto.UpdateSettingsRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)
	if err := h.repo.UpdateSettings(c.Request().Context(), req.Settings, callerID); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"status": "updated"})
}

func (h *PlatformHandler) GetSettingsAudit(c echo.Context) error {
	page, _ := strconv.Atoi(c.QueryParam("page"))
	limit, _ := strconv.Atoi(c.QueryParam("limit"))
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = 20
	}
	items, total, err := h.repo.ListSettingsAudit(c.Request().Context(), page, limit)
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.SettingsAuditResponse, len(items))
	for i, a := range items {
		resp[i] = dto.SettingsAuditResponse{
			ID:         a.ID.String(),
			SettingKey: a.SettingKey,
			OldValue:   a.OldValue,
			NewValue:   a.NewValue,
			ChangedBy:  a.ChangedBy.String(),
			ChangedAt:  a.ChangedAt.Format("2006-01-02T15:04:05Z"),
		}
	}
	return response.OKPaginated(c, resp, response.Meta{Page: page, Limit: limit, Total: total})
}

func (h *PlatformHandler) ListPricingRules(c echo.Context) error {
	rules, err := h.repo.ListPricingRules(c.Request().Context())
	if err != nil {
		return response.InternalError(c)
	}
	items := make([]dto.PricingRuleResponse, len(rules))
	for i, r := range rules {
		items[i] = dto.PricingRuleResponse{
			ID:            r.ID.String(),
			RuleType:      r.RuleType,
			Name:          r.Name,
			Multiplier:    r.Multiplier,
			FixedAmount:   r.FixedAmount,
			AppliesToDays: r.AppliesToDays,
			TimeFrom:      r.TimeFrom,
			TimeTo:        r.TimeTo,
			IsActive:      r.IsActive,
			CreatedAt:     r.CreatedAt.Format("2006-01-02T15:04:05Z"),
		}
	}
	return response.OK(c, items)
}

func (h *PlatformHandler) CreatePricingRule(c echo.Context) error {
	var req dto.CreatePricingRuleRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)
	rule := &entity.PricingRule{
		RuleType:      req.RuleType,
		Name:          req.Name,
		Multiplier:    req.Multiplier,
		FixedAmount:   req.FixedAmount,
		AppliesToDays: req.AppliesToDays,
		TimeFrom:      req.TimeFrom,
		TimeTo:        req.TimeTo,
		IsActive:      true,
		CreatedBy:     callerID,
	}
	if err := h.repo.CreatePricingRule(c.Request().Context(), rule); err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, map[string]string{"id": rule.ID.String()})
}

func (h *PlatformHandler) DeletePricingRule(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	if err := h.repo.DeletePricingRule(c.Request().Context(), id); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"status": "deleted"})
}

func (h *PlatformHandler) GetFlags(c echo.Context) error {
	flags, err := h.repo.GetAllFlags(c.Request().Context())
	if err != nil {
		return response.InternalError(c)
	}
	items := make([]dto.FeatureFlagResponse, len(flags))
	for i, f := range flags {
		items[i] = dto.FeatureFlagResponse{
			Key:         f.Key,
			Enabled:     f.Enabled,
			Description: f.Description,
			UpdatedAt:   f.UpdatedAt.Format("2006-01-02T15:04:05Z"),
		}
	}
	return response.OK(c, items)
}

func (h *PlatformHandler) UpdateFlag(c echo.Context) error {
	key := c.Param("key")
	var req dto.UpdateFlagRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)
	if err := h.repo.UpdateFlag(c.Request().Context(), key, req.Enabled, callerID); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]any{"key": key, "enabled": req.Enabled})
}

func (h *PlatformHandler) GetPublicConfig(c echo.Context) error {
	flags, err := h.repo.GetAllFlags(c.Request().Context())
	if err != nil {
		return response.InternalError(c)
	}
	settings, err := h.repo.GetAllSettings(c.Request().Context())
	if err != nil {
		return response.InternalError(c)
	}
	flagMap := make(map[string]bool)
	for _, f := range flags {
		flagMap[f.Key] = f.Enabled
	}
	maintenance := make(map[string]bool)
	for _, s := range settings {
		if strings.HasSuffix(s.Key, "_maintenance_mode") {
			maintenance[s.Key] = s.Value == "true"
		}
	}
	return response.OK(c, map[string]any{"feature_flags": flagMap, "maintenance": maintenance})
}

func (h *PlatformHandler) ListTemplates(c echo.Context) error {
	templates, err := h.repo.ListTemplates(c.Request().Context())
	if err != nil {
		return response.InternalError(c)
	}
	items := make([]dto.NotificationTemplateResponse, len(templates))
	for i, t := range templates {
		items[i] = dto.NotificationTemplateResponse{
			ID: t.ID.String(), Type: t.Type, Channel: t.Channel,
			Subject: t.Subject, Body: t.Body, Variables: t.Variables, IsActive: t.IsActive,
		}
	}
	return response.OK(c, items)
}

func (h *PlatformHandler) CreateTemplate(c echo.Context) error {
	var req dto.CreateTemplateRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	t := &entity.NotificationTemplate{
		Type: req.Type, Channel: req.Channel, Subject: req.Subject,
		Body: req.Body, Variables: req.Variables, IsActive: true,
	}
	if err := h.repo.CreateTemplate(c.Request().Context(), t); err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, map[string]string{"id": t.ID.String()})
}

func (h *PlatformHandler) DeleteTemplate(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	if err := h.repo.DeleteTemplate(c.Request().Context(), id); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"status": "deleted"})
}

func (h *PlatformHandler) PreviewTemplate(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	var req dto.PreviewTemplateRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	t, err := h.repo.GetTemplate(c.Request().Context(), id)
	if err != nil {
		return response.NotFound(c, "template not found")
	}
	rendered := t.Body
	for k, v := range req.Values {
		rendered = strings.ReplaceAll(rendered, "{{"+k+"}}", v)
	}
	return response.OK(c, map[string]string{"rendered": rendered})
}
