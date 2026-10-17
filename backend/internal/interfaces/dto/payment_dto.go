package dto

// InitiateResponse is returned to the client after a payment session is opened.
type InitiateResponse struct {
	RedirectURL string `json:"redirect_url"`
}

// SSLCallbackParams holds the form fields POSTed by SSLCommerz on success / fail /
// cancel / IPN callbacks. All fields use the `form` tag so Echo can bind them from
// an application/x-www-form-urlencoded body.
type SSLCallbackParams struct {
	TranID      string `form:"tran_id"`
	ValID       string `form:"val_id"`
	Amount      string `form:"amount"`
	CardType    string `form:"card_type"`
	Status      string `form:"status"`
	VerifySign  string `form:"verify_sign"`
	VerifyKey   string `form:"verify_key"`
	StoreAmount string `form:"store_amount"`
	Currency    string `form:"currency"`
	TranDate    string `form:"tran_date"`
	BankTranID  string `form:"bank_tran_id"`
}
