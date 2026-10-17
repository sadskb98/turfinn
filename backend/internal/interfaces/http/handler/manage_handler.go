package handler

import (
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"gorm.io/gorm"

	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"github.com/turfinn/backend/internal/interfaces/dto"
	mw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type ManageHandler struct {
	pitchRepo   domain.PitchRepository
	bookingRepo domain.BookingRepository
	verifyRepo  domain.VerificationRepository
	userRepo    domain.UserRepository
	db          *gorm.DB
}

func NewManageHandler(
	pr domain.PitchRepository,
	br domain.BookingRepository,
	vr domain.VerificationRepository,
	ur domain.UserRepository,
	db *gorm.DB,
) *ManageHandler {
	return &ManageHandler{
		pitchRepo:   pr,
		bookingRepo: br,
		verifyRepo:  vr,
		userRepo:    ur,
		db:          db,
	}
}

func (h *ManageHandler) Dashboard(c echo.Context) error {
	ctx := c.Request().Context()
	ownerID := c.Get(mw.UserIDKey).(uuid.UUID)

	pitches, err := h.pitchRepo.ListByOwner(ctx, ownerID)
	if err != nil {
		return response.InternalError(c)
	}

	pitchIDs := make([]uuid.UUID, len(pitches))
	for i, p := range pitches {
		pitchIDs[i] = p.ID
	}

	var totalBookings int64
	var todayBookings int64
	var upcomingBookings int64
	var revenue float64
	var cashToCollectPaisa int64

	if len(pitchIDs) > 0 {
		revenue, _ = h.bookingRepo.Revenue(ctx, pitchIDs)
		bookings, total, _ := h.bookingRepo.ListByPitches(ctx, pitchIDs, 1, 10000)
		totalBookings = total

		now := time.Now()
		todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
		todayEnd := todayStart.Add(24 * time.Hour)

		var cashToCollectPaisaLocal int64
		for _, b := range bookings {
			if b.StartsAt.After(todayStart) && b.StartsAt.Before(todayEnd) {
				todayBookings++
			}
			if b.StartsAt.After(now) && b.Status != entity.BookingCancelled {
				upcomingBookings++
			}
			// Outstanding cash = cash_due - cash_collected on confirmed
			// upcoming bookings. Past bookings are settled or written off.
			if b.Status == entity.BookingConfirmed && b.StartsAt.After(now.Add(-24*time.Hour)) {
				outstanding := b.CashDuePaisa - b.CashCollectedPaisa
				if outstanding > 0 {
					cashToCollectPaisaLocal += outstanding
				}
			}
		}
		cashToCollectPaisa = cashToCollectPaisaLocal
	}
	_ = cashToCollectPaisa

	return response.OK(c, dto.ManagerDashboardStats{
		TotalPitches:     len(pitches),
		TotalBookings:    totalBookings,
		TotalRevenue:     revenue,
		TodayBookings:    todayBookings,
		UpcomingBookings: upcomingBookings,
		CashToCollectBDT: float64(cashToCollectPaisa) / 100.0,
	})
}

func (h *ManageHandler) ListMyPitches(c echo.Context) error {
	ownerID := c.Get(mw.UserIDKey).(uuid.UUID)

	pitches, err := h.pitchRepo.ListByOwner(c.Request().Context(), ownerID)
	if err != nil {
		return response.InternalError(c)
	}

	items := make([]dto.AdminPitchResponse, len(pitches))
	for i, p := range pitches {
		items[i] = dto.AdminPitchResponse{
			ID:           p.ID.String(),
			Name:         p.Name,
			Address:      p.Address,
			City:         p.City,
			PricePerHour: p.PricePerHour,
			Surface:      p.Surface,
			Capacity:     p.Capacity,
			OwnerID:      p.OwnerID.String(),
			IsActive:     p.IsActive,
			CreatedAt:    p.CreatedAt.Format("2006-01-02T15:04:05Z"),
		}
	}
	return response.OK(c, items)
}

func (h *ManageHandler) CreatePitch(c echo.Context) error {
	ownerID := c.Get(mw.UserIDKey).(uuid.UUID)
	var req dto.UpsertPitchRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	pitch := entity.NewPitch(req.Name, req.Address, req.City, ownerID, req.PricePerHour)
	pitch.Description = req.Description
	pitch.Latitude = req.Latitude
	pitch.Longitude = req.Longitude
	pitch.Surface = req.Surface
	pitch.Capacity = req.Capacity
	pitch.ImageURLs = req.ImageURLs
	pitch.BannerURL = req.BannerURL
	pitch.ServiceRadiusKM = req.ServiceRadiusKM

	if err := h.pitchRepo.Create(c.Request().Context(), pitch); err != nil {
		return response.InternalError(c)
	}
	return response.Created(c, map[string]string{"id": pitch.ID.String()})
}

func (h *ManageHandler) UpdatePitch(c echo.Context) error {
	ownerID := c.Get(mw.UserIDKey).(uuid.UUID)
	pitchID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid pitch id")
	}

	pitch, err := h.pitchRepo.FindByID(c.Request().Context(), pitchID)
	if err != nil {
		return response.NotFound(c, "pitch not found")
	}
	if pitch.OwnerID != ownerID {
		return response.Forbidden(c)
	}

	var req dto.UpsertPitchRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	pitch.Name = req.Name
	pitch.Description = req.Description
	pitch.Address = req.Address
	pitch.City = req.City
	pitch.Latitude = req.Latitude
	pitch.Longitude = req.Longitude
	pitch.PricePerHour = req.PricePerHour
	pitch.Surface = req.Surface
	pitch.Capacity = req.Capacity
	pitch.ImageURLs = req.ImageURLs
	pitch.BannerURL = req.BannerURL
	pitch.ServiceRadiusKM = req.ServiceRadiusKM

	if err := h.pitchRepo.Update(c.Request().Context(), pitch); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"id": pitch.ID.String()})
}

func (h *ManageHandler) TogglePitch(c echo.Context) error {
	ownerID := c.Get(mw.UserIDKey).(uuid.UUID)
	pitchID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid pitch id")
	}

	pitch, err := h.pitchRepo.FindByID(c.Request().Context(), pitchID)
	if err != nil {
		return response.NotFound(c, "pitch not found")
	}
	if pitch.OwnerID != ownerID {
		return response.Forbidden(c)
	}

	pitch.IsActive = !pitch.IsActive
	if err := h.pitchRepo.Update(c.Request().Context(), pitch); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]any{"id": pitch.ID.String(), "is_active": pitch.IsActive})
}

func (h *ManageHandler) ListBookings(c echo.Context) error {
	ctx := c.Request().Context()
	ownerID := c.Get(mw.UserIDKey).(uuid.UUID)

	pitches, err := h.pitchRepo.ListByOwner(ctx, ownerID)
	if err != nil {
		return response.InternalError(c)
	}
	pitchIDs := make([]uuid.UUID, len(pitches))
	for i, p := range pitches {
		pitchIDs[i] = p.ID
	}
	if len(pitchIDs) == 0 {
		return response.OKPaginated(c, []dto.ManagerBookingResponse{}, response.Meta{})
	}

	page, _ := strconv.Atoi(c.QueryParam("page"))
	limit, _ := strconv.Atoi(c.QueryParam("limit"))
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = 20
	}

	bookings, total, err := h.bookingRepo.ListByPitches(ctx, pitchIDs, page, limit)
	if err != nil {
		return response.InternalError(c)
	}

	items := make([]dto.ManagerBookingResponse, len(bookings))
	for i, b := range bookings {
		items[i] = dto.ManagerBookingResponse{
			ID:           b.ID.String(),
			PitchName:    b.Pitch.Name,
			PitchID:      b.PitchID.String(),
			UserID:       b.UserID.String(),
			CustomerName: b.User.Name,
			StartsAt:     b.StartsAt,
			EndsAt:       b.EndsAt,
			TotalCost:    b.TotalCost,
			Status:       string(b.Status),
			Source:       b.Source,
			PaymentMethod: b.PaymentMethod,
			PaymentAmount: b.PaymentAmount,
			Notes:        b.Notes,
		}
	}
	return response.OKPaginated(c, items, response.Meta{Page: page, Limit: limit, Total: total})
}

func (h *ManageHandler) ConfirmBooking(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid booking id")
	}
	if err := h.bookingRepo.UpdateStatus(c.Request().Context(), id, entity.BookingConfirmed); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"id": id.String(), "status": "confirmed"})
}

func (h *ManageHandler) CancelBooking(c echo.Context) error {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid booking id")
	}
	if err := h.bookingRepo.UpdateStatus(c.Request().Context(), id, entity.BookingCancelled); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"id": id.String(), "status": "cancelled"})
}

// GetMyKYC handles GET /manage/kyc/me
func (h *ManageHandler) GetMyKYC(c echo.Context) error {
	userID, ok := c.Get(mw.UserIDKey).(uuid.UUID)
	if !ok {
		return response.Unauthorized(c)
	}
	k, err := h.verifyRepo.GetKYCByUser(c.Request().Context(), userID)
	if err != nil || k == nil {
		return response.OK(c, map[string]string{"status": "none"})
	}
	submittedAt := ""
	if k.SubmittedAt != nil {
		submittedAt = k.SubmittedAt.Format(time.RFC3339)
	}
	return response.OK(c, dto.KYCResponse{
		ID:               k.ID.String(),
		UserID:           k.UserID.String(),
		BusinessName:     k.BusinessName,
		NIDNumber:        k.NIDNumber,
		NIDPhotoFrontURL: k.NIDPhotoFrontURL,
		NIDPhotoBackURL:  k.NIDPhotoBackURL,
		SelfieURL:        k.SelfieURL,
		PayoutAccount:    k.PayoutAccount,
		Status:           k.Status,
		ReviewNote:       k.ReviewNote,
		SubmittedAt:      submittedAt,
	})
}

// SubmitKYC handles POST /manage/kyc
func (h *ManageHandler) SubmitKYC(c echo.Context) error {
	userID, ok := c.Get(mw.UserIDKey).(uuid.UUID)
	if !ok {
		return response.Unauthorized(c)
	}
	var req dto.SubmitKYCRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	now := time.Now()
	existing, err := h.verifyRepo.GetKYCByUser(c.Request().Context(), userID)

	if err != nil || existing == nil {
		k := &entity.ManagerKYC{
			UserID:           userID,
			BusinessName:     req.BusinessName,
			NIDNumber:        req.NIDNumber,
			NIDPhotoFrontURL: req.NIDPhotoFrontURL,
			NIDPhotoBackURL:  req.NIDPhotoBackURL,
			SelfieURL:        req.SelfieURL,
			PayoutAccount:    req.PayoutAccount,
			Status:           "submitted",
			SubmittedAt:      &now,
		}
		if err := h.verifyRepo.CreateKYC(c.Request().Context(), k); err != nil {
			return response.InternalError(c)
		}
		return response.OK(c, map[string]string{"status": "submitted"})
	}

	if existing.Status == "submitted" || existing.Status == "under_review" {
		return response.BadRequest(c, "application already under review")
	}

	existing.BusinessName = req.BusinessName
	existing.NIDNumber = req.NIDNumber
	existing.NIDPhotoFrontURL = req.NIDPhotoFrontURL
	existing.NIDPhotoBackURL = req.NIDPhotoBackURL
	existing.SelfieURL = req.SelfieURL
	existing.PayoutAccount = req.PayoutAccount
	existing.Status = "submitted"
	existing.SubmittedAt = &now
	existing.ReviewNote = ""

	if err := h.verifyRepo.UpdateKYC(c.Request().Context(), existing); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"status": "submitted"})
}

// GetMyBilling returns the billing summary for the caller's pitches:
// effective rate, trial status, premium status, monthly volume, total
// owed in settlement_account, current month's commission to date.
//
// Drives the manager panel's Billing sidebar entry and the premium-gate
// upgrade card.
func (h *ManageHandler) GetMyBilling(c echo.Context) error {
	ctx := c.Request().Context()
	ownerID := c.Get(mw.UserIDKey).(uuid.UUID)

	pitches, err := h.pitchRepo.ListByOwner(ctx, ownerID)
	if err != nil {
		return response.InternalError(c)
	}
	pricing := service.NewPricingService(h.db)

	type pitchBilling struct {
		ID                     string  `json:"id"`
		Name                   string  `json:"name"`
		Plan                   string  `json:"plan"`
		EffectiveCommissionBps int     `json:"effective_commission_bps"`
		TrialEndsAt            *string `json:"trial_ends_at,omitempty"`
		PremiumActiveUntil     *string `json:"premium_active_until,omitempty"`
		MonthlyVolume          int     `json:"monthly_volume"`
		MarketingBoostActive   bool    `json:"marketing_boost_active"`
	}

	out := make([]pitchBilling, 0, len(pitches))
	premiumActive := false
	for _, p := range pitches {
		volume, _ := pricing.MonthlyVolume(ctx, p.ID)
		var trialStr, premiumStr *string
		if p.TrialEndsAt != nil {
			s := p.TrialEndsAt.UTC().Format("2006-01-02T15:04:05Z")
			trialStr = &s
		}
		if p.PremiumActiveUntil != nil {
			s := p.PremiumActiveUntil.UTC().Format("2006-01-02T15:04:05Z")
			premiumStr = &s
			if pricing.IsPremiumActive(p) {
				premiumActive = true
			}
		}
		out = append(out, pitchBilling{
			ID:                     p.ID.String(),
			Name:                   p.Name,
			Plan:                   p.Plan,
			EffectiveCommissionBps: pricing.ResolveCommissionBps(ctx, p, "turfinn", volume),
			TrialEndsAt:            trialStr,
			PremiumActiveUntil:     premiumStr,
			MonthlyVolume:          volume,
			MarketingBoostActive:   p.MarketingBoostActive,
		})
	}

	// Outstanding settlement balance (sum across owner's account row).
	var pending int64
	_ = h.db.WithContext(ctx).Raw(
		`SELECT COALESCE(balance_paisa, 0) FROM settlement_accounts WHERE owner_id = ?`,
		ownerID,
	).Scan(&pending).Error

	cfg := pricing.Config()
	return response.OK(c, map[string]any{
		"pitches":              out,
		"premium_active":       premiumActive,
		"premium_monthly_bdt":  cfg.PremiumMonthlyBDT,
		"settlement_pending_bdt": float64(pending) / 100.0,
	})
}
