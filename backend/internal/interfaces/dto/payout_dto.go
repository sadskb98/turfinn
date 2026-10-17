package dto

// AddPayoutMethodRequest is the request body for POST /manager/payout-methods.
type AddPayoutMethodRequest struct {
	MethodType    string `json:"method_type"    validate:"required,oneof=bank bkash nagad rocket"`
	AccountNumber string `json:"account_number" validate:"required"`
	AccountName   string `json:"account_name"   validate:"required"`
	BankName      string `json:"bank_name"`
	RoutingNumber string `json:"routing_number"`
}

// RequestPayoutRequest is the request body for POST /manager/payouts.
type RequestPayoutRequest struct {
	AmountPaisa    int64  `json:"amount_paisa"      validate:"required,min=1"`
	PayoutMethodID string `json:"payout_method_id"  validate:"required,uuid"`
}

// PayoutMethodResponse is the response shape for a single payout method.
type PayoutMethodResponse struct {
	ID            string `json:"id"`
	MethodType    string `json:"method_type"`
	AccountNumber string `json:"account_number"`
	AccountName   string `json:"account_name"`
	BankName      string `json:"bank_name"`
	RoutingNumber string `json:"routing_number"`
	IsVerified    bool   `json:"is_verified"`
	CreatedAt     string `json:"created_at"`
}

// PayoutRequestResponse is the response shape for a single payout request.
type PayoutRequestResponse struct {
	ID            string `json:"id"`
	Amount        int64  `json:"amount_paisa"`
	Status        string `json:"status"`
	MethodType    string `json:"method_type"`
	AccountNumber string `json:"account_number"`
	RequestedAt   string `json:"requested_at"`
	ProcessedAt   string `json:"processed_at,omitempty"`
}
