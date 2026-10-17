package dto

// PlatformWalletResponse is the response shape for GET /super-admin/finance/platform-wallet.
type PlatformWalletResponse struct {
	BalancePaisa       int64                      `json:"balance_paisa"`
	RecentTransactions []PlatformWalletTxResponse `json:"recent_transactions"`
}

// PlatformWalletTxResponse is a single platform wallet transaction.
type PlatformWalletTxResponse struct {
	ID          string `json:"id"`
	AmountPaisa int64  `json:"amount_paisa"`
	TxType      string `json:"tx_type"`
	Description string `json:"description"`
	CreatedAt   string `json:"created_at"`
}

// RevenueSummaryResponse is the response shape for GET /super-admin/finance/revenue-summary.
type RevenueSummaryResponse struct {
	GMVPaisa         int64 `json:"gmv_paisa"`
	GrossFeePaisa    int64 `json:"gross_fee_paisa"`
	GatewayCostPaisa int64 `json:"gateway_cost_paisa"`
	NetRevenuePaisa  int64 `json:"net_revenue_paisa"`
	SettlementCount  int64 `json:"settlement_count"`
}

// ManagerBalanceItem is a single row in GET /super-admin/finance/manager-balances.
type ManagerBalanceItem struct {
	ManagerID             string `json:"manager_id"`
	ManagerName           string `json:"manager_name"`
	ManagerPhone          string `json:"manager_phone"`
	AvailableBalancePaisa int64  `json:"available_balance_paisa"`
	PendingBalancePaisa   int64  `json:"pending_balance_paisa"`
}

// ReceivableItem is a single row in GET /super-admin/finance/receivables.
type ReceivableItem struct {
	ID           string `json:"id"`
	ManagerID    string `json:"manager_id"`
	SettlementID string `json:"settlement_id"`
	AmountPaisa  int64  `json:"amount_paisa"`
	Status       string `json:"status"`
	CreatedAt    string `json:"created_at"`
}
