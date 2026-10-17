package handler

import (
	"crypto/rand"
	"encoding/hex"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"github.com/turfinn/backend/internal/interfaces/dto"
	mw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	phonepkg "github.com/turfinn/backend/internal/pkg/phone"
	"github.com/turfinn/backend/internal/pkg/response"
	"golang.org/x/crypto/bcrypt"
)

type SuperAdminHandler struct {
	repo     domain.SuperAdminRepository
	userRepo domain.UserRepository
}

func NewSuperAdminHandler(r domain.SuperAdminRepository, userRepo domain.UserRepository) *SuperAdminHandler {
	return &SuperAdminHandler{repo: r, userRepo: userRepo}
}

// ── Business Intelligence ───────────────────────────────────────────────────

func (h *SuperAdminHandler) GetNorthStar(c echo.Context) error {
	m, err := h.repo.GetNorthStarMetrics(c.Request().Context())
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, dto.NorthStarResponse{
		GMV: m.GMV, GMVMTD: m.GMVMTD, NetRevenue: m.NetRevenue,
		NetRevenueMTD: m.NetRevenueMTD, ActiveTurfs: m.ActiveTurfs,
		ActivePlayers: m.ActivePlayers, TotalBookings: m.TotalBookings,
		BookingsMTD: m.BookingsMTD,
	})
}

func (h *SuperAdminHandler) GetCohortRetention(c echo.Context) error {
	months, _ := strconv.Atoi(c.QueryParam("months"))
	if months < 1 {
		months = 6
	}
	rows, err := h.repo.GetCohortRetention(c.Request().Context(), months)
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.CohortRowResponse, len(rows))
	for i, r := range rows {
		var rate float64
		if r.CohortSize > 0 {
			rate = float64(r.Retained) / float64(r.CohortSize) * 100
		}
		resp[i] = dto.CohortRowResponse{
			CohortMonth: r.CohortMonth, MonthOffset: r.MonthOffset,
			Retained: r.Retained, CohortSize: r.CohortSize, Rate: rate,
		}
	}
	return response.OK(c, resp)
}

func (h *SuperAdminHandler) GetFunnel(c echo.Context) error {
	from, to, err := parseDateRange(c)
	if err != nil {
		return response.BadRequest(c, "invalid date range, use YYYY-MM-DD")
	}
	steps, err := h.repo.GetFunnel(c.Request().Context(), from, to)
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.FunnelStepResponse, len(steps))
	var prev int64
	for i, s := range steps {
		var dropOff float64
		if i > 0 && prev > 0 {
			dropOff = (1 - float64(s.Count)/float64(prev)) * 100
		}
		prev = s.Count
		resp[i] = dto.FunnelStepResponse{
			EventType: s.EventType, Count: s.Count, DropOff: dropOff,
		}
	}
	return response.OK(c, resp)
}

func (h *SuperAdminHandler) GetRevenueTimeSeries(c echo.Context) error {
	period := c.QueryParam("period")
	if period == "" {
		period = "day"
	}
	from, to, err := parseDateRange(c)
	if err != nil {
		return response.BadRequest(c, "invalid date range, use YYYY-MM-DD")
	}
	points, err := h.repo.GetRevenueTimeSeries(c.Request().Context(), period, from, to)
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.RevenuePointResponse, len(points))
	for i, p := range points {
		resp[i] = dto.RevenuePointResponse{Date: p.Date, Revenue: p.Revenue}
	}
	return response.OK(c, resp)
}

// ── Booking Events (analytics ingestion) ────────────────────────────────────

func (h *SuperAdminHandler) IngestBookingEvent(c echo.Context) error {
	var req dto.BookingEventRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)
	e := &entity.BookingEvent{
		UserID: &callerID, SessionID: req.SessionID,
		EventType: req.EventType, Metadata: req.Metadata,
	}
	if err := h.repo.CreateBookingEvent(c.Request().Context(), e); err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, map[string]string{"id": e.ID.String()})
}

// ── Marketing Spend ─────────────────────────────────────────────────────────

func (h *SuperAdminHandler) UpsertMarketingSpend(c echo.Context) error {
	var req dto.MarketingSpendRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)
	month, _ := time.Parse("2006-01-02", req.Month)
	s := &entity.MarketingSpend{
		Month: month, Amount: req.Amount, Notes: req.Notes, EnteredBy: callerID,
	}
	if err := h.repo.UpsertMarketingSpend(c.Request().Context(), s); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"status": "saved"})
}

// ── Audit Log ───────────────────────────────────────────────────────────────

func (h *SuperAdminHandler) ListAuditLog(c echo.Context) error {
	page, limit := paginationDefaults(c)
	var actorID *uuid.UUID
	if raw := c.QueryParam("actor_id"); raw != "" {
		if id, err := uuid.Parse(raw); err == nil {
			actorID = &id
		}
	}
	entityType := c.QueryParam("entity_type")
	action := c.QueryParam("action")
	var from, to *time.Time
	if raw := c.QueryParam("from"); raw != "" {
		if t, err := time.Parse("2006-01-02", raw); err == nil {
			from = &t
		}
	}
	if raw := c.QueryParam("to"); raw != "" {
		if t, err := time.Parse("2006-01-02", raw); err == nil {
			to = &t
		}
	}
	items, total, err := h.repo.ListAuditLog(c.Request().Context(), actorID, entityType, action, from, to, page, limit)
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.AuditLogResponse, len(items))
	for i, a := range items {
		resp[i] = dto.AuditLogResponse{
			ID: a.ID, ActorID: a.ActorID.String(), ActorRole: a.ActorRole,
			Action: a.Action, EntityType: a.EntityType, EntityID: a.EntityID,
			OldValue: a.OldValue, NewValue: a.NewValue, IPAddress: a.IPAddress,
			CreatedAt: a.CreatedAt.Format("2006-01-02T15:04:05Z"),
		}
	}
	return response.OKPaginated(c, resp, response.Meta{Page: page, Limit: limit, Total: total})
}

// ── Ledger & Finance ────────────────────────────────────────────────────────

func (h *SuperAdminHandler) ListLedger(c echo.Context) error {
	page, limit := paginationDefaults(c)
	entryType := c.QueryParam("entry_type")
	var from, to *time.Time
	if raw := c.QueryParam("from"); raw != "" {
		if t, err := time.Parse("2006-01-02", raw); err == nil {
			from = &t
		}
	}
	if raw := c.QueryParam("to"); raw != "" {
		if t, err := time.Parse("2006-01-02", raw); err == nil {
			to = &t
		}
	}
	items, total, err := h.repo.ListLedgerEntries(c.Request().Context(), entryType, from, to, page, limit)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OKPaginated(c, items, response.Meta{Page: page, Limit: limit, Total: total})
}

func (h *SuperAdminHandler) GetTrialBalance(c echo.Context) error {
	bal, err := h.repo.GetTrialBalance(c.Request().Context())
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, bal)
}

func (h *SuperAdminHandler) GetIncomeStatement(c echo.Context) error {
	from, to, err := parseDateRange(c)
	if err != nil {
		return response.BadRequest(c, "invalid date range, use YYYY-MM-DD")
	}
	revenue, refunds, promoExpense, err := h.repo.GetIncomeStatement(c.Request().Context(), from, to)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, dto.IncomeStatementResponse{
		Revenue: revenue, Refunds: refunds, PromoExpense: promoExpense,
		Net: revenue - refunds - promoExpense,
	})
}

func (h *SuperAdminHandler) GetVATReport(c echo.Context) error {
	year, _ := strconv.Atoi(c.QueryParam("year"))
	if year < 2020 {
		year = time.Now().Year()
	}
	rows, err := h.repo.GetVATReport(c.Request().Context(), year)
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.VATRowResponse, len(rows))
	for i, r := range rows {
		resp[i] = dto.VATRowResponse{
			Month:            strVal(r, "month"),
			TotalBookings:    int64Val(r, "total_bookings"),
			TotalGMV:         floatVal(r, "total_gmv"),
			TotalPlatformFee: floatVal(r, "total_platform_fee"),
			VATAmount:        floatVal(r, "vat_amount"),
		}
	}
	return response.OK(c, resp)
}

// ── Fraud Flags ─────────────────────────────────────────────────────────────

func (h *SuperAdminHandler) ListFraudFlags(c echo.Context) error {
	page, limit := paginationDefaults(c)
	status := c.QueryParam("status")
	items, total, err := h.repo.ListFraudFlags(c.Request().Context(), status, page, limit)
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.FraudFlagResponse, len(items))
	for i, f := range items {
		resp[i] = dto.FraudFlagResponse{
			ID: f.ID.String(), EntityType: f.EntityType, EntityID: f.EntityID.String(),
			FlagType: f.FlagType, Details: f.Details, Status: f.Status,
			CreatedAt: f.CreatedAt.Format("2006-01-02T15:04:05Z"),
		}
	}
	return response.OKPaginated(c, resp, response.Meta{Page: page, Limit: limit, Total: total})
}

func (h *SuperAdminHandler) UpdateFraudFlag(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	var body struct {
		Status string `json:"status" validate:"required,oneof=active dismissed escalated"`
	}
	if err := c.Bind(&body); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&body); err != nil {
		return response.BadRequest(c, err.Error())
	}
	callerID := c.Get(mw.UserIDKey).(uuid.UUID)
	f := &entity.FraudFlag{ID: id, Status: body.Status, ReviewedBy: callerID}
	if err := h.repo.UpdateFraudFlag(c.Request().Context(), f); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"id": id.String(), "status": body.Status})
}

// ── Rate Limits ─────────────────────────────────────────────────────────────

func (h *SuperAdminHandler) ListRateLimits(c echo.Context) error {
	items, err := h.repo.ListRateLimits(c.Request().Context())
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.RateLimitResponse, len(items))
	for i, r := range items {
		resp[i] = dto.RateLimitResponse{
			EndpointGroup: r.EndpointGroup, RequestsPerMinute: r.RequestsPerMinute,
			Burst: r.Burst, IsEnabled: r.IsEnabled,
		}
	}
	return response.OK(c, resp)
}

func (h *SuperAdminHandler) UpdateRateLimit(c echo.Context) error {
	group := c.Param("group")
	var req dto.UpdateRateLimitRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	if err := h.repo.UpdateRateLimit(c.Request().Context(), group, req.RequestsPerMinute, req.Burst); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"group": group, "status": "updated"})
}

// ── API Keys ────────────────────────────────────────────────────────────────

func (h *SuperAdminHandler) ListAPIKeys(c echo.Context) error {
	page, limit := paginationDefaults(c)
	items, total, err := h.repo.ListAPIKeys(c.Request().Context(), page, limit)
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.APIKeyResponse, len(items))
	for i, k := range items {
		r := dto.APIKeyResponse{
			ID: k.ID.String(), Name: k.Name, OwnerOrg: k.OwnerOrg,
			Scopes: k.Scopes, IsActive: k.IsActive,
			CreatedAt: k.CreatedAt.Format("2006-01-02T15:04:05Z"),
		}
		if k.ExpiresAt != nil {
			r.ExpiresAt = k.ExpiresAt.Format("2006-01-02T15:04:05Z")
		}
		resp[i] = r
	}
	return response.OKPaginated(c, resp, response.Meta{Page: page, Limit: limit, Total: total})
}

func (h *SuperAdminHandler) CreateAPIKey(c echo.Context) error {
	var req dto.CreateAPIKeyRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	// Generate a random 32-byte key
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return response.InternalError(c)
	}
	plainKey := "tfk_" + hex.EncodeToString(raw)
	hash, err := bcrypt.GenerateFromPassword([]byte(plainKey), bcrypt.DefaultCost)
	if err != nil {
		return response.InternalError(c)
	}
	k := &entity.APIKey{
		Name: req.Name, KeyHash: string(hash), OwnerOrg: req.OwnerOrg,
		Scopes: req.Scopes, IsActive: true,
	}
	if err := h.repo.CreateAPIKey(c.Request().Context(), k); err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, dto.APIKeyCreatedResponse{ID: k.ID.String(), Key: plainKey})
}

func (h *SuperAdminHandler) RevokeAPIKey(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	if err := h.repo.DeleteAPIKey(c.Request().Context(), id); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"status": "revoked"})
}

// ── Zones ───────────────────────────────────────────────────────────────────

func (h *SuperAdminHandler) ListZones(c echo.Context) error {
	items, err := h.repo.ListZones(c.Request().Context())
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.ZoneResponse, len(items))
	for i, z := range items {
		r := dto.ZoneResponse{
			ID: z.ID.String(), Name: z.Name, Slug: z.Slug, City: z.City,
			Lat: z.Lat, Lng: z.Lng, RadiusKM: z.RadiusKM, IsActive: z.IsActive,
		}
		if z.ZoneManager != nil {
			r.ZoneManagerID = z.ZoneManagerID.String()
			r.ZoneManagerName = z.ZoneManager.Name
		}
		resp[i] = r
	}
	return response.OK(c, resp)
}

func (h *SuperAdminHandler) CreateZone(c echo.Context) error {
	var req dto.CreateZoneRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	z := &entity.Zone{
		Name: req.Name, Slug: req.Slug, City: req.City,
		Lat: req.Lat, Lng: req.Lng, RadiusKM: req.RadiusKM, IsActive: true,
	}
	if err := h.repo.CreateZone(c.Request().Context(), z); err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, map[string]string{"id": z.ID.String()})
}

// ── Organizations ───────────────────────────────────────────────────────────

func (h *SuperAdminHandler) ListOrganizations(c echo.Context) error {
	page, limit := paginationDefaults(c)
	items, total, err := h.repo.ListOrganizations(c.Request().Context(), page, limit)
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.OrgResponse, len(items))
	for i, o := range items {
		resp[i] = dto.OrgResponse{
			ID: o.ID.String(), Name: o.Name, ContactName: o.ContactName,
			ContactEmail: o.ContactEmail, Phone: o.Phone,
			CreditLimitPaisa: o.CreditLimitPaisa, WalletBalancePaisa: o.WalletBalancePaisa,
			IsActive: o.IsActive,
		}
	}
	return response.OKPaginated(c, resp, response.Meta{Page: page, Limit: limit, Total: total})
}

func (h *SuperAdminHandler) CreateOrganization(c echo.Context) error {
	var req dto.CreateOrgRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	o := &entity.Organization{
		Name: req.Name, ContactName: req.ContactName, ContactEmail: req.ContactEmail,
		Phone: req.Phone, BillingAddress: req.BillingAddress,
		CreditLimitPaisa: req.CreditLimitPaisa, IsActive: true,
	}
	if err := h.repo.CreateOrganization(c.Request().Context(), o); err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, map[string]string{"id": o.ID.String()})
}

func (h *SuperAdminHandler) AddOrgCredit(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid id")
	}
	var req dto.AddCreditRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	org, err := h.repo.GetOrganization(c.Request().Context(), id)
	if err != nil {
		return response.NotFound(c, "organization not found")
	}
	org.WalletBalancePaisa += req.AmountPaisa
	if err := h.repo.UpdateOrganization(c.Request().Context(), org); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]any{"id": id.String(), "wallet_balance_paisa": org.WalletBalancePaisa})
}

// ── Resellers ───────────────────────────────────────────────────────────────

func (h *SuperAdminHandler) ListResellers(c echo.Context) error {
	page, limit := paginationDefaults(c)
	items, total, err := h.repo.ListResellers(c.Request().Context(), page, limit)
	if err != nil {
		return response.InternalError(c)
	}
	resp := make([]dto.ResellerResponse, len(items))
	for i, r := range items {
		resp[i] = dto.ResellerResponse{
			ID: r.ID.String(), UserID: r.UserID.String(), Name: r.Name,
			CommissionPercent: r.CommissionPercent, TotalEarnedPaisa: r.TotalEarnedPaisa,
			TotalPaidPaisa: r.TotalPaidPaisa, ActivePitchesCount: r.ActivePitchesCount,
			IsActive: r.IsActive,
		}
	}
	return response.OKPaginated(c, resp, response.Meta{Page: page, Limit: limit, Total: total})
}

func (h *SuperAdminHandler) CreateReseller(c echo.Context) error {
	var req dto.CreateResellerRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	userID, _ := uuid.Parse(req.UserID)
	r := &entity.Reseller{
		UserID: userID, Name: req.Name, CommissionPercent: req.CommissionPercent,
		IsActive: true,
	}
	if err := h.repo.CreateReseller(c.Request().Context(), r); err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, map[string]string{"id": r.ID.String()})
}

// ── Helpers ─────────────────────────────────────────────────────────────────

func parseDateRange(c echo.Context) (time.Time, time.Time, error) {
	fromStr := c.QueryParam("from")
	toStr := c.QueryParam("to")
	if fromStr == "" {
		fromStr = time.Now().AddDate(0, -1, 0).Format("2006-01-02")
	}
	if toStr == "" {
		toStr = time.Now().Format("2006-01-02")
	}
	from, err := time.Parse("2006-01-02", fromStr)
	if err != nil {
		return time.Time{}, time.Time{}, err
	}
	to, err := time.Parse("2006-01-02", toStr)
	if err != nil {
		return time.Time{}, time.Time{}, err
	}
	return from, to, nil
}

func strVal(m map[string]any, key string) string {
	if v, ok := m[key]; ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return ""
}

func int64Val(m map[string]any, key string) int64 {
	if v, ok := m[key]; ok {
		switch n := v.(type) {
		case int64:
			return n
		case float64:
			return int64(n)
		}
	}
	return 0
}

func floatVal(m map[string]any, key string) float64 {
	if v, ok := m[key]; ok {
		if f, ok := v.(float64); ok {
			return f
		}
	}
	return 0
}

// ── Turf Admin (manager) registration ──────────────────────────────────────
// The flow: super-admin creates a User row with role=manager via the panel.
// The manager then opens :3002/login on their own, types their phone, gets
// an OTP, and verifies — same auth path as everyone else. No password, no
// invite SMS from us.

type createManagerRequest struct {
	Phone string `json:"phone" validate:"required"`
	Name  string `json:"name"  validate:"required,min=1,max=100"`
}

// POST /super-admin/managers
//
// If a user already exists with the same phone, we promote them (set
// role=manager) rather than reject — covers the "this player is also a
// turf owner" case. Existing managers are returned unchanged.
func (h *SuperAdminHandler) CreateManager(c echo.Context) error {
	var req createManagerRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	phone := normalizePhone(req.Phone)
	if phone == "" {
		return response.BadRequest(c, "invalid phone")
	}

	ctx := c.Request().Context()
	existing, _ := h.userRepo.FindByPhone(ctx, phone)
	if existing != nil {
		if existing.Role == entity.RoleManager || existing.Role == entity.RoleAdmin || existing.Role == entity.RoleSuperAdmin {
			return response.OK(c, managerResponse(existing))
		}
		// Promote a player to manager.
		existing.Role = entity.RoleManager
		if existing.Name == "" {
			existing.Name = req.Name
		}
		if err := h.userRepo.Update(ctx, existing); err != nil {
			return response.InternalError(c)
		}
		return response.OK(c, managerResponse(existing))
	}

	user := &entity.User{
		ID:    uuid.New(),
		Phone: &phone,
		Name:  req.Name,
		Role:  entity.RoleManager,
	}
	if err := h.userRepo.Create(ctx, user); err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, managerResponse(user))
}

// GET /super-admin/managers
//
// Lists every user with role=manager. Page-size capped at 100; managers
// won't realistically exceed that without paginating, but we keep it
// honest.
func (h *SuperAdminHandler) ListManagers(c echo.Context) error {
	ctx := c.Request().Context()
	managers, err := h.repo.ListUsersByRole(ctx, string(entity.RoleManager))
	if err != nil {
		return response.InternalError(c)
	}
	out := make([]map[string]any, 0, len(managers))
	for _, m := range managers {
		out = append(out, managerResponse(&m))
	}
	return response.OK(c, out)
}

func managerResponse(u *entity.User) map[string]any {
	phone := ""
	if u.Phone != nil {
		phone = *u.Phone
	}
	return map[string]any{
		"id":         u.ID.String(),
		"name":       u.Name,
		"phone":      phone,
		"role":       string(u.Role),
		"created_at": u.CreatedAt.Format("2006-01-02T15:04:05Z"),
	}
}

// normalizePhone is now a thin wrapper around the shared
// internal/pkg/phone package which uses libphonenumber for proper
// validation. Kept as a small helper here so existing call sites in
// this file don't have to change their imports.
func normalizePhone(raw string) string {
	return phonepkg.Normalize(raw)
}
