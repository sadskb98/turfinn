package handler

import (
	"html"
	"strings"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/infrastructure/worker"
	"github.com/turfinn/backend/internal/interfaces/dto"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type BookingHandler struct {
	bookingSvc  *service.BookingService
	asynqClient *asynq.Client
}

func NewBookingHandler(bookingSvc *service.BookingService, asynqClient *asynq.Client) *BookingHandler {
	return &BookingHandler{bookingSvc: bookingSvc, asynqClient: asynqClient}
}

// PUT /api/v1/admin/bookings/:id/status
func (h *BookingHandler) UpdateStatus(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid booking id")
	}
	var req struct {
		Status string `json:"status" validate:"required,oneof=confirmed cancelled"`
	}
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	booking, err := h.bookingSvc.GetByID(c.Request().Context(), id)
	if err != nil {
		return response.NotFound(c, "booking not found")
	}
	if err := h.bookingSvc.UpdateStatus(c.Request().Context(), id, entity.BookingStatus(req.Status)); err != nil {
		return response.InternalError(c)
	}
	if req.Status == "confirmed" {
		_ = worker.EnqueueFCM(h.asynqClient, worker.FCMPayload{
			UserID: booking.UserID,
			Title:  "Booking Confirmed",
			Body:   "Your slot is confirmed. See you on the pitch!",
			Data:   map[string]string{"screen": "/bookings/me", "booking_id": id.String()},
		})
	}
	return response.OK(c, map[string]string{"message": "status updated"})
}

// POST /api/v1/bookings
func (h *BookingHandler) Create(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	var req dto.CreateBookingRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	// Sanitize free-text fields
	req.Notes = html.EscapeString(strings.TrimSpace(req.Notes))

	booking, err := h.bookingSvc.Create(c.Request().Context(), userID, req)
	if err != nil {
		if err.Error() == "slot not available" {
			return response.Conflict(c, err.Error())
		}
		return response.BadRequest(c, err.Error())
	}

	// Reload with Pitch so the response includes pitch name
	if loaded, err := h.bookingSvc.GetByID(c.Request().Context(), booking.ID); err == nil {
		booking = loaded
	}
	return response.Created(c, toBookingResponse(booking))
}

// GET /api/v1/bookings/me
func (h *BookingHandler) ListMine(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	var q dto.ListBookingsQuery
	if err := c.Bind(&q); err != nil {
		return response.BadRequest(c, "invalid query params")
	}
	if q.Page < 1 {
		q.Page = 1
	}
	if q.Limit < 1 {
		q.Limit = 20
	}
	bookings, total, err := h.bookingSvc.ListByUser(c.Request().Context(), userID, q.Page, q.Limit)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OKPaginated(c, toBookingResponses(bookings), response.Meta{
		Page: q.Page, Limit: q.Limit, Total: total,
	})
}

// DELETE /api/v1/bookings/:id
func (h *BookingHandler) Cancel(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid booking id")
	}
	if err := h.bookingSvc.Cancel(c.Request().Context(), id, userID); err != nil {
		return response.BadRequest(c, err.Error())
	}
	return response.OK(c, map[string]string{"message": "booking cancelled"})
}

func toBookingResponse(b *entity.Booking) dto.BookingResponse {
	pitchName := ""
	if b.Pitch.ID != uuid.Nil {
		pitchName = b.Pitch.Name
	}
	return dto.BookingResponse{
		ID:                 b.ID.String(),
		PitchID:            b.PitchID.String(),
		PitchName:          pitchName,
		UserID:             b.UserID.String(),
		StartsAt:           b.StartsAt,
		EndsAt:             b.EndsAt,
		TotalCost:          b.TotalCost,
		Status:             string(b.Status),
		Notes:              b.Notes,
		PaymentMode:        b.PaymentMode,
		CashDuePaisa:       b.CashDuePaisa,
		CashCollectedPaisa: b.CashCollectedPaisa,
	}
}

func toBookingResponses(bookings []*entity.Booking) []dto.BookingResponse {
	out := make([]dto.BookingResponse, len(bookings))
	for i, b := range bookings {
		out[i] = toBookingResponse(b)
	}
	return out
}
