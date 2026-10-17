package dto

// ManagerWalletResponse is the response shape for GET /manager/wallet.
type ManagerWalletResponse struct {
	AvailableBalancePaisa int64 `json:"available_balance_paisa"`
	PendingBalancePaisa   int64 `json:"pending_balance_paisa"`
}

// ManagerWalletTxResponse is the response shape for a single wallet transaction.
type ManagerWalletTxResponse struct {
	ID            string `json:"id"`
	AmountPaisa   int64  `json:"amount_paisa"`
	TxType        string `json:"tx_type"`
	ReferenceType string `json:"reference_type,omitempty"`
	ReferenceID   string `json:"reference_id,omitempty"`
	Description   string `json:"description,omitempty"`
	CreatedAt     string `json:"created_at"`
}

// SettlementResponse is the response shape for a single booking settlement.
type SettlementResponse struct {
	ID                  string `json:"id"`
	BookingID           string `json:"booking_id"`
	TotalPaidPaisa      int64  `json:"total_paid_paisa"`
	OwnerPayoutPaisa    int64  `json:"owner_payout_paisa"`
	TurfinnRevenuePaisa int64  `json:"turfinn_revenue_paisa"`
	GatewayFeePaisa     int64  `json:"gateway_fee_paisa"`
	HoldDays            int    `json:"hold_days"`
	Graduated           bool   `json:"graduated"`
	SettledAt           string `json:"settled_at,omitempty"`
	CreatedAt           string `json:"created_at"`
}

// ManagerFeeConfigResponse is the response shape for GET /manager/financials/fee-config.
type ManagerFeeConfigResponse struct {
	CommissionBps           int   `json:"commission_bps"`
	PayoutMinThresholdPaisa int64 `json:"payout_min_threshold_paisa"`
	HoldDays                int   `json:"hold_days"`
	IsManagerSpecific       bool  `json:"is_manager_specific"`
}

// FinancialAnalyticsResponse is the response shape for GET /manager/financials/analytics.
type FinancialAnalyticsResponse struct {
	TotalEarnedPaisa  int64 `json:"total_earned_paisa"`
	TotalPendingPaisa int64 `json:"total_pending_paisa"`
	TotalPaidOutPaisa int64 `json:"total_paid_out_paisa"`
}

// WHTCertificateResponse is the response shape for a single WHT tax line.
type WHTCertificateResponse struct {
	SettlementID string `json:"settlement_id"`
	BookingID    string `json:"booking_id"`
	TaxType      string `json:"tax_type"`
	RateBps      int    `json:"rate_bps"`
	AmountPaisa  int64  `json:"amount_paisa"`
	CreatedAt    string `json:"created_at"`
}

// TaxSummaryItem is one row in the GET /manager/tax/summary response.
type TaxSummaryItem struct {
	TaxType     string `json:"tax_type"`
	AmountPaisa int64  `json:"amount_paisa"`
	Count       int64  `json:"count"`
}
