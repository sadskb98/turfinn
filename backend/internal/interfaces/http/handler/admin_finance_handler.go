package handler

import (
	"errors"
	"strconv"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/labstack/echo/v4"
	"github.com/rs/zerolog/log"
	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/interfaces/dto"
	"github.com/turfinn/backend/internal/pkg/response"
)

// AdminFinanceHandler handles admin payout management and fee config endpoints.
type AdminFinanceHandler struct {
	svc *service.AdminFinanceService
}

// NewAdminFinanceHandler constructs an AdminFinanceHandler.
func NewAdminFinanceHandler(svc *service.AdminFinanceService) *AdminFinanceHandler {
	return &AdminFinanceHandler{svc: svc}
}

// ListAllPayouts handles GET /admin/payouts.
// Query params: page, limit, status (optional filter).
func (h *AdminFinanceHandler) ListAllPayouts(c echo.Context) error {
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
	statusFilter := c.QueryParam("status")
	validStatuses := map[string]bool{
		"":                             true,
		entity.PayoutStatusPending:    true,
		entity.PayoutStatusApproved:   true,
		entity.PayoutStatusProcessing: true,
		entity.PayoutStatusCompleted:  true,
		entity.PayoutStatusRejected:   true,
	}
	if !validStatuses[statusFilter] {
		return response.BadRequest(c, "invalid status filter")
	}

	payouts, total, err := h.svc.ListAllPayouts(c.Request().Context(), page, limit, statusFilter)
	if err != nil {
		log.Error().Err(err).Msg("admin: list all payouts error")
		return response.InternalError(c)
	}

	items := make([]dto.AdminPayoutRequestResponse, len(payouts))
	for i, p := range payouts {
		item := dto.AdminPayoutRequestResponse{
			ID:          p.ID.String(),
			ManagerID:   p.ManagerID.String(),
			AmountPaisa: p.AmountPaisa,
			Status:      p.Status,
			RequestedAt: p.CreatedAt.Format("2006-01-02T15:04:05Z"),
		}
		if p.TransferReference != nil {
			item.TransferReference = *p.TransferReference
		}
		if p.RejectionReason != nil {
			item.RejectionReason = *p.RejectionReason
		}
		if p.ProcessedAt != nil {
			item.ProcessedAt = p.ProcessedAt.Format("2006-01-02T15:04:05Z")
		}
		if p.CompletedAt != nil {
			item.CompletedAt = p.CompletedAt.Format("2006-01-02T15:04:05Z")
		}
		items[i] = item
	}

	return response.OKPaginated(c, items, response.Meta{Page: page, Limit: limit, Total: total})
}

// ApprovePayout handles PUT /admin/payouts/:id/approve.
func (h *AdminFinanceHandler) ApprovePayout(c echo.Context) error {
	payoutID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid payout id")
	}

	payoutReq, err := h.svc.ApprovePayout(c.Request().Context(), payoutID)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrPayoutNotFound):
			return response.NotFound(c, "payout request not found")
		case errors.Is(err, service.ErrInvalidStateTransition):
			return response.BadRequest(c, "invalid payout state transition")
		default:
			log.Error().Err(err).Msg("admin: approve payout error")
			return response.InternalError(c)
		}
	}

	return response.OK(c, mapPayoutResponse(payoutReq))
}

// ProcessPayout handles PUT /admin/payouts/:id/process.
func (h *AdminFinanceHandler) ProcessPayout(c echo.Context) error {
	payoutID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid payout id")
	}

	payoutReq, err := h.svc.ProcessPayout(c.Request().Context(), payoutID)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrPayoutNotFound):
			return response.NotFound(c, "payout request not found")
		case errors.Is(err, service.ErrInvalidStateTransition):
			return response.BadRequest(c, "invalid payout state transition")
		default:
			log.Error().Err(err).Msg("admin: process payout error")
			return response.InternalError(c)
		}
	}

	return response.OK(c, mapPayoutResponse(payoutReq))
}

// CompletePayout handles PUT /admin/payouts/:id/complete.
func (h *AdminFinanceHandler) CompletePayout(c echo.Context) error {
	payoutID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid payout id")
	}

	var req dto.AdminCompletePayoutRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	payoutReq, err := h.svc.CompletePayout(c.Request().Context(), payoutID, req.TransferReference)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrPayoutNotFound):
			return response.NotFound(c, "payout request not found")
		case errors.Is(err, service.ErrInvalidStateTransition):
			return response.BadRequest(c, "invalid payout state transition")
		default:
			log.Error().Err(err).Msg("admin: complete payout error")
			return response.InternalError(c)
		}
	}

	return response.OK(c, mapPayoutResponse(payoutReq))
}

// RejectPayout handles PUT /admin/payouts/:id/reject.
func (h *AdminFinanceHandler) RejectPayout(c echo.Context) error {
	payoutID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid payout id")
	}

	var req dto.AdminRejectPayoutRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	payoutReq, err := h.svc.RejectPayout(c.Request().Context(), payoutID, req.RejectionReason)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrPayoutNotFound):
			return response.NotFound(c, "payout request not found")
		case errors.Is(err, service.ErrInvalidStateTransition):
			return response.BadRequest(c, "invalid payout state transition")
		default:
			log.Error().Err(err).Msg("admin: reject payout error")
			return response.InternalError(c)
		}
	}

	return response.OK(c, mapPayoutResponse(payoutReq))
}

// ListFeeConfigs handles GET /admin/fee-configs.
func (h *AdminFinanceHandler) ListFeeConfigs(c echo.Context) error {
	configs, err := h.svc.ListFeeConfigs(c.Request().Context())
	if err != nil {
		log.Error().Err(err).Msg("admin: list fee configs error")
		return response.InternalError(c)
	}

	items := make([]dto.AdminFeeConfigResponse, len(configs))
	for i, cfg := range configs {
		items[i] = mapFeeConfigResponse(&cfg)
	}
	return response.OK(c, items)
}

// CreateFeeConfig handles POST /admin/fee-configs.
func (h *AdminFinanceHandler) CreateFeeConfig(c echo.Context) error {
	var req dto.AdminCreateFeeConfigRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	cfg, err := h.svc.CreateFeeConfig(c.Request().Context(), req)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrInvalidFeeConfigInput):
			return response.BadRequest(c, err.Error())
		default:
			log.Error().Err(err).Msg("admin: create fee config error")
			return response.InternalError(c)
		}
	}

	return response.Created(c, mapFeeConfigResponse(cfg))
}

// UpdateFeeConfig handles PUT /admin/fee-configs/:id.
func (h *AdminFinanceHandler) UpdateFeeConfig(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid fee config id")
	}

	var req dto.AdminUpdateFeeConfigRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	cfg, err := h.svc.UpdateFeeConfig(c.Request().Context(), id, req)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrFeeConfigNotFound):
			return response.NotFound(c, "fee config not found")
		default:
			log.Error().Err(err).Msg("admin: update fee config error")
			return response.InternalError(c)
		}
	}

	return response.OK(c, mapFeeConfigResponse(cfg))
}

// ListGatewayFeeRates handles GET /admin/gateway-fee-rates.
func (h *AdminFinanceHandler) ListGatewayFeeRates(c echo.Context) error {
	rates, err := h.svc.ListGatewayFeeRates(c.Request().Context())
	if err != nil {
		log.Error().Err(err).Msg("admin: list gateway fee rates error")
		return response.InternalError(c)
	}

	items := make([]dto.AdminGatewayFeeRateResponse, len(rates))
	for i, r := range rates {
		items[i] = dto.AdminGatewayFeeRateResponse{
			ID:        r.ID.String(),
			CardType:  r.CardType,
			FeeBps:    r.FeeBps,
			UpdatedAt: r.UpdatedAt.Format("2006-01-02T15:04:05Z"),
		}
	}
	return response.OK(c, items)
}

// UpdateGatewayFeeRate handles PUT /admin/gateway-fee-rates/:card_type.
func (h *AdminFinanceHandler) UpdateGatewayFeeRate(c echo.Context) error {
	cardType := c.Param("card_type")
	if cardType == "" {
		return response.BadRequest(c, "card_type is required")
	}

	var req dto.AdminUpdateGatewayRateRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	rate, err := h.svc.UpdateGatewayFeeRate(c.Request().Context(), cardType, req.FeeBps)
	if err != nil {
		log.Error().Err(err).Msg("admin: update gateway fee rate error")
		return response.InternalError(c)
	}

	return response.OK(c, dto.AdminGatewayFeeRateResponse{
		ID:        rate.ID.String(),
		CardType:  rate.CardType,
		FeeBps:    rate.FeeBps,
		UpdatedAt: rate.UpdatedAt.Format("2006-01-02T15:04:05Z"),
	})
}

// CreateGatewayFeeReconciliation handles POST /admin/gateway-fee-reconciliations.
func (h *AdminFinanceHandler) CreateGatewayFeeReconciliation(c echo.Context) error {
	var req dto.AdminCreateReconciliationRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	rec, err := h.svc.CreateGatewayFeeReconciliation(c.Request().Context(), req)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return response.Conflict(c, "reconciliation already exists for this settlement")
		}
		log.Error().Err(err).Msg("admin: create gateway fee reconciliation error")
		return response.InternalError(c)
	}

	return response.Created(c, dto.AdminReconciliationResponse{
		ID:           rec.ID.String(),
		SettlementID: rec.SettlementID.String(),
		ChargedPaisa: rec.ChargedPaisa,
		ActualPaisa:  rec.ActualPaisa,
		DiffPaisa:    rec.DiffPaisa,
		CreatedAt:    rec.CreatedAt.Format("2006-01-02T15:04:05Z"),
	})
}

// --- helpers ---

func mapPayoutResponse(p *entity.PayoutRequest) dto.AdminPayoutRequestResponse {
	r := dto.AdminPayoutRequestResponse{
		ID:          p.ID.String(),
		ManagerID:   p.ManagerID.String(),
		AmountPaisa: p.AmountPaisa,
		Status:      p.Status,
		RequestedAt: p.CreatedAt.Format("2006-01-02T15:04:05Z"),
	}
	if p.TransferReference != nil {
		r.TransferReference = *p.TransferReference
	}
	if p.RejectionReason != nil {
		r.RejectionReason = *p.RejectionReason
	}
	if p.ProcessedAt != nil {
		r.ProcessedAt = p.ProcessedAt.Format("2006-01-02T15:04:05Z")
	}
	if p.CompletedAt != nil {
		r.CompletedAt = p.CompletedAt.Format("2006-01-02T15:04:05Z")
	}
	return r
}

func mapFeeConfigResponse(cfg *entity.PartnerFeeConfig) dto.AdminFeeConfigResponse {
	r := dto.AdminFeeConfigResponse{
		ID:                      cfg.ID.String(),
		CommissionBps:           cfg.CommissionBps,
		PayoutMinThresholdPaisa: cfg.PayoutMinThresholdPaisa,
		HoldDays:                cfg.HoldDays,
		CreatedAt:               cfg.CreatedAt.Format("2006-01-02T15:04:05Z"),
		UpdatedAt:               cfg.UpdatedAt.Format("2006-01-02T15:04:05Z"),
	}
	if cfg.ManagerID != nil {
		r.ManagerID = cfg.ManagerID.String()
	}
	if cfg.ValidFrom != nil {
		r.ValidFrom = cfg.ValidFrom.Format("2006-01-02")
	}
	if cfg.ValidTo != nil {
		r.ValidTo = cfg.ValidTo.Format("2006-01-02")
	}
	return r
}
