package handler

import (
	"strconv"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/application/service"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type WalletHandler struct {
	svc     *service.WalletService
	gameSvc *service.GamificationService
}

func NewWalletHandler(svc *service.WalletService, gameSvc *service.GamificationService) *WalletHandler {
	return &WalletHandler{svc: svc, gameSvc: gameSvc}
}

// GET /api/v1/wallet
func (h *WalletHandler) GetBalance(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	balance, err := h.svc.GetBalance(c.Request().Context(), userID)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]interface{}{"balance": balance})
}

// POST /api/v1/wallet/topup  body: {"amount": 100}
func (h *WalletHandler) TopUp(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	var req struct {
		Amount int `json:"amount" validate:"required,min=1"`
	}
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	if err := h.svc.TopUp(c.Request().Context(), userID, req.Amount); err != nil {
		return response.BadRequest(c, err.Error())
	}
	return response.OK(c, map[string]string{"status": "topped_up"})
}

// GET /api/v1/wallet/transactions?page=1&limit=20
func (h *WalletHandler) ListTransactions(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	page, _ := strconv.Atoi(c.QueryParam("page"))
	if page < 1 {
		page = 1
	}
	limit, _ := strconv.Atoi(c.QueryParam("limit"))
	if limit < 1 {
		limit = 20
	}
	txs, total, err := h.svc.ListTransactions(c.Request().Context(), userID, page, limit)
	if err != nil {
		return response.InternalError(c)
	}
	var resp []map[string]interface{}
	for _, t := range txs {
		resp = append(resp, map[string]interface{}{
			"id":         t.ID,
			"amount":     t.Amount,
			"type":       t.Type,
			"reference":  t.Reference,
			"created_at": t.CreatedAt,
		})
	}
	return response.OKPaginated(c, resp, response.Meta{Page: page, Limit: limit, Total: total})
}

// GET /api/v1/profile
func (h *WalletHandler) GetProfile(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	profile, err := h.svc.GetProfile(c.Request().Context(), userID)
	if err != nil {
		return response.InternalError(c)
	}

	ctx := c.Request().Context()

	// Read XP and level from user
	var userData struct {
		XP    int
		Level int
	}
	h.gameSvc.DB().WithContext(ctx).Table("users").Select("xp, level").Where("id = ?", userID).Scan(&userData)

	profile["xp"] = userData.XP
	profile["level"] = userData.Level
	profile["level_title"] = service.LevelTitle(userData.Level)
	profile["xp_to_next_level"] = service.XPToNextLevel(userData.XP, userData.Level)

	streak, _ := h.gameSvc.GetStreak(ctx, userID)
	profile["current_streak"] = streak.CurrentStreak
	profile["longest_streak"] = streak.LongestStreak
	profile["streak_freezes"] = streak.StreakFreezesRemaining

	referral, _ := h.gameSvc.GetOrCreateReferralCode(ctx, userID)
	profile["referral_code"] = referral.Code

	return response.OK(c, profile)
}
