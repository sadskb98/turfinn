// Package service — PricingService is the single source of truth for the
// commission rate applied to a booking. Every code path that needs to
// know "how much do we charge?" goes through ResolveCommissionBps.
//
// Resolution order (first match wins):
//   1. Trial — if pitch.TrialEndsAt is in the future → 0 bps
//   2. ERP-only plan — flat-fee tier, no per-booking commission → 0 bps
//   3. Walk-in source — pitch.WalkinFeeBpsOverride or AvivConfig.WalkinBps
//   4. Marketplace booking — pitch.MarketplaceFeeBpsOverride or volume
//      tier table from AvivConfig
//
// Pure-function-y on top of (db, cfg). No side effects. Safe to call
// from any service (booking, payment, walk-in, settlement).
package service

import (
	"context"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/turfinn/backend/internal/config"
	"github.com/turfinn/backend/internal/domain/entity"
)

type PricingService struct {
	db  *gorm.DB
	cfg config.MatchConfig
}

// NewPricingService loads MatchConfig once and reuses it. Hot config
// rotation (Consul KV change) requires an api restart for the new bps
// values to apply — accepted trade-off for simplicity.
func NewPricingService(db *gorm.DB) *PricingService {
	return &PricingService{db: db, cfg: config.LoadMatchConfig()}
}

// ResolveCommissionBps returns the basis-points commission rate for a
// new booking. monthlyVolume = how many marketplace bookings the pitch
// has already accumulated this calendar month (used for tier lookup).
// Pass 0 for walk-ins.
func (s *PricingService) ResolveCommissionBps(
	_ context.Context,
	pitch *entity.Pitch,
	source string,
	monthlyVolume int,
) int {
	if pitch == nil {
		return 0
	}
	// 1. Trial — every plan, every source is 0% during trial.
	if pitch.TrialEndsAt != nil && time.Now().Before(*pitch.TrialEndsAt) {
		return 0
	}
	// 2. ERP-only pitches have a flat monthly fee billed elsewhere; the
	// per-booking commission is always 0.
	if pitch.Plan == entity.PitchPlanERPOnly {
		return 0
	}
	// 3. Walk-in source.
	if source == "walk_in" {
		if pitch.WalkinFeeBpsOverride != nil {
			return *pitch.WalkinFeeBpsOverride
		}
		return s.cfg.WalkinBps
	}
	// 4. Marketplace booking — override always wins over volume tiers.
	if pitch.MarketplaceFeeBpsOverride != nil {
		return *pitch.MarketplaceFeeBpsOverride
	}
	switch {
	case s.cfg.Tier3Bookings > 0 && monthlyVolume >= s.cfg.Tier3Bookings:
		return s.cfg.Tier3Bps
	case s.cfg.Tier2Bookings > 0 && monthlyVolume >= s.cfg.Tier2Bookings:
		return s.cfg.Tier2Bps
	default:
		return s.cfg.Tier1Bps
	}
}

// MonthlyVolume returns the count of marketplace bookings (excluding
// cancelled ones) for this pitch in the current calendar month. Used
// by ResolveCommissionBps to pick the right tier.
//
// Walk-in bookings are excluded — they don't count toward marketplace
// tier progression. This rewards owners for actually using the
// marketplace rather than logging everything as walk-in.
func (s *PricingService) MonthlyVolume(ctx context.Context, pitchID uuid.UUID) (int, error) {
	var count int64
	now := time.Now()
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
	err := s.db.WithContext(ctx).Model(&entity.Booking{}).
		Where("pitch_id = ? AND source = ? AND status <> ? AND created_at >= ?",
			pitchID, "turfinn", entity.BookingCancelled, monthStart).
		Count(&count).Error
	return int(count), err
}

// IsTrialActive is a small helper for UI callers that need to render a
// "Trial: X days left" badge without re-implementing the time check.
func (s *PricingService) IsTrialActive(pitch *entity.Pitch) bool {
	return pitch != nil && pitch.TrialEndsAt != nil && time.Now().Before(*pitch.TrialEndsAt)
}

// IsPremiumActive returns true when the pitch's manager has a valid
// Premium ERP subscription. Drives the panel's premium gating.
func (s *PricingService) IsPremiumActive(pitch *entity.Pitch) bool {
	return pitch != nil && pitch.PremiumActiveUntil != nil && time.Now().Before(*pitch.PremiumActiveUntil)
}

// Config exposes the underlying AvivConfig for callers (DTOs, billing
// view) that need to display thresholds + sticker prices.
func (s *PricingService) Config() config.MatchConfig {
	return s.cfg
}
