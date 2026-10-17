package handler

import (
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/interfaces/dto"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type ManagerHandler struct {
	svc      *service.AnalyticsService
	enhanced *service.ManagerAnalyticsService
	bookings *service.BookingService
}

func NewManagerHandler(
	svc *service.AnalyticsService,
	enhanced *service.ManagerAnalyticsService,
	bookings *service.BookingService,
) *ManagerHandler {
	return &ManagerHandler{svc: svc, enhanced: enhanced, bookings: bookings}
}

// GET /api/v1/manager/analytics/summary?period=today|week|month
func (h *ManagerHandler) GetSummary(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}
	period := c.QueryParam("period")
	if period == "" {
		period = "month"
	}
	summary, err := h.svc.GetSummary(c.Request().Context(), managerID, period)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, summary)
}

// GET /api/v1/manager/analytics/revenue-chart?days=30
func (h *ManagerHandler) GetRevenueChart(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}
	days := 30
	if d := c.QueryParam("days"); d != "" {
		if n, err := parseInt(d); err == nil && n > 0 {
			days = n
		}
	}
	chart, err := h.svc.GetRevenueChart(c.Request().Context(), managerID, days)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, chart)
}

// GET /api/v1/manager/analytics/pitch-breakdown?period=month
func (h *ManagerHandler) GetPitchBreakdown(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}
	period := c.QueryParam("period")
	if period == "" {
		period = "month"
	}
	stats, err := h.svc.GetPitchBreakdown(c.Request().Context(), managerID, period)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, stats)
}

// GET /api/v1/manager/bookings?status=&source=&date=&page=1&limit=20
func (h *ManagerHandler) ListBookings(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}
	filter := dto.ManagerBookingFilter{
		Status: c.QueryParam("status"),
		Source: c.QueryParam("source"),
		Date:   c.QueryParam("date"),
		Page:   1,
		Limit:  20,
	}
	if p, err := parseInt(c.QueryParam("page")); err == nil && p > 0 {
		filter.Page = p
	}
	if l, err := parseInt(c.QueryParam("limit")); err == nil && l > 0 && l <= 100 {
		filter.Limit = l
	}
	bookings, total, err := h.svc.ListBookings(c.Request().Context(), managerID, filter)
	if err != nil {
		return response.InternalError(c)
	}
	out := make([]dto.ManagerBookingResponse, len(bookings))
	for i, b := range bookings {
		out[i] = toManagerBookingResponse(b)
	}
	return response.OKPaginated(c, out, response.Meta{
		Page: filter.Page, Limit: filter.Limit, Total: total,
	})
}

// POST /api/v1/manager/bookings
func (h *ManagerHandler) CreateWalkIn(c echo.Context) error {
	managerID, idErr := mustManagerID(c)
	if idErr != nil {
		return response.Unauthorized(c)
	}
	var req dto.CreateWalkInBookingRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	booking, err := h.svc.CreateWalkIn(c.Request().Context(), managerID, req)
	if err != nil {
		msg := err.Error()
		switch {
		case msg == "slot not available":
			return response.Conflict(c, msg)
		case strings.Contains(msg, "pitch not found"):
			return response.NotFound(c, msg)
		case strings.Contains(msg, "invalid pitch_id"):
			return response.BadRequest(c, msg)
		default:
			return response.InternalError(c)
		}
	}
	return response.Created(c, toManagerBookingResponse(booking))
}

// POST /api/v1/manager/bookings/:id/mark-cash-collected
//
// Records that the owner physically collected the cash share at the venue
// for a partial-payment booking. The booking_service handles auth (caller
// must own the pitch) and writes a ledger entry to balance trial balance.
func (h *ManagerHandler) MarkCashCollected(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid booking id")
	}
	if h.bookings == nil {
		return response.InternalError(c)
	}
	if err := h.bookings.MarkCashCollected(c.Request().Context(), id, managerID); err != nil {
		msg := err.Error()
		switch {
		case strings.Contains(msg, "not authorized"):
			return response.BadRequest(c, msg)
		case strings.Contains(msg, "booking not found"):
			return response.NotFound(c, msg)
		default:
			return response.BadRequest(c, msg)
		}
	}
	return response.OK(c, map[string]string{"status": "collected"})
}

// PUT /api/v1/manager/bookings/:id/status
func (h *ManagerHandler) UpdateStatus(c echo.Context) error {
	managerID, idErr := mustManagerID(c)
	if idErr != nil {
		return response.Unauthorized(c)
	}
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
	if err := h.svc.UpdateBookingStatus(c.Request().Context(), managerID, id, entity.BookingStatus(req.Status)); err != nil {
		if strings.Contains(err.Error(), "not found") {
			return response.NotFound(c, err.Error())
		}
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"message": "status updated"})
}

// GET /api/v1/manager/financials?from=2026-01-01&to=2026-12-31
func (h *ManagerHandler) GetFinancials(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}
	from := time.Now().UTC().AddDate(0, -1, 0)
	to := time.Now().UTC()
	if f := c.QueryParam("from"); f != "" {
		if t, err := time.Parse("2006-01-02", f); err == nil {
			from = t
		}
	}
	if t := c.QueryParam("to"); t != "" {
		if parsed, err := time.Parse("2006-01-02", t); err == nil {
			to = parsed.Add(24 * time.Hour) // inclusive
		}
	}
	fin, err := h.svc.GetFinancials(c.Request().Context(), managerID, from, to)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, fin)
}

// mustManagerID extracts the authenticated user's UUID from the echo context.
// Returns Unauthorized if the value is missing or wrong type.
func mustManagerID(c echo.Context) (uuid.UUID, error) {
	raw := c.Get(authmw.UserIDKey)
	id, ok := raw.(uuid.UUID)
	if !ok {
		return uuid.Nil, echo.ErrUnauthorized
	}
	return id, nil
}

func toManagerBookingResponse(b *entity.Booking) dto.ManagerBookingResponse {
	pitchName := ""
	if b.Pitch.ID != uuid.Nil {
		pitchName = b.Pitch.Name
	}
	customerName := ""
	if strings.HasPrefix(b.Notes, "Walk-in: ") {
		customerName = strings.TrimPrefix(b.Notes, "Walk-in: ")
	} else if b.User.ID != uuid.Nil {
		customerName = b.User.Name
	}
	customerPhone := ""
	if b.User.Phone != nil {
		customerPhone = *b.User.Phone
	}
	return dto.ManagerBookingResponse{
		ID:                 b.ID.String(),
		PitchID:            b.PitchID.String(),
		PitchName:          pitchName,
		UserID:             b.UserID.String(),
		CustomerName:       customerName,
		CustomerPhone:      customerPhone,
		StartsAt:           b.StartsAt,
		EndsAt:             b.EndsAt,
		TotalCost:          b.TotalCost,
		Status:             string(b.Status),
		Source:             b.Source,
		PaymentMethod:      b.PaymentMethod,
		PaymentAmount:      b.PaymentAmount,
		Notes:              b.Notes,
		PaymentMode:        b.PaymentMode,
		CashDuePaisa:       b.CashDuePaisa,
		CashCollectedPaisa: b.CashCollectedPaisa,
		CashCollectedAt:    b.CashCollectedAt,
	}
}

// GET /api/v1/manager/analytics/heatmap?period=month
func (h *ManagerHandler) GetHeatmap(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}
	period := c.QueryParam("period")
	if period == "" {
		period = "month"
	}
	heatmap, err := h.enhanced.GetHeatmap(c.Request().Context(), managerID, period)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, heatmap)
}

// GET /api/v1/manager/analytics/peak-hours?period=month
func (h *ManagerHandler) GetPeakHours(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}
	period := c.QueryParam("period")
	if period == "" {
		period = "month"
	}
	peaks, err := h.enhanced.GetPeakHours(c.Request().Context(), managerID, period)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, peaks)
}

// GET /api/v1/manager/analytics/customers?period=month
func (h *ManagerHandler) GetCustomerInsights(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}
	period := c.QueryParam("period")
	if period == "" {
		period = "month"
	}
	insights, err := h.enhanced.GetCustomerInsights(c.Request().Context(), managerID, period)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, insights)
}

// GET /api/v1/manager/financials/ledger?from=2026-01-01&to=2026-12-31
func (h *ManagerHandler) GetDailyLedger(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}
	from := time.Now().UTC().AddDate(0, -1, 0)
	to := time.Now().UTC()
	if f := c.QueryParam("from"); f != "" {
		if t, err := time.Parse("2006-01-02", f); err == nil {
			from = t
		}
	}
	if t := c.QueryParam("to"); t != "" {
		if parsed, err := time.Parse("2006-01-02", t); err == nil {
			to = parsed.Add(24 * time.Hour)
		}
	}
	ledger, err := h.enhanced.GetDailyLedger(c.Request().Context(), managerID, from, to)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, ledger)
}

// GET /api/v1/manager/financials/pitch-pnl?from=2026-01-01&to=2026-12-31
func (h *ManagerHandler) GetPitchPnL(c echo.Context) error {
	managerID, err := mustManagerID(c)
	if err != nil {
		return response.Unauthorized(c)
	}
	from := time.Now().UTC().AddDate(0, -1, 0)
	to := time.Now().UTC()
	if f := c.QueryParam("from"); f != "" {
		if t, err := time.Parse("2006-01-02", f); err == nil {
			from = t
		}
	}
	if t := c.QueryParam("to"); t != "" {
		if parsed, err := time.Parse("2006-01-02", t); err == nil {
			to = parsed.Add(24 * time.Hour)
		}
	}
	entries, err := h.enhanced.GetPitchPnL(c.Request().Context(), managerID, from, to)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, entries)
}

func parseInt(s string) (int, error) {
	var n int
	_, err := fmt.Sscanf(s, "%d", &n)
	return n, err
}
