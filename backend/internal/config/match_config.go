package config

import (
	"github.com/spf13/viper"
)

// MatchConfig captures all the tunable knobs for the matchmaking + safety
// layer. Sourced from Consul (which is hydrated by docker-compose env via
// consul-init at startup) so business policy can be tuned without a redeploy.
type MatchConfig struct {
	// Economics
	JoinFeeBDT             int // commitment fee debited on join
	DefaultDurationMinutes int // applied when host omits duration

	// Cancellation policy
	LateCancelHoursThreshold int // cancel within N hours = forfeit fee
	LateCancelStrikeLimit    int // N strikes within window = hosting ban
	LateCancelStrikeWindow   int // strike-counter window in days
	HostingBanDays           int // length of suspension when limit hit

	// Trust + safety
	AgeGateMinimum             int // 16+ to post/join external matches
	TrustGateMinSuccessful     int // need ≥N successful matches to host external
	AutoSuspendReportThreshold int // auto-suspend post after N reports

	// External-pitch verification
	ExternalPitchVerifyMinMatches int // promote to "verified" after N successful matches

	// Auto-cancel policy
	AutoCancelBufferMinutes int // cancel-and-refund this many minutes BEFORE kickoff if not filled
	AutoCancelMinFillPct    int // % of spots that must be filled by the buffer cutoff (0–100)

	// Joiner-cancel policy: leave + auto-refund only allowed this many minutes
	// before kickoff. After this window the seat is released but the payment
	// is held for host review.
	JoinerCancelMinMinutesBeforeKickoff int

	// ── Aviv pricing plan ────────────────────────────────────────────
	// Volume-tiered marketplace commission + walk-in arbitrage + trial.
	// All values are basis points (1000 = 10%). Overridable via Consul.
	TrialDays                int // free-trial length on new pitches
	Tier1Bps                 int // commission for marketplace bookings 0..(Tier2Bookings-1)/month
	Tier2Bookings            int // monthly threshold to enter Tier 2
	Tier2Bps                 int
	Tier3Bookings            int // monthly threshold to enter Tier 3
	Tier3Bps                 int
	WalkinBps                int // walk-in commission when "Turfinn handles cash" is OFF
	WalkinPaymentHandlingBps int // walk-in commission when "Turfinn handles cash" is ON
	PremiumMonthlyBDT        int // sticker price of Premium ERP tier (configurable)
	WalletInterestBpsAnnual  int // annualized interest paid on player_wallet balances
}

// LoadMatchConfig reads MatchConfig from viper (which has Consul + env baked in).
// Defaults are conservative and applied per-field when the key is missing.
func LoadMatchConfig() MatchConfig {
	v := viper.GetViper()
	v.SetDefault("MATCH_JOIN_FEE_BDT", 20)
	v.SetDefault("MATCH_DEFAULT_DURATION_MINUTES", 90)
	v.SetDefault("MATCH_LATE_CANCEL_HOURS_THRESHOLD", 6)
	v.SetDefault("MATCH_LATE_CANCEL_STRIKE_LIMIT", 3)
	v.SetDefault("MATCH_LATE_CANCEL_STRIKE_WINDOW_DAYS", 30)
	v.SetDefault("MATCH_HOSTING_BAN_DAYS", 30)
	v.SetDefault("MATCH_AGE_GATE_MIN", 16)
	v.SetDefault("MATCH_TRUST_GATE_MIN_SUCCESSFUL", 3)
	v.SetDefault("MATCH_AUTO_SUSPEND_REPORT_THRESHOLD", 3)
	v.SetDefault("MATCH_EXTERNAL_PITCH_VERIFY_MIN_MATCHES", 3)
	v.SetDefault("MATCH_AUTO_CANCEL_BUFFER_MINUTES", 30)
	v.SetDefault("MATCH_AUTO_CANCEL_MIN_FILL_PCT", 50)
	v.SetDefault("MATCH_JOINER_CANCEL_MIN_MINUTES_BEFORE_KICKOFF", 60)

	// Aviv defaults: 60-day trial, 12/10/8% volume tiers, 0%/2% walk-in,
	// 2,000 BDT premium ERP. Anything tunable later via Consul keys
	// AVIV_*  (e.g. AVIV_TIER1_BPS=1100 to drop Tier 1 to 11%).
	v.SetDefault("AVIV_TRIAL_DAYS", 60)
	v.SetDefault("AVIV_TIER1_BPS", 1200)         // 12% on bookings 0..30/mo
	v.SetDefault("AVIV_TIER2_BOOKINGS", 31)
	v.SetDefault("AVIV_TIER2_BPS", 1000)         // 10% on bookings 31..100/mo
	v.SetDefault("AVIV_TIER3_BOOKINGS", 101)
	v.SetDefault("AVIV_TIER3_BPS", 800)          // 8% on bookings 101+/mo
	v.SetDefault("AVIV_WALKIN_BPS", 0)           // 0% by default
	v.SetDefault("AVIV_WALKIN_PAYMENT_HANDLING_BPS", 200) // 2% if owner opts into cash-handling
	v.SetDefault("AVIV_PREMIUM_MONTHLY_BDT", 2000)
	v.SetDefault("AVIV_WALLET_INTEREST_BPS_ANNUAL", 50) // 0.5% annualized on player wallet
	return MatchConfig{
		JoinFeeBDT:                    v.GetInt("MATCH_JOIN_FEE_BDT"),
		DefaultDurationMinutes:        v.GetInt("MATCH_DEFAULT_DURATION_MINUTES"),
		LateCancelHoursThreshold:      v.GetInt("MATCH_LATE_CANCEL_HOURS_THRESHOLD"),
		LateCancelStrikeLimit:         v.GetInt("MATCH_LATE_CANCEL_STRIKE_LIMIT"),
		LateCancelStrikeWindow:        v.GetInt("MATCH_LATE_CANCEL_STRIKE_WINDOW_DAYS"),
		HostingBanDays:                v.GetInt("MATCH_HOSTING_BAN_DAYS"),
		AgeGateMinimum:                v.GetInt("MATCH_AGE_GATE_MIN"),
		TrustGateMinSuccessful:        v.GetInt("MATCH_TRUST_GATE_MIN_SUCCESSFUL"),
		AutoSuspendReportThreshold:    v.GetInt("MATCH_AUTO_SUSPEND_REPORT_THRESHOLD"),
		ExternalPitchVerifyMinMatches: v.GetInt("MATCH_EXTERNAL_PITCH_VERIFY_MIN_MATCHES"),
		AutoCancelBufferMinutes:       v.GetInt("MATCH_AUTO_CANCEL_BUFFER_MINUTES"),
		AutoCancelMinFillPct:          v.GetInt("MATCH_AUTO_CANCEL_MIN_FILL_PCT"),
		JoinerCancelMinMinutesBeforeKickoff: v.GetInt("MATCH_JOINER_CANCEL_MIN_MINUTES_BEFORE_KICKOFF"),

		TrialDays:                v.GetInt("AVIV_TRIAL_DAYS"),
		Tier1Bps:                 v.GetInt("AVIV_TIER1_BPS"),
		Tier2Bookings:            v.GetInt("AVIV_TIER2_BOOKINGS"),
		Tier2Bps:                 v.GetInt("AVIV_TIER2_BPS"),
		Tier3Bookings:            v.GetInt("AVIV_TIER3_BOOKINGS"),
		Tier3Bps:                 v.GetInt("AVIV_TIER3_BPS"),
		WalkinBps:                v.GetInt("AVIV_WALKIN_BPS"),
		WalkinPaymentHandlingBps: v.GetInt("AVIV_WALKIN_PAYMENT_HANDLING_BPS"),
		PremiumMonthlyBDT:        v.GetInt("AVIV_PREMIUM_MONTHLY_BDT"),
		WalletInterestBpsAnnual:  v.GetInt("AVIV_WALLET_INTEREST_BPS_ANNUAL"),
	}
}
