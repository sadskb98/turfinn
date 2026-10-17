package dto

// AdminCreateFeeConfigRequest is the request body for POST /admin/fee-configs.
type AdminCreateFeeConfigRequest struct {
	ManagerID               *string `json:"manager_id"`                                                       // optional; nil = global
	CommissionBps           int     `json:"commission_bps"            validate:"min=0,max=10000"`
	PayoutMinThresholdPaisa int64   `json:"payout_min_threshold_paisa" validate:"min=0"`
	HoldDays                int     `json:"hold_days"                 validate:"min=0,max=365"`
	ValidFrom               *string `json:"valid_from"`               // optional YYYY-MM-DD
	ValidTo                 *string `json:"valid_to"`                 // optional YYYY-MM-DD
}

// AdminUpdateFeeConfigRequest is the request body for PUT /admin/fee-configs/:id.
type AdminUpdateFeeConfigRequest struct {
	CommissionBps           *int    `json:"commission_bps"            validate:"omitempty,min=0,max=10000"`
	PayoutMinThresholdPaisa *int64  `json:"payout_min_threshold_paisa" validate:"omitempty,min=0"`
	HoldDays                *int    `json:"hold_days"                 validate:"omitempty,min=0,max=365"`
	ValidFrom               *string `json:"valid_from"`
	ValidTo                 *string `json:"valid_to"`
}

// AdminUpdateGatewayRateRequest is the request body for PUT /admin/gateway-fee-rates/:card_type.
type AdminUpdateGatewayRateRequest struct {
	FeeBps int `json:"fee_bps" validate:"required,min=0,max=10000"`
}

// AdminCreateReconciliationRequest is the request body for POST /admin/gateway-fee-reconciliations.
type AdminCreateReconciliationRequest struct {
	SettlementID string `json:"settlement_id" validate:"required,uuid"`
	ChargedPaisa int64  `json:"charged_paisa" validate:"required,min=1"`
	ActualPaisa  int64  `json:"actual_paisa"  validate:"required,min=1"`
}

// AdminApprovePayoutRequest has no body.
type AdminApprovePayoutRequest struct{}

// AdminCompletePayoutRequest is the request body for PUT /admin/payouts/:id/complete.
type AdminCompletePayoutRequest struct {
	TransferReference string `json:"transfer_reference" validate:"required"`
}

// AdminRejectPayoutRequest is the request body for PUT /admin/payouts/:id/reject.
type AdminRejectPayoutRequest struct {
	RejectionReason string `json:"rejection_reason" validate:"required"`
}

// AdminPayoutRequestResponse is the response shape for a single admin payout view.
type AdminPayoutRequestResponse struct {
	ID                string `json:"id"`
	ManagerID         string `json:"manager_id"`
	AmountPaisa       int64  `json:"amount_paisa"`
	Status            string `json:"status"`
	TransferReference string `json:"transfer_reference,omitempty"`
	RejectionReason   string `json:"rejection_reason,omitempty"`
	RequestedAt       string `json:"requested_at"`
	ProcessedAt       string `json:"processed_at,omitempty"`
	CompletedAt       string `json:"completed_at,omitempty"`
}

// AdminFeeConfigResponse is the response shape for a single partner fee config.
type AdminFeeConfigResponse struct {
	ID                      string `json:"id"`
	ManagerID               string `json:"manager_id,omitempty"`
	CommissionBps           int    `json:"commission_bps"`
	PayoutMinThresholdPaisa int64  `json:"payout_min_threshold_paisa"`
	HoldDays                int    `json:"hold_days"`
	ValidFrom               string `json:"valid_from,omitempty"`
	ValidTo                 string `json:"valid_to,omitempty"`
	CreatedAt               string `json:"created_at"`
	UpdatedAt               string `json:"updated_at"`
}

// AdminGatewayFeeRateResponse is the response shape for a single gateway fee rate.
type AdminGatewayFeeRateResponse struct {
	ID        string `json:"id"`
	CardType  string `json:"card_type"`
	FeeBps    int    `json:"fee_bps"`
	UpdatedAt string `json:"updated_at"`
}

// AdminReconciliationResponse is the response shape for a gateway fee reconciliation row.
type AdminReconciliationResponse struct {
	ID           string `json:"id"`
	SettlementID string `json:"settlement_id"`
	ChargedPaisa int64  `json:"charged_paisa"`
	ActualPaisa  int64  `json:"actual_paisa"`
	DiffPaisa    int64  `json:"diff_paisa"`
	CreatedAt    string `json:"created_at"`
}
