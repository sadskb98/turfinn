// Package sslcommerz provides an HTTP client for the SSLCommerz payment gateway.
// It covers payment initiation (redirecting the customer to the gateway page) and
// post-payment validation via the SSLCommerz Validation API.
//
// The client is intentionally free of Viper/config logic; callers read env vars
// via their own config mechanism and pass values to NewClient.
package sslcommerz

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// defaultHTTPTimeout is applied to all outbound SSLCommerz API calls.
const defaultHTTPTimeout = 15 * time.Second

// Client is a thin wrapper around the SSLCommerz HTTP API.
// It is safe for concurrent use.
type Client struct {
	storeID     string
	storePasswd string
	baseURL     string // e.g. https://sandbox.sslcommerz.com
	http        *http.Client
}

// NewClient creates a new SSLCommerz Client.
//
// Parameters:
//   - storeID     — SSLCZ_STORE_ID
//   - storePasswd — SSLCZ_STORE_PASSWD
//   - baseURL     — SSLCZ_BASE_URL (sandbox: https://sandbox.sslcommerz.com)
//
// Callers build callback URLs (success, fail, cancel, IPN) themselves and pass
// them in InitiateRequest.
func NewClient(storeID, storePasswd, baseURL string) *Client {
	return &Client{
		storeID:     storeID,
		storePasswd: storePasswd,
		baseURL:     strings.TrimRight(baseURL, "/"),
		http:        &http.Client{Timeout: defaultHTTPTimeout},
	}
}

// InitiateRequest carries the fields required to open a payment session with SSLCommerz.
// All string fields are validated non-empty by the caller before passing here.
type InitiateRequest struct {
	// Transaction
	TranID      string // unique transaction ID (caller-generated)
	TotalAmount string // formatted as "NNNN.NN" (paisa already converted to taka)
	Currency    string // default "BDT"

	// Product
	ProductName     string
	ProductCategory string
	ProductProfile  string // default "general"

	// Customer
	CustomerName    string
	CustomerEmail   string
	CustomerPhone   string
	CustomerAddress string
	CustomerCity    string
	CustomerCountry string // default "Bangladesh"

	// Callbacks (built from appBaseURL by the caller, or pre-set)
	SuccessURL string
	FailURL    string
	CancelURL  string
	IPNURL     string

	// EMI
	EMIOption int // 0 = no EMI (Go zero value)
}

// initiateResponse mirrors the JSON body returned by the SSLCommerz gateway init endpoint.
type initiateResponse struct {
	Status         string `json:"status"`
	Failedreason   string `json:"failedreason"`
	GatewayPageURL string `json:"GatewayPageURL"`
}

// ValidateResponse contains the fields we surface from the SSLCommerz Validation API.
type ValidateResponse struct {
	Status      string `json:"status"`
	TranID      string `json:"tran_id"`
	ValID       string `json:"val_id"`
	BankTranID  string `json:"bank_tran_id"` // required for issuing refunds later
	Amount      string `json:"amount"`
	CardType    string `json:"card_type"`
	StoreAmount string `json:"store_amount"`
	TranDate    string `json:"tran_date"`
}

// Initiate opens a payment session with SSLCommerz and returns the URL to which the
// customer browser should be redirected.
//
// It POSTs form-encoded data to {baseURL}/gwprocess/v4/api.php and returns the
// GatewayPageURL from the JSON response.
func (c *Client) Initiate(ctx context.Context, req InitiateRequest) (string, error) {
	// Apply defaults.
	if req.Currency == "" {
		req.Currency = "BDT"
	}
	if req.ProductProfile == "" {
		req.ProductProfile = "general"
	}
	if req.CustomerCountry == "" {
		req.CustomerCountry = "Bangladesh"
	}

	form := url.Values{}
	form.Set("store_id", c.storeID)
	form.Set("store_passwd", c.storePasswd)
	form.Set("total_amount", req.TotalAmount)
	form.Set("currency", req.Currency)
	form.Set("tran_id", req.TranID)
	form.Set("product_name", req.ProductName)
	form.Set("product_category", req.ProductCategory)
	form.Set("product_profile", req.ProductProfile)
	form.Set("cus_name", req.CustomerName)
	form.Set("cus_email", req.CustomerEmail)
	form.Set("cus_phone", req.CustomerPhone)
	form.Set("cus_add1", req.CustomerAddress)
	form.Set("cus_city", req.CustomerCity)
	form.Set("cus_country", req.CustomerCountry)
	form.Set("success_url", req.SuccessURL)
	form.Set("fail_url", req.FailURL)
	form.Set("cancel_url", req.CancelURL)
	form.Set("ipn_url", req.IPNURL)
	form.Set("emi_option", fmt.Sprintf("%d", req.EMIOption))

	endpoint := c.baseURL + "/gwprocess/v4/api.php"

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint,
		strings.NewReader(form.Encode()))
	if err != nil {
		return "", fmt.Errorf("sslcommerz initiate: build request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := c.http.Do(httpReq)
	if err != nil {
		return "", fmt.Errorf("sslcommerz initiate: http: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return "", fmt.Errorf("sslcommerz initiate: read body: %w", err)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("sslcommerz initiate: unexpected HTTP status %d", resp.StatusCode)
	}

	var parsed initiateResponse
	if err := json.Unmarshal(body, &parsed); err != nil {
		return "", fmt.Errorf("sslcommerz initiate: decode response: %w", err)
	}

	if parsed.Status != "SUCCESS" {
		return "", fmt.Errorf("sslcommerz initiate: gateway error: %s", parsed.Failedreason)
	}
	if parsed.GatewayPageURL == "" {
		return "", fmt.Errorf("sslcommerz initiate: empty GatewayPageURL in response")
	}

	return parsed.GatewayPageURL, nil
}

// RefundResponse is the parsed shape of the refund initiation API.
//
// SSLCommerz returns:
//   - APIConnect: SUCCESS / FAILED
//   - Status:     refund_initiated | refund_failed
//   - RefundRefID — opaque ID we store for audit / status polling.
type RefundResponse struct {
	APIConnect  string `json:"APIConnect"`
	Status      string `json:"status"`
	BankTranID  string `json:"bank_tran_id"`
	TranID      string `json:"trans_id"`
	RefundRefID string `json:"refund_ref_id"`
	Errors      string `json:"errorReason"`
}

// Refund issues a refund against a settled SSLCommerz transaction.
//
// SSLCommerz endpoint:
//
//	GET /validator/api/merchantTransIDvalidationAPI.php?
//	    bank_tran_id=...&refund_amount=...&refund_remarks=...
//	    &store_id=...&store_passwd=...&v=1&format=json
//
// `bankTranID` is the bank-side transaction identifier we got back from the
// Validate API (`bank_tran_id` field). We store it on the payment row at
// success time so we have it available for refunds.
//
// Returns the refund ref ID on success, or an error describing why SSL
// rejected the refund (most common: amount > original tx, or already refunded).
func (c *Client) Refund(
	ctx context.Context,
	bankTranID string,
	amountTaka string,
	remarks string,
) (RefundResponse, error) {
	params := url.Values{}
	params.Set("bank_tran_id", bankTranID)
	params.Set("refund_amount", amountTaka)
	params.Set("refund_remarks", remarks)
	params.Set("store_id", c.storeID)
	params.Set("store_passwd", c.storePasswd) // redact in access logs
	params.Set("v", "1")
	params.Set("format", "json")

	endpoint := c.baseURL + "/validator/api/merchantTransIDvalidationAPI.php?" + params.Encode()
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return RefundResponse{}, fmt.Errorf("sslcommerz refund: build request: %w", err)
	}
	resp, err := c.http.Do(httpReq)
	if err != nil {
		return RefundResponse{}, fmt.Errorf("sslcommerz refund: http: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return RefundResponse{}, fmt.Errorf("sslcommerz refund: read body: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return RefundResponse{}, fmt.Errorf("sslcommerz refund: status %d body=%s", resp.StatusCode, string(body))
	}

	var out RefundResponse
	if err := json.Unmarshal(body, &out); err != nil {
		return RefundResponse{}, fmt.Errorf("sslcommerz refund: decode: %w", err)
	}
	// Idempotent success: SSL responds with errorReason like
	// "Already refund initiated!" or "Already refunded" when the refund has
	// already been accepted (e.g. on a retry, or after a network timeout
	// caused us to lose the original refund_ref_id). Treat as success — the
	// money is on its way back, even though we don't have a fresh ref_id.
	if reasonIndicatesAlreadyAccepted(out.Errors) {
		// Empty RefundRefID is acceptable here — the caller persists `nil`.
		return out, nil
	}
	if out.APIConnect != "SUCCESS" || out.Status == "refund_failed" {
		reason := out.Errors
		if reason == "" {
			reason = out.Status
		}
		return out, fmt.Errorf("sslcommerz refund rejected: %s", reason)
	}
	return out, nil
}

// reasonIndicatesAlreadyAccepted matches the messages SSL returns when a
// refund has already been accepted on a prior call. The API has no
// dedicated status for this — we have to pattern-match the human-readable
// errorReason.
func reasonIndicatesAlreadyAccepted(reason string) bool {
	r := strings.ToLower(reason)
	return strings.Contains(r, "already refund initiated") ||
		strings.Contains(r, "already refunded")
}

// Validate queries the SSLCommerz Validation API to confirm a completed transaction.
//
// It GETs {baseURL}/validator/api/validationserverAPI.php with the val_id, store_id,
// store_passwd, and format=json query parameters.
func (c *Client) Validate(ctx context.Context, valID string) (ValidateResponse, error) {
	params := url.Values{}
	params.Set("val_id", valID)
	params.Set("store_id", c.storeID)
	// store_passwd appears in query string as required by SSLCommerz Validate API — no alternative;
	// ensure reverse proxy / access log middleware redacts this parameter before production.
	params.Set("store_passwd", c.storePasswd)
	params.Set("format", "json")

	endpoint := c.baseURL + "/validator/api/validationserverAPI.php?" + params.Encode()

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return ValidateResponse{}, fmt.Errorf("sslcommerz validate: build request: %w", err)
	}

	resp, err := c.http.Do(httpReq)
	if err != nil {
		return ValidateResponse{}, fmt.Errorf("sslcommerz validate: http: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return ValidateResponse{}, fmt.Errorf("sslcommerz validate: read body: %w", err)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return ValidateResponse{}, fmt.Errorf("sslcommerz validate: unexpected HTTP status %d", resp.StatusCode)
	}

	var result ValidateResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return ValidateResponse{}, fmt.Errorf("sslcommerz validate: decode response: %w", err)
	}

	return result, nil
}
