// Package handler — booking_split_handler.go exposes the Split-Pay
// endpoints. The captain initiates via the auth-protected /bookings/split
// route; everyone else (including non-Turfinn-users) hits the public
// /split/:token routes from a WhatsApp link with no auth.
package handler

import (
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/nyaruka/phonenumbers"
	"github.com/rs/zerolog/log"

	"github.com/turfinn/backend/internal/application/service"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type BookingSplitHandler struct {
	svc *service.BookingSplitService
}

func NewBookingSplitHandler(svc *service.BookingSplitService) *BookingSplitHandler {
	return &BookingSplitHandler{svc: svc}
}

// ── Captain-facing (auth) ────────────────────────────────────────────────

type initiateSplitRequest struct {
	PitchID     string    `json:"pitch_id" validate:"required,uuid"`
	StartsAt    time.Time `json:"starts_at" validate:"required"`
	EndsAt      time.Time `json:"ends_at" validate:"required"`
	TotalShares int       `json:"total_shares" validate:"required,min=2,max=30"`
	Notes       string    `json:"notes"`
}

// POST /api/v1/bookings/split
func (h *BookingSplitHandler) Initiate(c echo.Context) error {
	uid, ok := c.Get(authmw.UserIDKey).(uuid.UUID)
	if !ok {
		return response.Unauthorized(c)
	}
	var req initiateSplitRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	pitchID, err := uuid.Parse(req.PitchID)
	if err != nil {
		return response.BadRequest(c, "invalid pitch_id")
	}
	res, err := h.svc.InitiateSplit(c.Request().Context(), service.InitiateSplitInput{
		CaptainID:   uid,
		PitchID:     pitchID,
		StartsAt:    req.StartsAt,
		EndsAt:      req.EndsAt,
		TotalShares: req.TotalShares,
		Notes:       req.Notes,
	})
	if err != nil {
		return response.BadRequest(c, err.Error())
	}
	return response.OK(c, map[string]any{
		"booking_id":  res.BookingID.String(),
		"token":       res.Token,
		"deadline_at": res.DeadlineAt,
		"gateway_url": res.GatewayURL,
		"per_share_paisa": res.PerShare,
	})
}

// ── Public (no auth) ─────────────────────────────────────────────────────

// GET /api/v1/split/:token
func (h *BookingSplitHandler) GetByToken(c echo.Context) error {
	token := c.Param("token")
	if token == "" {
		return response.BadRequest(c, "token required")
	}
	view, err := h.svc.GetByToken(c.Request().Context(), token)
	if err != nil {
		return response.NotFound(c, err.Error())
	}
	return response.OK(c, view)
}

type claimRequest struct {
	Phone string `json:"phone" validate:"required"`
}

// POST /api/v1/split/:token/claim
//
// Body: { "phone": "01XXXXXXXXX" } — accepted in any common BD format,
// normalised to E.164 (+8801XXXXXXXXX) before persistence so duplicate
// rows for the same person can't form by typing variation.
func (h *BookingSplitHandler) Claim(c echo.Context) error {
	token := c.Param("token")
	if token == "" {
		return response.BadRequest(c, "token required")
	}
	var req claimRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	phone, err := normalizeBDPhone(req.Phone)
	if err != nil {
		return response.BadRequest(c, "invalid phone")
	}

	url, err := h.svc.ClaimAndInitiateShare(c.Request().Context(), token, phone)
	if err != nil {
		return response.BadRequest(c, err.Error())
	}
	return response.OK(c, map[string]string{"gateway_url": url})
}

// ── SSL callbacks ────────────────────────────────────────────────────────

// POST /api/v1/payment/split/success
func (h *BookingSplitHandler) Success(c echo.Context) error {
	form, _ := c.FormParams()
	params := paramsFromForm(form)
	tranID := params["tran_id"]
	if err := h.svc.HandleShareSuccess(c.Request().Context(), params); err != nil {
		log.Error().Err(err).Str("tran_id", tranID).Msg("split payment success: confirm failed")
		return renderReturnPage(c, "fail", tranID,
			"We received your payment but ran into an issue confirming it. Please re-open the link — we'll retry automatically.")
	}
	log.Info().Str("tran_id", tranID).Msg("split payment success: confirmed")
	return renderReturnPage(c, "success", tranID,
		"Payment received. The captain will see your share shortly.")
}

// POST /api/v1/payment/split/ipn  (server-to-server)
func (h *BookingSplitHandler) IPN(c echo.Context) error {
	form, _ := c.FormParams()
	params := paramsFromForm(form)
	if err := h.svc.HandleShareSuccess(c.Request().Context(), params); err != nil {
		log.Error().Err(err).Str("tran_id", params["tran_id"]).Msg("split payment IPN: confirm failed")
		return response.BadRequest(c, err.Error())
	}
	return response.OK(c, map[string]string{"status": "ok"})
}

// POST /api/v1/payment/split/fail
func (h *BookingSplitHandler) Fail(c echo.Context) error {
	form, _ := c.FormParams()
	params := paramsFromForm(form)
	tranID := params["tran_id"]
	return renderReturnPage(c, "fail", tranID, "Payment failed. You can try again from the link.")
}

// POST /api/v1/payment/split/cancel
func (h *BookingSplitHandler) Cancel(c echo.Context) error {
	form, _ := c.FormParams()
	params := paramsFromForm(form)
	tranID := params["tran_id"]
	return renderReturnPage(c, "cancel", tranID, "Payment cancelled. You can try again from the link.")
}

// normalizeBDPhone accepts "01XXXXXXXXX", "8801…", "+8801…", returns
// E.164 (+8801XXXXXXXXX) using the same lib the auth flow uses.
func normalizeBDPhone(in string) (string, error) {
	in = strings.TrimSpace(in)
	if in == "" {
		return "", echo.NewHTTPError(400, "phone required")
	}
	num, err := phonenumbers.Parse(in, "BD")
	if err != nil {
		return "", err
	}
	if !phonenumbers.IsValidNumber(num) {
		return "", echo.NewHTTPError(400, "phone invalid")
	}
	return phonenumbers.Format(num, phonenumbers.E164), nil
}
