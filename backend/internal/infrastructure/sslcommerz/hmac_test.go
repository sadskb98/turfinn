package sslcommerz

import (
	"testing"
)

func TestVerifySign(t *testing.T) {
	// Baseline params used in several cases.
	// verify_key lists three fields; sorted order: amount, currency, tran_id.
	// Concatenated values: "1500.00" + "BDT" + "TXN123" = "1500.00BDTTXN123"
	// MD5("testpassword") = "e16b2ab8d12314bf4efbd6203906ea6c"
	// Full string: "1500.00BDTTXN123e16b2ab8d12314bf4efbd6203906ea6c"
	// MD5 of that  = "09e3400aa10dd5748eb2bced422f4b33"
	const (
		validSign   = "09e3400aa10dd5748eb2bced422f4b33"
		storePasswd = "testpassword"
	)

	baseParams := func() map[string]string {
		return map[string]string{
			"tran_id":    "TXN123",
			"amount":     "1500.00",
			"currency":   "BDT",
			"verify_key": "amount,currency,tran_id",
			"verify_sign": validSign,
		}
	}

	tests := []struct {
		name        string
		params      map[string]string
		storePasswd string
		want        bool
	}{
		{
			name:        "valid signature",
			params:      baseParams(),
			storePasswd: storePasswd,
			want:        true,
		},
		{
			name: "valid signature uppercase compare",
			params: func() map[string]string {
				p := baseParams()
				p["verify_sign"] = "09E3400AA10DD5748EB2BCED422F4B33" // uppercase
				return p
			}(),
			storePasswd: storePasswd,
			want:        true,
		},
		{
			name: "tampered value",
			params: func() map[string]string {
				p := baseParams()
				p["amount"] = "9999.00" // changed after signing
				return p
			}(),
			storePasswd: storePasswd,
			want:        false,
		},
		{
			name:        "wrong password",
			params:      baseParams(),
			storePasswd: "wrongpassword",
			want:        false,
		},
		{
			name: "missing verify_key",
			params: func() map[string]string {
				p := baseParams()
				delete(p, "verify_key")
				return p
			}(),
			storePasswd: storePasswd,
			want:        false,
		},
		{
			name: "empty verify_key",
			params: func() map[string]string {
				p := baseParams()
				p["verify_key"] = ""
				return p
			}(),
			storePasswd: storePasswd,
			want:        false,
		},
		{
			name: "missing verify_sign",
			params: func() map[string]string {
				p := baseParams()
				delete(p, "verify_sign")
				return p
			}(),
			storePasswd: storePasswd,
			want:        false,
		},
		{
			name: "listed key absent from params",
			params: func() map[string]string {
				p := baseParams()
				// verify_key references "amount" but we delete it
				delete(p, "amount")
				return p
			}(),
			storePasswd: storePasswd,
			want:        false,
		},
		{
			name: "empty verify_sign",
			params: func() map[string]string {
				p := baseParams()
				p["verify_sign"] = ""
				return p
			}(),
			storePasswd: storePasswd,
			want:        false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := VerifySign(tc.params, tc.storePasswd)
			if got != tc.want {
				t.Errorf("VerifySign() = %v, want %v", got, tc.want)
			}
		})
	}
}
