package handler

import (
	"encoding/csv"
	"strconv"
	"time"

	"github.com/labstack/echo/v4"
	"github.com/rs/zerolog/log"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/interfaces/dto"
	"github.com/turfinn/backend/internal/pkg/response"
	"gorm.io/gorm"
)

// SuperAdminFinanceHandler handles super-admin finance and tax export endpoints.
type SuperAdminFinanceHandler struct {
	db *gorm.DB
}

// NewSuperAdminFinanceHandler constructs a SuperAdminFinanceHandler.
func NewSuperAdminFinanceHandler(db *gorm.DB) *SuperAdminFinanceHandler {
	return &SuperAdminFinanceHandler{db: db}
}

// revenueSummaryRow is an internal scan target for the revenue aggregate query.
type revenueSummaryRow struct {
	GMVPaisa         int64 `gorm:"column:gmv"`
	GrossFeePaisa    int64 `gorm:"column:gross_fee"`
	GatewayCostPaisa int64 `gorm:"column:gateway_cost"`
	SettlementCount  int64 `gorm:"column:settlement_count"`
}

// managerBalanceRow is an internal scan target for the manager-balances join query.
type managerBalanceRow struct {
	ManagerID             string `gorm:"column:manager_id"`
	ManagerName           string `gorm:"column:manager_name"`
	ManagerPhone          string `gorm:"column:manager_phone"`
	AvailableBalancePaisa int64  `gorm:"column:available_balance_paisa"`
	PendingBalancePaisa   int64  `gorm:"column:pending_balance_paisa"`
}

// GetPlatformWallet handles GET /super-admin/finance/platform-wallet.
// Returns the turfinn_main wallet balance and its 20 most recent transactions.
func (h *SuperAdminFinanceHandler) GetPlatformWallet(c echo.Context) error {
	var wallet entity.PlatformWallet
	if err := h.db.WithContext(c.Request().Context()).
		Table("platform_wallet").
		Where("name = ?", "turfinn_main").
		First(&wallet).Error; err != nil {
		log.Error().Err(err).Msg("superadmin finance: get platform wallet error")
		return response.InternalError(c)
	}

	var txs []entity.PlatformWalletTransaction
	if err := h.db.WithContext(c.Request().Context()).
		Table("platform_wallet_transactions").
		Where("wallet_id = ?", wallet.ID).
		Order("created_at DESC").
		Limit(20).
		Find(&txs).Error; err != nil {
		log.Error().Err(err).Msg("superadmin finance: get platform wallet transactions error")
		return response.InternalError(c)
	}

	txResponses := make([]dto.PlatformWalletTxResponse, len(txs))
	for i, tx := range txs {
		item := dto.PlatformWalletTxResponse{
			ID:          tx.ID.String(),
			AmountPaisa: tx.AmountPaisa,
			CreatedAt:   tx.CreatedAt.Format(time.RFC3339),
		}
		if tx.TxType != nil {
			item.TxType = *tx.TxType
		}
		if tx.Description != nil {
			item.Description = *tx.Description
		}
		txResponses[i] = item
	}

	return response.OK(c, dto.PlatformWalletResponse{
		BalancePaisa:       wallet.BalancePaisa,
		RecentTransactions: txResponses,
	})
}

// GetRevenueSummary handles GET /super-admin/finance/revenue-summary.
// Aggregates booking_settlements to produce GMV, gross fee, gateway cost,
// net revenue and settlement count.
func (h *SuperAdminFinanceHandler) GetRevenueSummary(c echo.Context) error {
	var row revenueSummaryRow
	if err := h.db.WithContext(c.Request().Context()).
		Model(&entity.BookingSettlement{}).
		Select(
			"COALESCE(SUM(total_paid_paisa), 0) AS gmv, " +
				"COALESCE(SUM(turfinn_revenue_paisa), 0) AS gross_fee, " +
				"COALESCE(SUM(gateway_fee_paisa), 0) AS gateway_cost, " +
				"COUNT(*) AS settlement_count",
		).
		Scan(&row).Error; err != nil {
		log.Error().Err(err).Msg("superadmin finance: get revenue summary error")
		return response.InternalError(c)
	}

	return response.OK(c, dto.RevenueSummaryResponse{
		GMVPaisa:         row.GMVPaisa,
		GrossFeePaisa:    row.GrossFeePaisa,
		GatewayCostPaisa: row.GatewayCostPaisa,
		NetRevenuePaisa:  row.GrossFeePaisa - row.GatewayCostPaisa,
		SettlementCount:  row.SettlementCount,
	})
}

// GetManagerBalances handles GET /super-admin/finance/manager-balances.
// Joins manager_wallets with users and returns balances ordered descending by
// available balance.
func (h *SuperAdminFinanceHandler) GetManagerBalances(c echo.Context) error {
	var rows []managerBalanceRow
	if err := h.db.WithContext(c.Request().Context()).Raw(`
		SELECT mw.manager_id,
		       u.name  AS manager_name,
		       u.phone AS manager_phone,
		       mw.available_balance_paisa,
		       mw.pending_balance_paisa
		FROM manager_wallets mw
		JOIN users u ON u.id = mw.manager_id
		ORDER BY mw.available_balance_paisa DESC
	`).Scan(&rows).Error; err != nil {
		log.Error().Err(err).Msg("superadmin finance: get manager balances error")
		return response.InternalError(c)
	}

	items := make([]dto.ManagerBalanceItem, len(rows))
	for i, r := range rows {
		items[i] = dto.ManagerBalanceItem{
			ManagerID:             r.ManagerID,
			ManagerName:           r.ManagerName,
			ManagerPhone:          r.ManagerPhone,
			AvailableBalancePaisa: r.AvailableBalancePaisa,
			PendingBalancePaisa:   r.PendingBalancePaisa,
		}
	}

	return response.OK(c, items)
}

// GetReceivables handles GET /super-admin/finance/receivables.
// Returns paginated outstanding manager receivables.
func (h *SuperAdminFinanceHandler) GetReceivables(c echo.Context) error {
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

	var total int64
	q := h.db.WithContext(c.Request().Context()).
		Model(&entity.ManagerReceivable{}).
		Where("status = ?", entity.ReceivableStatusOutstanding)

	if err := q.Session(&gorm.Session{}).Count(&total).Error; err != nil {
		log.Error().Err(err).Msg("superadmin finance: count receivables error")
		return response.InternalError(c)
	}

	var receivables []entity.ManagerReceivable
	if err := q.Session(&gorm.Session{}).
		Order("created_at DESC").
		Offset((page - 1) * limit).
		Limit(limit).
		Find(&receivables).Error; err != nil {
		log.Error().Err(err).Msg("superadmin finance: get receivables error")
		return response.InternalError(c)
	}

	items := make([]dto.ReceivableItem, len(receivables))
	for i, r := range receivables {
		items[i] = dto.ReceivableItem{
			ID:           r.ID.String(),
			ManagerID:    r.ManagerID.String(),
			SettlementID: r.SettlementID.String(),
			AmountPaisa:  r.AmountPaisa,
			Status:       r.Status,
			CreatedAt:    r.CreatedAt.Format(time.RFC3339),
		}
	}

	return response.OKPaginated(c, items, response.Meta{Page: page, Limit: limit, Total: total})
}

// ExportTaxCSV handles GET /super-admin/tax/export.
// Streams a CSV of booking_tax_lines for the given tax type and month range.
func (h *SuperAdminFinanceHandler) ExportTaxCSV(c echo.Context) error {
	taxType := c.QueryParam("type")
	if taxType != "vat" && taxType != "wht" {
		return response.BadRequest(c, "type must be 'vat' or 'wht'")
	}

	fromParam := c.QueryParam("from")
	toParam := c.QueryParam("to")
	if fromParam == "" || toParam == "" {
		return response.BadRequest(c, "from and to are required (YYYY-MM)")
	}

	fromTime, err := time.Parse("2006-01", fromParam)
	if err != nil {
		return response.BadRequest(c, "invalid from date, expected YYYY-MM")
	}

	toTime, err := time.Parse("2006-01", toParam)
	if err != nil {
		return response.BadRequest(c, "invalid to date, expected YYYY-MM")
	}

	// toEnd is the first day of the month after the to month (exclusive upper bound).
	toEnd := toTime.AddDate(0, 1, 0)

	var taxLines []entity.BookingTaxLine
	if err := h.db.WithContext(c.Request().Context()).
		Where("tax_type = ? AND created_at >= ? AND created_at < ?", taxType, fromTime, toEnd).
		Order("created_at ASC").
		Find(&taxLines).Error; err != nil {
		log.Error().Err(err).Msg("superadmin finance: export tax csv error")
		return response.InternalError(c)
	}

	c.Response().Header().Set("Content-Type", "text/csv")
	c.Response().Header().Set("Content-Disposition", `attachment; filename="tax-export.csv"`)
	c.Response().WriteHeader(200)

	w := csv.NewWriter(c.Response())
	if err := w.Write([]string{
		"settlement_id", "booking_id", "tax_type", "rate_bps", "amount_paisa", "created_at",
	}); err != nil {
		log.Error().Err(err).Msg("superadmin finance: write csv header error")
		return nil
	}

	// We need the booking_id from booking_settlements for each tax line.
	// Batch-fetch settlement -> booking_id mapping for the tax lines found.
	settlementIDs := make([]string, 0, len(taxLines))
	for _, tl := range taxLines {
		settlementIDs = append(settlementIDs, tl.SettlementID.String())
	}

	bookingBySettlement := make(map[string]string)
	if len(settlementIDs) > 0 {
		var settlements []entity.BookingSettlement
		if err := h.db.WithContext(c.Request().Context()).
			Select("id, booking_id").
			Where("id IN ?", settlementIDs).
			Find(&settlements).Error; err != nil {
			log.Error().Err(err).Msg("superadmin finance: fetch settlements for csv error")
			// Non-fatal: proceed without booking IDs rather than aborting.
		} else {
			for _, s := range settlements {
				bookingBySettlement[s.ID.String()] = s.BookingID.String()
			}
		}
	}

	for _, tl := range taxLines {
		bookingID := bookingBySettlement[tl.SettlementID.String()]
		if err := w.Write([]string{
			tl.SettlementID.String(),
			bookingID,
			tl.TaxType,
			strconv.Itoa(tl.RateBps),
			strconv.FormatInt(tl.AmountPaisa, 10),
			tl.CreatedAt.Format(time.RFC3339),
		}); err != nil {
			log.Error().Err(err).Msg("superadmin finance: write csv row error")
			return nil
		}
	}

	w.Flush()
	return nil
}
