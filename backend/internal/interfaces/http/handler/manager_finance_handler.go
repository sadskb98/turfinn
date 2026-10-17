package handler

import (
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/rs/zerolog/log"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/interfaces/dto"
	mw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
	"gorm.io/gorm"
)

// ManagerFinanceHandler handles wallet, settlements, fee config, analytics, and
// tax endpoints for the turf manager panel.
type ManagerFinanceHandler struct {
	db *gorm.DB
}

// NewManagerFinanceHandler constructs a ManagerFinanceHandler.
func NewManagerFinanceHandler(db *gorm.DB) *ManagerFinanceHandler {
	return &ManagerFinanceHandler{db: db}
}

// GetWallet handles GET /manager/wallet.
func (h *ManagerFinanceHandler) GetWallet(c echo.Context) error {
	managerID := c.Get(mw.UserIDKey).(uuid.UUID)

	var wallet entity.ManagerWallet
	err := h.db.Where("manager_id = ?", managerID).First(&wallet).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			// Wallet may not exist yet (no payments received); return zero balances.
			return response.OK(c, dto.ManagerWalletResponse{
				AvailableBalancePaisa: 0,
				PendingBalancePaisa:   0,
			})
		}
		log.Error().Err(err).Msg("get manager wallet error")
		return response.InternalError(c)
	}

	return response.OK(c, dto.ManagerWalletResponse{
		AvailableBalancePaisa: wallet.AvailableBalancePaisa,
		PendingBalancePaisa:   wallet.PendingBalancePaisa,
	})
}

// ListWalletTransactions handles GET /manager/wallet/transactions.
func (h *ManagerFinanceHandler) ListWalletTransactions(c echo.Context) error {
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
	offset := (page - 1) * limit

	// Look up the wallet first; if it doesn't exist return empty list.
	var wallet entity.ManagerWallet
	err := h.db.Where("manager_id = ?", managerID).First(&wallet).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return response.OKPaginated(c, []dto.ManagerWalletTxResponse{}, response.Meta{Page: page, Limit: limit, Total: 0})
		}
		log.Error().Err(err).Msg("get wallet for transactions error")
		return response.InternalError(c)
	}

	var txs []entity.ManagerWalletTransaction
	var total int64

	q := h.db.Model(&entity.ManagerWalletTransaction{}).Where("wallet_id = ?", wallet.ID)
	if err := q.Session(&gorm.Session{}).Count(&total).Error; err != nil {
		log.Error().Err(err).Msg("count wallet transactions error")
		return response.InternalError(c)
	}
	if err := q.Order("created_at DESC").Limit(limit).Offset(offset).Find(&txs).Error; err != nil {
		log.Error().Err(err).Msg("list wallet transactions error")
		return response.InternalError(c)
	}

	items := make([]dto.ManagerWalletTxResponse, len(txs))
	for i, tx := range txs {
		item := dto.ManagerWalletTxResponse{
			ID:          tx.ID.String(),
			AmountPaisa: tx.AmountPaisa,
			CreatedAt:   tx.CreatedAt.Format(time.RFC3339),
		}
		if tx.TxType != nil {
			item.TxType = *tx.TxType
		}
		if tx.ReferenceType != nil {
			item.ReferenceType = *tx.ReferenceType
		}
		if tx.ReferenceID != nil {
			item.ReferenceID = tx.ReferenceID.String()
		}
		if tx.Description != nil {
			item.Description = *tx.Description
		}
		items[i] = item
	}

	return response.OKPaginated(c, items, response.Meta{Page: page, Limit: limit, Total: total})
}

// ListSettlements handles GET /manager/financials/settlements.
func (h *ManagerFinanceHandler) ListSettlements(c echo.Context) error {
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
	offset := (page - 1) * limit

	baseQ := h.db.Model(&entity.BookingSettlement{}).
		Joins("JOIN bookings b ON b.id = booking_settlements.booking_id").
		Joins("JOIN pitches p ON p.id = b.pitch_id").
		Where("p.owner_id = ?", managerID)

	var total int64
	if err := baseQ.Session(&gorm.Session{}).Count(&total).Error; err != nil {
		log.Error().Err(err).Msg("count settlements error")
		return response.InternalError(c)
	}

	var settlements []entity.BookingSettlement
	if err := baseQ.Order("booking_settlements.created_at DESC").
		Limit(limit).Offset(offset).
		Find(&settlements).Error; err != nil {
		log.Error().Err(err).Msg("list settlements error")
		return response.InternalError(c)
	}

	items := make([]dto.SettlementResponse, len(settlements))
	for i, s := range settlements {
		item := dto.SettlementResponse{
			ID:                  s.ID.String(),
			BookingID:           s.BookingID.String(),
			TotalPaidPaisa:      s.TotalPaidPaisa,
			OwnerPayoutPaisa:    s.OwnerPayoutPaisa,
			TurfinnRevenuePaisa: s.TurfinnRevenuePaisa,
			GatewayFeePaisa:     s.GatewayFeePaisa,
			HoldDays:            s.HoldDays,
			Graduated:           s.Graduated,
			CreatedAt:           s.CreatedAt.Format(time.RFC3339),
		}
		if s.SettledAt != nil {
			item.SettledAt = s.SettledAt.Format(time.RFC3339)
		}
		items[i] = item
	}

	return response.OKPaginated(c, items, response.Meta{Page: page, Limit: limit, Total: total})
}

// GetFeeConfig handles GET /manager/financials/fee-config.
// Returns the most specific active fee config: manager-specific first, then global default.
func (h *ManagerFinanceHandler) GetFeeConfig(c echo.Context) error {
	managerID := c.Get(mw.UserIDKey).(uuid.UUID)

	var cfg entity.PartnerFeeConfig
	err := h.db.
		Where("(manager_id = ? OR manager_id IS NULL) AND (valid_to IS NULL OR valid_to >= CURRENT_DATE)", managerID).
		Order("(manager_id IS NOT NULL) DESC, valid_from DESC").
		Limit(1).
		First(&cfg).Error

	if err != nil {
		if err == gorm.ErrRecordNotFound {
			// No config at all — return sensible defaults.
			return response.OK(c, dto.ManagerFeeConfigResponse{
				CommissionBps:           1500,
				PayoutMinThresholdPaisa: 50000,
				HoldDays:                3,
				IsManagerSpecific:       false,
			})
		}
		log.Error().Err(err).Msg("get fee config error")
		return response.InternalError(c)
	}

	return response.OK(c, dto.ManagerFeeConfigResponse{
		CommissionBps:           cfg.CommissionBps,
		PayoutMinThresholdPaisa: cfg.PayoutMinThresholdPaisa,
		HoldDays:                cfg.HoldDays,
		IsManagerSpecific:       cfg.ManagerID != nil,
	})
}

// GetFinancialAnalytics handles GET /manager/financials/analytics.
func (h *ManagerFinanceHandler) GetFinancialAnalytics(c echo.Context) error {
	managerID := c.Get(mw.UserIDKey).(uuid.UUID)

	// TotalEarned: sum of owner_payout_paisa from graduated settlements for this manager.
	var totalEarned int64
	err := h.db.Model(&entity.BookingSettlement{}).
		Joins("JOIN bookings b ON b.id = booking_settlements.booking_id").
		Joins("JOIN pitches p ON p.id = b.pitch_id").
		Where("p.owner_id = ? AND booking_settlements.graduated = true", managerID).
		Select("COALESCE(SUM(booking_settlements.owner_payout_paisa), 0)").
		Scan(&totalEarned).Error
	if err != nil {
		log.Error().Err(err).Msg("analytics: sum earned error")
		return response.InternalError(c)
	}

	// TotalPending: sum of owner_payout_paisa from non-graduated settlements for this manager.
	var totalPending int64
	err = h.db.Model(&entity.BookingSettlement{}).
		Joins("JOIN bookings b ON b.id = booking_settlements.booking_id").
		Joins("JOIN pitches p ON p.id = b.pitch_id").
		Where("p.owner_id = ? AND booking_settlements.graduated = false", managerID).
		Select("COALESCE(SUM(booking_settlements.owner_payout_paisa), 0)").
		Scan(&totalPending).Error
	if err != nil {
		log.Error().Err(err).Msg("analytics: sum pending error")
		return response.InternalError(c)
	}

	// TotalPaidOut: sum of payout requests with status = 'completed'.
	var totalPaidOut int64
	err = h.db.Model(&entity.PayoutRequest{}).
		Where("manager_id = ? AND status = ?", managerID, entity.PayoutStatusCompleted).
		Select("COALESCE(SUM(amount_paisa), 0)").
		Scan(&totalPaidOut).Error
	if err != nil {
		log.Error().Err(err).Msg("analytics: sum paid out error")
		return response.InternalError(c)
	}

	return response.OK(c, dto.FinancialAnalyticsResponse{
		TotalEarnedPaisa:  totalEarned,
		TotalPendingPaisa: totalPending,
		TotalPaidOutPaisa: totalPaidOut,
	})
}

// ListWHTCertificates handles GET /manager/tax/wht-certificates.
func (h *ManagerFinanceHandler) ListWHTCertificates(c echo.Context) error {
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
	offset := (page - 1) * limit

	type whtRow struct {
		entity.BookingTaxLine
		BookingID string `gorm:"column:booking_id"`
	}

	baseQ := h.db.Model(&entity.BookingTaxLine{}).
		Select("booking_tax_lines.*, b.id AS booking_id").
		Joins("JOIN booking_settlements bs ON bs.id = booking_tax_lines.settlement_id").
		Joins("JOIN bookings b ON b.id = bs.booking_id").
		Joins("JOIN pitches p ON p.id = b.pitch_id").
		Where("p.owner_id = ? AND booking_tax_lines.tax_type = 'wht'", managerID)

	var total int64
	if err := baseQ.Session(&gorm.Session{}).Count(&total).Error; err != nil {
		log.Error().Err(err).Msg("count wht certificates error")
		return response.InternalError(c)
	}

	var rows []whtRow
	if err := baseQ.Order("booking_tax_lines.created_at DESC").
		Limit(limit).Offset(offset).
		Scan(&rows).Error; err != nil {
		log.Error().Err(err).Msg("list wht certificates error")
		return response.InternalError(c)
	}

	items := make([]dto.WHTCertificateResponse, len(rows))
	for i, r := range rows {
		items[i] = dto.WHTCertificateResponse{
			SettlementID: r.BookingTaxLine.SettlementID.String(),
			BookingID:    r.BookingID,
			TaxType:      r.BookingTaxLine.TaxType,
			RateBps:      r.BookingTaxLine.RateBps,
			AmountPaisa:  r.BookingTaxLine.AmountPaisa,
			CreatedAt:    r.BookingTaxLine.CreatedAt.Format(time.RFC3339),
		}
	}

	return response.OKPaginated(c, items, response.Meta{Page: page, Limit: limit, Total: total})
}

// GetTaxSummary handles GET /manager/tax/summary.
func (h *ManagerFinanceHandler) GetTaxSummary(c echo.Context) error {
	managerID := c.Get(mw.UserIDKey).(uuid.UUID)

	var items []dto.TaxSummaryItem
	err := h.db.Raw(`
		SELECT btl.tax_type,
		       COALESCE(SUM(btl.amount_paisa), 0) AS amount_paisa,
		       COUNT(*) AS count
		FROM booking_tax_lines btl
		JOIN booking_settlements bs ON bs.id = btl.settlement_id
		JOIN bookings b ON b.id = bs.booking_id
		JOIN pitches p ON p.id = b.pitch_id
		WHERE p.owner_id = ?
		GROUP BY btl.tax_type
		ORDER BY btl.tax_type
	`, managerID).Scan(&items).Error
	if err != nil {
		log.Error().Err(err).Msg("get tax summary error")
		return response.InternalError(c)
	}

	if items == nil {
		items = []dto.TaxSummaryItem{}
	}

	return response.OK(c, items)
}
