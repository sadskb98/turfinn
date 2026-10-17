package service

import (
	"testing"

	"github.com/turfinn/backend/internal/domain/entity"
)

// makePartnerFeeConfig builds a minimal PartnerFeeConfig for test use.
func makePartnerFeeConfig(commissionBps, holdDays int) *entity.PartnerFeeConfig {
	return &entity.PartnerFeeConfig{
		CommissionBps: commissionBps,
		HoldDays:      holdDays,
	}
}

// makeGatewayFeeRate builds a minimal GatewayFeeRate for test use.
func makeGatewayFeeRate(feeBps int) *entity.GatewayFeeRate {
	return &entity.GatewayFeeRate{FeeBps: feeBps}
}

// makeTaxRateEntity builds a minimal TaxRate for test use.
func makeTaxRateEntity(rateBps int) *entity.TaxRate {
	return &entity.TaxRate{RateBps: rateBps}
}

// TestComputeSplit exercises the pure ComputeSplit function. After the formula fix,
// turfinnRevenue = commission exactly, so the invariant
// ownerPayout + turfinnRevenue + gatewayFee == gross holds unconditionally —
// even with real Bangladesh rates (15% VAT, 3.5% WHT) where vatRate != whtRate.
func TestComputeSplit(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name               string
		bookingAmountPaisa int64
		commissionBps      int
		gatewayFeeBps      int
		vatRateBps         int
		whtRateBps         int
		// Expected outputs
		wantGatewayFee     int64
		wantOwnerPayout    int64
		wantTurfinnRevenue int64
		wantVAT            int64
		wantWHT            int64
	}{
		{
			// Standard split using real Bangladesh rates: 15% commission, 1.75% gateway,
			// 15% VAT, 3.5% WHT. VAT != WHT — the key case the old formula got wrong.
			//
			// bookingAmount = 150_000 paisa (BDT 1500)
			// gatewayFee  = roundBps(150000, 175)  = (26_250_000 + 5000) / 10000 = 2625
			// netAfterGW  = 150000 - 2625 = 147375
			// commission  = roundBps(147375, 1500) = (221_062_500 + 5000) / 10000 = 22106
			// vat         = roundBps(22106, 1500)  = (33_159_000 + 5000) / 10000 = 3316
			// wht         = roundBps(22106, 350)   = (7_737_100 + 5000)  / 10000 = 774
			// turfinnRev  = 22106  (= commission; VAT/WHT are sub-ledger only)
			// ownerPayout = 150000 - 2625 - 22106 = 125269
			// invariant   = 125269 + 22106 + 2625 = 150000 ✓
			name:               "standard_split",
			bookingAmountPaisa: 150_000,
			commissionBps:      1500,
			gatewayFeeBps:      175,
			vatRateBps:         1500,
			whtRateBps:         350,
			wantGatewayFee:     2625,
			wantOwnerPayout:    125269,
			wantVAT:            3316,
			wantWHT:            774,
			wantTurfinnRevenue: 22106,
		},
		{
			// Zero commission — owner gets everything minus gateway fee.
			// Any tax rates are valid since commission = 0 → vat = wht = 0.
			//
			// gatewayFee  = roundBps(50000, 175) = (8_750_000 + 5000) / 10000 = 875
			// netAfterGW  = 49125
			// commission  = roundBps(49125, 0) = 0
			// vat = wht = 0
			// turfinnRev  = 0
			// ownerPayout = 50000 - 875 - 0 = 49125
			// invariant   = 49125 + 0 + 875 = 50000 ✓
			name:               "zero_commission",
			bookingAmountPaisa: 50_000,
			commissionBps:      0,
			gatewayFeeBps:      175,
			vatRateBps:         1500,
			whtRateBps:         350,
			wantGatewayFee:     875,
			wantOwnerPayout:    49125,
			wantVAT:            0,
			wantWHT:            0,
			wantTurfinnRevenue: 0,
		},
		{
			// Rounding edge case: amount = 1 paisa, 50% commission, zero tax rates.
			//
			// gatewayFee  = roundBps(1, 175) = (175 + 5000) / 10000 = 0
			// netAfterGW  = 1
			// commission  = roundBps(1, 5000) = (5000 + 5000) / 10000 = 1
			// vat = wht = 0
			// turfinnRev  = 1  (= commission)
			// ownerPayout = 1 - 0 - 1 = 0
			// invariant   = 0 + 1 + 0 = 1 ✓
			name:               "rounding_edge_case_1_paisa",
			bookingAmountPaisa: 1,
			commissionBps:      5000,
			gatewayFeeBps:      175,
			vatRateBps:         0,
			whtRateBps:         0,
			wantGatewayFee:     0,
			wantOwnerPayout:    0,
			wantVAT:            0,
			wantWHT:            0,
			wantTurfinnRevenue: 1,
		},
		{
			// Large booking (1 000 BDT = 100 000 paisa) confirming invariant holds at scale.
			//
			// gatewayFee  = roundBps(100000, 200) = (20_000_000 + 5000) / 10000 = 2000
			// netAfterGW  = 98000
			// commission  = roundBps(98000, 1000) = (98_000_000 + 5000) / 10000 = 9800
			// vat         = roundBps(9800, 300) = (2_940_000 + 5000) / 10000 = 294
			// wht         = roundBps(9800, 300) = 294
			// turfinnRev  = 9800  (= commission)
			// ownerPayout = 100000 - 2000 - 9800 = 88200
			// invariant   = 88200 + 9800 + 2000 = 100000 ✓
			name:               "large_booking_symmetric_taxes",
			bookingAmountPaisa: 100_000,
			commissionBps:      1000,
			gatewayFeeBps:      200,
			vatRateBps:         300,
			whtRateBps:         300,
			wantGatewayFee:     2000,
			wantOwnerPayout:    88200,
			wantVAT:            294,
			wantWHT:            294,
			wantTurfinnRevenue: 9800,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			cfg := makePartnerFeeConfig(tc.commissionBps, 3)
			gfr := makeGatewayFeeRate(tc.gatewayFeeBps)
			vatRate := makeTaxRateEntity(tc.vatRateBps)
			whtRate := makeTaxRateEntity(tc.whtRateBps)

			got := ComputeSplit(tc.bookingAmountPaisa, cfg, gfr, vatRate, whtRate)

			if got.TotalPaidPaisa != tc.bookingAmountPaisa {
				t.Errorf("TotalPaidPaisa: got %d, want %d", got.TotalPaidPaisa, tc.bookingAmountPaisa)
			}
			if got.GatewayFeePaisa != tc.wantGatewayFee {
				t.Errorf("GatewayFeePaisa: got %d, want %d", got.GatewayFeePaisa, tc.wantGatewayFee)
			}
			if got.OwnerPayoutPaisa != tc.wantOwnerPayout {
				t.Errorf("OwnerPayoutPaisa: got %d, want %d", got.OwnerPayoutPaisa, tc.wantOwnerPayout)
			}
			if got.TurfinnRevenuePaisa != tc.wantTurfinnRevenue {
				t.Errorf("TurfinnRevenuePaisa: got %d, want %d", got.TurfinnRevenuePaisa, tc.wantTurfinnRevenue)
			}
			if got.VATAmountPaisa != tc.wantVAT {
				t.Errorf("VATAmountPaisa: got %d, want %d", got.VATAmountPaisa, tc.wantVAT)
			}
			if got.WHTAmountPaisa != tc.wantWHT {
				t.Errorf("WHTAmountPaisa: got %d, want %d", got.WHTAmountPaisa, tc.wantWHT)
			}

			// Invariant: three top-level buckets must reconstitute the gross payment.
			// This holds unconditionally because turfinnRevenue = commission, so VAT/WHT rates cancel out of the three-bucket sum.
			actualSum := got.OwnerPayoutPaisa + got.TurfinnRevenuePaisa + got.GatewayFeePaisa
			if actualSum != tc.bookingAmountPaisa {
				t.Errorf("invariant violated: ownerPayout(%d) + turfinnRevenue(%d) + gatewayFee(%d) = %d, want %d",
					got.OwnerPayoutPaisa, got.TurfinnRevenuePaisa, got.GatewayFeePaisa,
					actualSum, tc.bookingAmountPaisa)
			}
		})
	}
}

// TestComputeSplit_TotalPaidPassthrough confirms TotalPaidPaisa always equals
// the input regardless of other parameters (it is stored for audit, never computed).
func TestComputeSplit_TotalPaidPassthrough(t *testing.T) {
	t.Parallel()
	amounts := []int64{0, 1, 9999, 100_000, 1_000_000}
	for _, amount := range amounts {
		cfg := makePartnerFeeConfig(0, 3)   // zero commission avoids panic
		gfr := makeGatewayFeeRate(0)        // zero gateway fee
		vat := makeTaxRateEntity(0)
		wht := makeTaxRateEntity(0)
		got := ComputeSplit(amount, cfg, gfr, vat, wht)
		if got.TotalPaidPaisa != amount {
			t.Errorf("amount %d: TotalPaidPaisa = %d, want %d", amount, got.TotalPaidPaisa, amount)
		}
	}
}
