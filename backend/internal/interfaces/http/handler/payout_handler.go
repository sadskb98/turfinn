package handler

import (
	"errors"
	"strconv"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/rs/zerolog/log"
	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/interfaces/dto"
	mw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

// PayoutHandler handles payout method and payout request endpoints for managers.
type PayoutHandler struct {
	svc *service.PayoutService
}

// NewPayoutHandler constructs a PayoutHandler.
func NewPayoutHandler(svc *service.PayoutService) *PayoutHandler {
	return &PayoutHandler{svc: svc}
}

// AddPayoutMethod handles POST /manager/payout-methods.
func (h *PayoutHandler) AddPayoutMethod(c echo.Context) error {
	managerID := c.Get(mw.UserIDKey).(uuid.UUID)

	var req dto.AddPayoutMethodRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	method, err := h.svc.AddPayoutMethod(c.Request().Context(), managerID, req)
	if err != nil {
		log.Error().Err(err).Msg("add payout method error")
		return response.InternalError(c)
	}

	bankName := ""
	if method.BankName != nil {
		bankName = *method.BankName
	}
	routingNumber := ""
	if method.RoutingNumber != nil {
		routingNumber = *method.RoutingNumber
	}
	accountName := ""
	if method.AccountName != nil {
		accountName = *method.AccountName
	}

	return response.Created(c, dto.PayoutMethodResponse{
		ID:            method.ID.String(),
		MethodType:    method.MethodType,
		AccountNumber: method.AccountNumber,
		AccountName:   accountName,
		BankName:      bankName,
		RoutingNumber: routingNumber,
		IsVerified:    method.IsVerified,
		CreatedAt:     method.CreatedAt.Format("2006-01-02T15:04:05Z"),
	})
}

// ListPayoutMethods handles GET /manager/payout-methods.
func (h *PayoutHandler) ListPayoutMethods(c echo.Context) error {
	managerID := c.Get(mw.UserIDKey).(uuid.UUID)

	methods, err := h.svc.ListPayoutMethods(c.Request().Context(), managerID)
	if err != nil {
		log.Error().Err(err).Msg("list payout methods error")
		return response.InternalError(c)
	}

	items := make([]dto.PayoutMethodResponse, len(methods))
	for i, m := range methods {
		bankName := ""
		if m.BankName != nil {
			bankName = *m.BankName
		}
		routingNumber := ""
		if m.RoutingNumber != nil {
			routingNumber = *m.RoutingNumber
		}
		accountName := ""
		if m.AccountName != nil {
			accountName = *m.AccountName
		}
		items[i] = dto.PayoutMethodResponse{
			ID:            m.ID.String(),
			MethodType:    m.MethodType,
			AccountNumber: m.AccountNumber,
			AccountName:   accountName,
			BankName:      bankName,
			RoutingNumber: routingNumber,
			IsVerified:    m.IsVerified,
			CreatedAt:     m.CreatedAt.Format("2006-01-02T15:04:05Z"),
		}
	}
	return response.OK(c, items)
}

// DeletePayoutMethod handles DELETE /manager/payout-methods/:id.
func (h *PayoutHandler) DeletePayoutMethod(c echo.Context) error {
	managerID := c.Get(mw.UserIDKey).(uuid.UUID)

	methodID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid payout method id")
	}

	if err := h.svc.DeletePayoutMethod(c.Request().Context(), managerID, methodID); err != nil {
		switch {
		case errors.Is(err, service.ErrPayoutMethodNotFound):
			return response.NotFound(c, "payout method not found")
		case errors.Is(err, service.ErrPayoutMethodInUse):
			return response.Conflict(c, "payout method has in-flight payout requests")
		default:
			log.Error().Err(err).Msg("delete payout method error")
			return response.InternalError(c)
		}
	}

	return response.OK(c, map[string]string{"id": methodID.String(), "status": "deleted"})
}

// RequestPayout handles POST /manager/payouts.
func (h *PayoutHandler) RequestPayout(c echo.Context) error {
	managerID := c.Get(mw.UserIDKey).(uuid.UUID)

	var req dto.RequestPayoutRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	payoutReq, err := h.svc.RequestPayout(c.Request().Context(), managerID, req)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrKYCNotApproved):
			return response.BadRequest(c, err.Error())
		case errors.Is(err, service.ErrPayoutMethodNotFound):
			return response.NotFound(c, err.Error())
		case errors.Is(err, service.ErrBelowMinThreshold):
			return response.BadRequest(c, err.Error())
		case errors.Is(err, service.ErrPayoutAlreadyPending):
			return response.Conflict(c, err.Error())
		case errors.Is(err, service.ErrInsufficientLedgerBalance):
			return response.BadRequest(c, "insufficient available balance")
		default:
			log.Error().Err(err).Msg("request payout error")
			return response.InternalError(c)
		}
	}

	processedAt := ""
	if payoutReq.ProcessedAt != nil {
		processedAt = payoutReq.ProcessedAt.Format("2006-01-02T15:04:05Z")
	}

	return response.Created(c, dto.PayoutRequestResponse{
		ID:          payoutReq.ID.String(),
		Amount:      payoutReq.AmountPaisa,
		Status:      payoutReq.Status,
		RequestedAt: payoutReq.CreatedAt.Format("2006-01-02T15:04:05Z"),
		ProcessedAt: processedAt,
	})
}

// ListPayouts handles GET /manager/payouts.
func (h *PayoutHandler) ListPayouts(c echo.Context) error {
	managerID := c.Get(mw.UserIDKey).(uuid.UUID)

	page, _ := strconv.Atoi(c.QueryParam("page"))
	limit, _ := strconv.Atoi(c.QueryParam("limit"))
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = 20
	}
	if limit > 100 {
		limit = 100
	}

	payouts, total, err := h.svc.ListPayouts(c.Request().Context(), managerID, page, limit)
	if err != nil {
		log.Error().Err(err).Msg("list payouts error")
		return response.InternalError(c)
	}

	items := make([]dto.PayoutRequestResponse, len(payouts))
	for i, p := range payouts {
		processedAt := ""
		if p.ProcessedAt != nil {
			processedAt = p.ProcessedAt.Format("2006-01-02T15:04:05Z")
		}
		items[i] = dto.PayoutRequestResponse{
			ID:          p.ID.String(),
			Amount:      p.AmountPaisa,
			Status:      p.Status,
			RequestedAt: p.CreatedAt.Format("2006-01-02T15:04:05Z"),
			ProcessedAt: processedAt,
		}
	}

	return response.OKPaginated(c, items, response.Meta{Page: page, Limit: limit, Total: total})
}
