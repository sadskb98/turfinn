# Handoff: Manager Enhanced Analytics Implementation

**Date:** 2026-04-11
**Plan file:** `docs/superpowers/plans/2026-04-11-manager-enhanced-analytics.md`
**Branch:** `main` (all commits so far are on main)

---

## What's DONE (committed)

| Task | Commit | Files Created |
|------|--------|---------------|
| B1: Migration | `5e94cf8` | `backend/migrations/015_manager_promo_codes.sql` |
| B2: DTOs | `598793a` | `backend/internal/interfaces/dto/manager_enhanced_dto.go` |
| B3: Service + Tests | `aca6734` | `backend/internal/application/service/manager_analytics_service.go`, `manager_analytics_service_test.go` |

Tests pass: `cd backend && go test ./internal/application/service/ -run TestFillHeatmapGrid -v` and `TestTopAndBottom`

---

## What's LEFT (5 tasks, must be done in order)

### Task B4: Handler Methods + Router Wiring (BACKEND)

**This is the next task to implement.** Full code is in the plan file Task B4.

**What to do:**

1. **Add `OwnerID` to PromoCode entity** in `backend/internal/domain/entity/marketing.go`:
   ```go
   OwnerID *uuid.UUID `json:"owner_id,omitempty" gorm:"type:uuid;index"`
   ```

2. **Update `ManagerHandler` struct** in `backend/internal/interfaces/http/handler/manager_handler.go`:
   - Add `enhanced *service.ManagerAnalyticsService` field
   - Update `NewManagerHandler` to accept both services
   - Add 5 handler methods: `GetHeatmap`, `GetPeakHours`, `GetCustomerInsights`, `GetDailyLedger`, `GetPitchPnL`

3. **Create `manager_campaigns_handler.go`** in `backend/internal/interfaces/http/handler/`:
   - `ManagerCampaignsHandler` struct with `db *gorm.DB`
   - Methods: `ListPromos`, `CreatePromo`, `DeactivatePromo`

4. **Update `router.go`** — add 8 new routes to the manager group (after line ~122):
   ```
   manager.GET("/analytics/heatmap", managerH.GetHeatmap)
   manager.GET("/analytics/peak-hours", managerH.GetPeakHours)
   manager.GET("/analytics/customers", managerH.GetCustomerInsights)
   manager.GET("/financials/ledger", managerH.GetDailyLedger)
   manager.GET("/financials/pitch-pnl", managerH.GetPitchPnL)
   manager.GET("/promos", campaignsH.ListPromos)
   manager.POST("/promos", campaignsH.CreatePromo)
   manager.PUT("/promos/:id/deactivate", campaignsH.DeactivatePromo)
   ```
   Also add `campaignsH *handler.ManagerCampaignsHandler` param to `NewRouter`.

5. **Update `main.go`** wiring (~line 91, 104, 116-119):
   ```go
   managerAnalyticsSvc := service.NewManagerAnalyticsService(db)
   managerH := handler.NewManagerHandler(analyticsSvc, managerAnalyticsSvc)
   campaignsH := handler.NewManagerCampaignsHandler(db)
   // Add campaignsH to NewRouter call
   ```

6. **Verify:** `cd backend && go build ./...`

---

### Task F1: Remote Source — New API Methods (FLUTTER)

**File:** `lib/data/sources/remote/manage_remote_source.dart`

Add 8 new methods calling the endpoints from B4:
- `getManagerHeatmap(period)` → GET `/manager/analytics/heatmap?period=`
- `getManagerPeakHours(period)` → GET `/manager/analytics/peak-hours?period=`
- `getManagerCustomerInsights(period)` → GET `/manager/analytics/customers?period=`
- `getManagerDailyLedger(from, to)` → GET `/manager/financials/ledger?from=&to=`
- `getManagerPitchPnL(period)` → GET `/manager/financials/pitch-pnl?period=`
- `listManagerPromos()` → GET `/manager/promos`
- `createManagerPromo(body)` → POST `/manager/promos`
- `deactivateManagerPromo(id)` → PUT `/manager/promos/$id/deactivate`

---

### Task F2: Enhanced Analytics View (FLUTTER)

**File:** `lib/presentation/screens/manage/manage_panel_screen.dart`

- Rename "My Analytics" sidebar item → "Analytics Pro"
- Replace existing analytics body with `_AnalyticsProView` widget
- 3 tabs: Heatmap (7x16 colored grid), Peak Hours (top 5 / bottom 5 table), Customer Insights (table with repeat rate)
- Add `_TabButton` helper widget
- Full widget code is in plan file Task F2

---

### Task F3: Enhanced Financials View (FLUTTER)

**File:** `lib/presentation/screens/manage/manage_panel_screen.dart`

- Rename "My Financials" sidebar item → "Financials Pro"
- Replace existing financials body with `_FinancialsProView` widget
- 3 tabs: Overview (existing), Daily Ledger (date-based table), Pitch P&L (per-pitch breakdown)
- Full widget code is in plan file Task F3

---

### Task F4: Campaigns View (FLUTTER)

**File:** `lib/presentation/screens/manage/manage_panel_screen.dart`

- Add "Campaigns" as 8th sidebar item
- Add `_CampaignsView` widget to `IndexedStack`
- Create promo code dialog with fields: code, discount type, value, valid dates, max uses
- List existing promos with deactivate button
- Full widget code is in plan file Task F4

---

## How to Execute

```bash
# Read the full plan with complete code for each task:
cat docs/superpowers/plans/2026-04-11-manager-enhanced-analytics.md

# After implementing B4, verify backend builds:
cd backend && go build ./...

# After implementing F1-F4, verify Flutter:
flutter analyze
dart run build_runner build --delete-conflicting-outputs

# Run backend tests:
cd backend && go test ./...
```

## Important Notes

- All complete implementation code (copy-paste ready) is in the plan file
- The plan uses existing `PanelScaffold`, `StatCard`, `DataTableCard` widgets
- Manager routes are gated by `authmw.RequireManager()` middleware
- PromoCode entity already exists in `marketing.go` — just add the `OwnerID` field
- There are uncommitted changes in the working tree (unrelated to this feature) — don't touch those files
