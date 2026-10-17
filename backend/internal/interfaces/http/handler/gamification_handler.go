package handler

import (
	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/application/service"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type GamificationHandler struct {
	svc *service.GamificationService
}

func NewGamificationHandler(svc *service.GamificationService) *GamificationHandler {
	return &GamificationHandler{svc: svc}
}

func (h *GamificationHandler) Checkin(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	result, err := h.svc.Checkin(c.Request().Context(), userID)
	if err != nil {
		return response.BadRequest(c, err.Error())
	}
	return response.OK(c, result)
}

func (h *GamificationHandler) GetCheckinStatus(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	status := h.svc.GetCheckinStatus(c.Request().Context(), userID)
	return response.OK(c, status)
}

func (h *GamificationHandler) GetChallenges(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	challenges, err := h.svc.GetWeeklyChallenges(c.Request().Context(), userID)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, challenges)
}

func (h *GamificationHandler) GetLeaderboard(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	lb, err := h.svc.GetLeaderboard(c.Request().Context(), userID)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, lb)
}

func (h *GamificationHandler) GetPreviousLeaderboard(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	lb, err := h.svc.GetPreviousLeaderboard(c.Request().Context(), userID)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, lb)
}

func (h *GamificationHandler) GetReferral(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	info, err := h.svc.GetReferralInfo(c.Request().Context(), userID)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, info)
}

func (h *GamificationHandler) ApplyReferral(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	var req struct {
		Code string `json:"code" validate:"required"`
	}
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := h.svc.ApplyReferralCode(c.Request().Context(), userID, req.Code); err != nil {
		return response.BadRequest(c, err.Error())
	}
	return response.OK(c, map[string]string{"status": "applied"})
}

func (h *GamificationHandler) BuyStreakFreeze(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	if err := h.svc.BuyStreakFreeze(c.Request().Context(), userID); err != nil {
		return response.BadRequest(c, err.Error())
	}
	return response.OK(c, map[string]string{"status": "purchased"})
}
