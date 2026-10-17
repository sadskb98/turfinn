// Package handler — pricing_handler.go exposes super-admin endpoints for
// the Aviv pricing model: per-pitch fee overrides, trial extension,
// premium grant/revoke, and add-on toggles.
//
// Mounted under /super-admin/pitches/:id/* — gated to super_admin in
// router.go (the existing /super-admin group already requires super_admin).
package handler

import (
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"

	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/pkg/response"
)

type PricingHandler struct {
	db *gorm.DB
}

func NewPricingHandler(db *gorm.DB) *PricingHandler {
	return &PricingHandler{db: db}
}

// PUT /super-admin/pitches/:id/pricing
//
// Body — all optional, only set fields are applied:
//
//	{
//	  "plan": "marketplace" | "erp_only",
//	  "marketplace_fee_bps_override": int (nullable to clear),
//	  "walkin_fee_bps_override": int (nullable to clear),
//	  "trial_extension_days": int (positive — extends trial)
//	}
//
// Use null/missing to leave a field unchanged. Use 0 (not null) to set
// override = 0% explicitly.
func (h *PricingHandler) UpdatePitchPricing(c echo.Context) error {
	pitchID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid pitch id")
	}
	// Use a raw map so we can distinguish absent vs null vs value.
	var body map[string]any
	if err := c.Bind(&body); err != nil {
		return response.BadRequest(c, "invalid request body")
	}

	updates := map[string]any{}
	if v, ok := body["plan"]; ok {
		s, ok := v.(string)
		if !ok || (s != entity.PitchPlanMarketplace && s != entity.PitchPlanERPOnly) {
			return response.BadRequest(c, "invalid plan")
		}
		updates["plan"] = s
	}
	if v, ok := body["marketplace_fee_bps_override"]; ok {
		updates["marketplace_fee_bps_override"] = parseBpsOverride(v)
	}
	if v, ok := body["walkin_fee_bps_override"]; ok {
		updates["walkin_fee_bps_override"] = parseBpsOverride(v)
	}
	if v, ok := body["trial_extension_days"]; ok {
		days := 0
		switch d := v.(type) {
		case float64:
			days = int(d)
		case int:
			days = d
		}
		if days > 0 {
			// Extend from now (or from existing trial end if it's still
			// in the future — whichever is later).
			var pitch entity.Pitch
			if err := h.db.WithContext(c.Request().Context()).
				First(&pitch, "id = ?", pitchID).Error; err == nil {
				base := time.Now()
				if pitch.TrialEndsAt != nil && pitch.TrialEndsAt.After(base) {
					base = *pitch.TrialEndsAt
				}
				newEnd := base.Add(time.Duration(days) * 24 * time.Hour)
				updates["trial_ends_at"] = newEnd
			}
		}
	}

	if len(updates) == 0 {
		return response.BadRequest(c, "no fields to update")
	}
	updates["updated_at"] = time.Now()

	if err := h.db.WithContext(c.Request().Context()).
		Model(&entity.Pitch{}).
		Where("id = ?", pitchID).
		Updates(updates).Error; err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]any{"id": pitchID.String(), "updated": updates})
}

// PUT /super-admin/pitches/:id/premium
// Body: { "until": "2026-12-31T00:00:00Z" }  // nil to revoke
func (h *PricingHandler) SetPremium(c echo.Context) error {
	pitchID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid pitch id")
	}
	var req struct {
		Until *string `json:"until"`
	}
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid body")
	}
	updates := map[string]any{"updated_at": time.Now()}
	if req.Until == nil || *req.Until == "" {
		updates["premium_active_until"] = gorm.Expr("NULL")
	} else {
		t, err := time.Parse(time.RFC3339, *req.Until)
		if err != nil {
			return response.BadRequest(c, "invalid until: expected RFC3339")
		}
		updates["premium_active_until"] = t
	}
	if err := h.db.WithContext(c.Request().Context()).
		Model(&entity.Pitch{}).
		Where("id = ?", pitchID).
		Updates(updates).Error; err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"id": pitchID.String()})
}

// POST /super-admin/pitches/:id/addons/:kind/enable
// POST /super-admin/pitches/:id/addons/:kind/disable
//
// kind: "marketing_boost" | "match_guarantee_insurance" | "bulk_sms"
// For now this only flips the boolean for marketing_boost and writes an
// addon_subscriptions row for everything else; the subscription billing
// itself is reconciled monthly.
func (h *PricingHandler) ToggleAddon(c echo.Context) error {
	pitchID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid pitch id")
	}
	kind := c.Param("kind")
	action := c.Param("action") // "enable" or "disable" — set via route binding
	if action != "enable" && action != "disable" {
		return response.BadRequest(c, "action must be enable or disable")
	}
	enable := action == "enable"

	// marketing_boost has a quick boolean on pitches for the player-app
	// ranking algorithm; insurance + bulk_sms only need the subscription
	// row for billing. Keep both consistent: write a subscription row in
	// every case and also flip the boolean for marketing_boost.
	now := time.Now()
	tx := h.db.WithContext(c.Request().Context()).Begin()
	if kind == "marketing_boost" {
		if err := tx.Model(&entity.Pitch{}).Where("id = ?", pitchID).
			Updates(map[string]any{"marketing_boost_active": enable, "updated_at": now}).Error; err != nil {
			tx.Rollback()
			return response.InternalError(c)
		}
	}
	if enable {
		// Close any existing active subscription for idempotency, then open new.
		_ = tx.Exec(`UPDATE addon_subscriptions SET disabled_at = ?
		             WHERE pitch_id = ? AND addon_kind = ? AND disabled_at IS NULL`,
			now, pitchID, kind).Error
		monthly := monthlyPaisaForAddon(kind)
		_ = tx.Exec(`INSERT INTO addon_subscriptions (pitch_id, addon_kind, enabled_at, monthly_paisa)
		             VALUES (?, ?, ?, ?)`, pitchID, kind, now, monthly).Error
	} else {
		_ = tx.Exec(`UPDATE addon_subscriptions SET disabled_at = ?
		             WHERE pitch_id = ? AND addon_kind = ? AND disabled_at IS NULL`,
			now, pitchID, kind).Error
	}
	if err := tx.Commit().Error; err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]any{
		"pitch_id": pitchID.String(),
		"kind":     kind,
		"enabled":  enable,
	})
}

// parseBpsOverride accepts a number or null — returns *int for GORM.
// nil here triggers "set column = NULL" in the resulting Updates map.
func parseBpsOverride(v any) any {
	if v == nil {
		return gorm.Expr("NULL")
	}
	switch n := v.(type) {
	case float64:
		i := int(n)
		return &i
	case int:
		return &n
	default:
		return gorm.Expr("NULL")
	}
}

// monthlyPaisaForAddon maps add-on kind → sticker price in paisa. Should
// eventually live in MatchConfig but kept inline here while we settle on
// the add-on catalogue.
func monthlyPaisaForAddon(kind string) int64 {
	switch kind {
	case "marketing_boost":
		return 50000 // 500 BDT
	case "match_guarantee_insurance":
		// Variable (1.5% of revenue) — store 0 here; computed at month-end.
		return 0
	case "bulk_sms":
		// Pay-per-use — no monthly fee.
		return 0
	default:
		return 0
	}
}
