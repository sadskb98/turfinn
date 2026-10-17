package handler

import (
	"errors"
	"net/http"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/rs/zerolog/log"
	"github.com/turfinn/backend/internal/application/service"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/interfaces/dto"
	"github.com/turfinn/backend/internal/pkg/response"
)

// PaymentHandler handles SSLCommerz payment initiation and gateway callbacks.
type PaymentHandler struct {
	svc        *service.PaymentService
	appBaseURL string
}

// NewPaymentHandler constructs a PaymentHandler.
// appBaseURL is used to build the post-payment redirect URL (e.g. "https://turfinn.com").
func NewPaymentHandler(svc *service.PaymentService, appBaseURL string) *PaymentHandler {
	return &PaymentHandler{svc: svc, appBaseURL: appBaseURL}
}

// Initiate handles POST /api/v1/bookings/:id/pay
// Requires auth middleware — userID is read from JWT claims.
func (h *PaymentHandler) Initiate(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)

	bookingID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid booking id")
	}

	redirectURL, err := h.svc.InitiatePayment(c.Request().Context(), bookingID, userID)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrBookingNotFound):
			return response.NotFound(c, "booking not found")
		case errors.Is(err, service.ErrNotBookingOwner):
			return response.Forbidden(c)
		case errors.Is(err, service.ErrAlreadyPaid):
			return response.Conflict(c, "booking already has a successful payment")
		case errors.Is(err, service.ErrNotPayable):
			return response.BadRequest(c, "booking cannot be paid in its current status")
		default:
			log.Error().Err(err).Msg("payment initiate error")
			return response.InternalError(c)
		}
	}

	return response.OK(c, dto.InitiateResponse{RedirectURL: redirectURL})
}

// Success handles POST /api/v1/payment/success (SSLCommerz callback — no auth).
// On success it redirects the user browser to the booking-success page.
func (h *PaymentHandler) Success(c echo.Context) error {
	var params dto.SSLCallbackParams
	if err := c.Bind(&params); err != nil {
		return response.BadRequest(c, "invalid callback params")
	}

	if err := h.svc.HandleCallback(c.Request().Context(), params); err != nil {
		// Log internally, never expose error detail on public callback endpoints.
		// Return 200 so SSLCommerz does not retry endlessly.
		log.Error().Err(err).Msg("payment callback error")
		return c.JSON(http.StatusOK, map[string]any{"success": false})
	}

	return c.Redirect(http.StatusFound, h.appBaseURL+"/booking-success")
}

// IPN handles POST /api/v1/payment/ipn (SSLCommerz IPN — no auth).
// Same logic as Success but returns 200 JSON instead of redirecting.
func (h *PaymentHandler) IPN(c echo.Context) error {
	var params dto.SSLCallbackParams
	if err := c.Bind(&params); err != nil {
		return response.BadRequest(c, "invalid ipn params")
	}

	if err := h.svc.HandleCallback(c.Request().Context(), params); err != nil {
		// Log internally, never expose error detail on public callback endpoints.
		log.Error().Err(err).Msg("payment callback error")
		return c.JSON(http.StatusOK, map[string]any{"success": false})
	}

	return response.OK(c, map[string]string{"message": "ipn processed"})
}

// Fail handles POST /api/v1/payment/fail (SSLCommerz callback — no auth).
func (h *PaymentHandler) Fail(c echo.Context) error {
	var params dto.SSLCallbackParams
	if err := c.Bind(&params); err != nil {
		return response.BadRequest(c, "invalid callback params")
	}

	if err := h.svc.HandleFail(c.Request().Context(), params.TranID); err != nil {
		return response.InternalError(c)
	}

	return response.OK(c, map[string]string{"message": "payment failed"})
}

// Cancel handles POST /api/v1/payment/cancel (SSLCommerz callback — no auth).
func (h *PaymentHandler) Cancel(c echo.Context) error {
	var params dto.SSLCallbackParams
	if err := c.Bind(&params); err != nil {
		return response.BadRequest(c, "invalid callback params")
	}

	if err := h.svc.HandleCancel(c.Request().Context(), params.TranID); err != nil {
		return response.InternalError(c)
	}

	return response.OK(c, map[string]string{"message": "payment cancelled"})
}
