package http

import (
	"fmt"
	"strings"
	"time"

	"github.com/go-playground/validator/v10"
	"github.com/labstack/echo/v4"
	echomw "github.com/labstack/echo/v4/middleware"
	"github.com/spf13/viper"
	"github.com/turfinn/backend/internal/interfaces/http/handler"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"gorm.io/gorm"
)

type customValidator struct{ v *validator.Validate }

func (cv *customValidator) Validate(i any) error { return cv.v.Struct(i) }

func NewRouter(
	db *gorm.DB,
	// Core handlers (worktree)
	authH    *handler.AuthHandler,
	pitchH   *handler.PitchHandler,
	bookingH *handler.BookingHandler,
	uploadH  *handler.UploadHandler,
	eventsH  *handler.EventsHandler,
	reviewH  *handler.ReviewHandler,
	userH    *handler.UserHandler,
	wsH      *handler.WSHandler,
	managerH *handler.ManagerHandler,
	feedH    *handler.MatchPostHandler,
	walletH  *handler.WalletHandler,
	// Admin/manage handlers (main repo)
	teamH       *handler.TeamHandler,
	adminH      *handler.AdminHandler,
	manageH     *handler.ManageHandler,
	platformH   *handler.PlatformHandler,
	marketingH  *handler.MarketingHandler,
	disputeH    *handler.DisputeHandler,
	superAdminH *handler.SuperAdminHandler,
	campaignsH      *handler.ManagerCampaignsHandler,
	gamificationH   *handler.GamificationHandler,
	tournamentH     *handler.TournamentHandler,
	// Split-payment ledger handlers
	paymentH        *handler.PaymentHandler,
	payoutH         *handler.PayoutHandler,
	adminFinanceH   *handler.AdminFinanceHandler,
	managerFinanceH *handler.ManagerFinanceHandler,
	saFinanceH      *handler.SuperAdminFinanceHandler,
	// Sports content (news + match events)
	sportsH         *handler.SportsHandler,
	matchPayH       *handler.MatchPaymentHandler,
	pricingH        *handler.PricingHandler,
	splitH          *handler.BookingSplitHandler,
) *echo.Echo {
	e := echo.New()
	e.HideBanner = true
	e.Validator = &customValidator{v: validator.New()}

	e.Use(echomw.RecoverWithConfig(echomw.DefaultRecoverConfig))
	e.Use(echomw.RequestLoggerWithConfig(echomw.RequestLoggerConfig{
		LogMethod: true,
		LogURI:    true,
		LogStatus: true,
		LogLatency: true,
		LogValuesFunc: func(c echo.Context, v echomw.RequestLoggerValues) error {
			fmt.Printf("%s %s %d %s\n", v.Method, v.URI, v.Status, v.Latency)
			return nil
		},
	}))
	corsOrigins := []string{
		"http://localhost:3000",
		"http://localhost:3002",
		"http://localhost:3003",
	}
	if raw := viper.GetString("CORS_ORIGINS"); raw != "" {
		corsOrigins = strings.Split(raw, ",")
	}
	e.Use(echomw.CORSWithConfig(echomw.CORSConfig{
		AllowOrigins: corsOrigins,
		AllowMethods: []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowHeaders: []string{"Content-Type", "Authorization"},
	}))

	// Health check for Docker/orchestrators — registered BEFORE rate limiter
	e.GET("/health", func(c echo.Context) error {
		return c.JSON(200, map[string]string{"status": "ok"})
	})

	// Deep link verification files — served without auth or rate limiting
	// iOS Universal Links: replace TEAMID with your actual Apple Developer Team ID
	e.GET("/.well-known/apple-app-site-association", func(c echo.Context) error {
		c.Response().Header().Set("Content-Type", "application/json")
		return c.String(200, `{"applinks":{"apps":[],"details":[{"appID":"TEAMID.com.app.turfinn","paths":["/pitch/*","/booking/*","/feed/*","/teams/*"]}]}}`)
	})
	// Android App Links: replace REPLACE_WITH_SHA256_FINGERPRINT with the release keystore SHA-256
	e.GET("/.well-known/assetlinks.json", func(c echo.Context) error {
		c.Response().Header().Set("Content-Type", "application/json")
		return c.String(200, `[{"relation":["delegate_permission/common.handle_all_urls"],"target":{"namespace":"android_app","package_name":"com.app.turfinn","sha256_cert_fingerprints":["REPLACE_WITH_SHA256_FINGERPRINT"]}}]`)
	})

	// Global rate limit — skip /health so Docker healthcheck doesn't exhaust the window
	e.Use(authmw.RateLimiter(200, time.Minute, func(c echo.Context) bool {
		return c.Request().URL.Path == "/health"
	}))

	// WebSocket endpoint (public, auth via query param)
	e.GET("/ws", wsH.Connect)

	v1 := e.Group("/api/v1")

	// Auth (public) — tight rate limit on OTP endpoints
	auth := v1.Group("/auth", authmw.RateLimiter(20, time.Minute))
	auth.POST("/send-otp", authH.SendOTP)
	auth.POST("/verify-otp", authH.VerifyOTP)
	auth.POST("/google", authH.GoogleSignIn)
	// Super-admin email + password login. Public on purpose — credentials
	// come from Consul, which is the gate.
	auth.POST("/super-admin-login", authH.SuperAdminLogin)

	// Pitches (list/get public, create requires auth)
	pitches := v1.Group("/pitches")
	pitches.GET("", pitchH.List)
	pitches.GET("/:id", pitchH.GetByID)
	pitches.GET("/:id/slots", pitchH.GetSlots)
	pitches.POST("", pitchH.Create, authmw.Auth(db))

	// Reviews (create requires auth, list is public)
	pitches.POST("/:pitch_id/reviews", reviewH.CreateReview, authmw.Auth(db))
	pitches.GET("/:pitch_id/reviews", reviewH.ListReviews)

	// Bookings (all require auth)
	bookings := v1.Group("/bookings", authmw.Auth(db))
	bookings.POST("", bookingH.Create, authmw.RateLimiter(20, time.Minute))
	bookings.POST("/split", splitH.Initiate, authmw.RateLimiter(10, time.Minute))
	bookings.GET("/me", bookingH.ListMine)
	bookings.DELETE("/:id", bookingH.Cancel)
	bookings.POST("/:id/pay", paymentH.Initiate)

	// Image upload (auth required)
	upload := v1.Group("/upload", authmw.Auth(db))
	upload.POST("/presign", uploadH.Presign)

	// Analytics events — auth optional
	v1.POST("/events", eventsH.Track, authmw.OptionalAuth(db))

	// Users (auth required)
	users := v1.Group("/users", authmw.Auth(db))
	users.GET("/me", userH.GetMe)
	users.PUT("/me", userH.UpdateMe)
	users.PUT("/me/fcm-token", userH.UpdateFCMToken)

	// Teams — with full CRUD and matchmaking
	teams := v1.Group("/teams", authmw.Auth(db))
	teams.POST("", teamH.CreateTeam)
	teams.GET("/me", teamH.ListMyTeams)
	teams.GET("/:id", teamH.GetTeam)
	teams.POST("/join", teamH.JoinTeam)
	teams.PUT("/:id/formation", teamH.UpdateFormation)
	teams.GET("/:id/messages", wsH.ListMessages)

	// Team captain management
	teams.POST("/:id/transfer-captain", teamH.TransferCaptain)
	teams.DELETE("/:id/members/:uid", teamH.RemoveMember)

	// Matchmaking (auth required)
	mm := v1.Group("/matchmaking", authmw.Auth(db))
	mm.POST("/find", teamH.FindMatch)
	mm.GET("/active/:team_id", teamH.GetActiveMatch)
	mm.GET("/:id", teamH.GetMatch)
	mm.PUT("/:id/venue", teamH.SetVenue)
	mm.GET("/:id/messages", wsH.ListMatchMessages)

	// Manager dashboard (role=manager required)
	manager := v1.Group("/manager", authmw.Auth(db), authmw.RequireManager())
	manager.GET("/analytics/summary", managerH.GetSummary)
	manager.GET("/analytics/revenue-chart", managerH.GetRevenueChart)
	manager.GET("/analytics/pitch-breakdown", managerH.GetPitchBreakdown)
	manager.GET("/bookings", managerH.ListBookings)
	manager.POST("/bookings", managerH.CreateWalkIn)
	manager.PUT("/bookings/:id/status", managerH.UpdateStatus)
	manager.POST("/bookings/:id/mark-cash-collected", managerH.MarkCashCollected)
	manager.GET("/financials", managerH.GetFinancials)
	manager.GET("/match-cancellations", matchPayH.ManagerListCancellations)

	// Enhanced analytics
	manager.GET("/analytics/heatmap", managerH.GetHeatmap)
	manager.GET("/analytics/peak-hours", managerH.GetPeakHours)
	manager.GET("/analytics/customers", managerH.GetCustomerInsights)

	// Enhanced financials
	manager.GET("/financials/ledger", managerH.GetDailyLedger)
	manager.GET("/financials/pitch-pnl", managerH.GetPitchPnL)

	// Manager campaigns (promo codes)
	manager.GET("/promos", campaignsH.ListPromos)
	manager.POST("/promos", campaignsH.CreatePromo)
	manager.PUT("/promos/:id/deactivate", campaignsH.DeactivatePromo)

	// Match Feed (auth required)
	feed := v1.Group("/feed", authmw.Auth(db))
	feed.POST("", feedH.Create)
	feed.GET("", feedH.List)
	feed.GET("/mine", feedH.ListMine)
	feed.GET("/:id", feedH.GetByID)
	feed.POST("/:id/join", feedH.Join)
	feed.POST("/:id/initiate-payment", matchPayH.Initiate)
	feed.POST("/:id/cancel", matchPayH.HostCancel)
	feed.POST("/:id/leave", matchPayH.JoinerCancel)
	feed.POST("/:id/report", feedH.Report)

	externals := v1.Group("/external-pitches", authmw.Auth(db))
	externals.GET("", feedH.SearchExternalPitches)
	externals.POST("", feedH.CreateExternalPitch)

	sports := v1.Group("/sports", authmw.Auth(db))
	sports.GET("/leagues", sportsH.ListLeagues)
	sports.GET("/news", sportsH.ListNews)
	sports.GET("/matches", sportsH.ListMatches)
	sports.GET("/feed", sportsH.ListFeed)
	sports.GET("/standings", sportsH.GetStandings)

	// Wallet & Profile (auth required)
	wallet := v1.Group("/wallet", authmw.Auth(db))
	wallet.GET("", walletH.GetBalance)
	wallet.GET("/transactions", walletH.ListTransactions)

	// Profile
	v1.GET("/profile", walletH.GetProfile, authmw.Auth(db))

	// Gamification (auth required)
	gamification := v1.Group("", authmw.Auth(db))
	gamification.POST("/checkin", gamificationH.Checkin)
	gamification.GET("/checkin/status", gamificationH.GetCheckinStatus)
	gamification.GET("/challenges", gamificationH.GetChallenges)
	gamification.GET("/leaderboard", gamificationH.GetLeaderboard)
	gamification.GET("/leaderboard/previous", gamificationH.GetPreviousLeaderboard)
	gamification.GET("/referral", gamificationH.GetReferral)
	gamification.POST("/referral/apply", gamificationH.ApplyReferral)
	gamification.POST("/store/streak-freeze", gamificationH.BuyStreakFreeze)

	// Tournaments (auth required)
	tournaments := v1.Group("/tournaments", authmw.Auth(db))
	tournaments.POST("", tournamentH.Create)
	tournaments.GET("", tournamentH.List)
	tournaments.GET("/:id", tournamentH.Get)
	tournaments.POST("/:id/join", tournamentH.Join)
	tournaments.POST("/:id/start", tournamentH.Start)
	tournaments.POST("/:id/cancel", tournamentH.Cancel)
	tournaments.POST("/:id/leave", tournamentH.Leave)
	tournaments.POST("/:id/matches/:mid/report", tournamentH.ReportScore)
	tournaments.POST("/:id/matches/:mid/confirm", tournamentH.ConfirmScore)
	tournaments.POST("/:id/matches/:mid/dispute", tournamentH.DisputeScore)

	// ── Admin panel (admin + super_admin) ─────────────────────────────────────
	// Super-admin needs the same data the admin panel shows (users, pitches,
	// bookings, teams, matches, dashboard) — the /super-admin group is for
	// platform-level analytics + governance, not raw entity CRUD. Without
	// super_admin in this gate, the super-admin web panel renders empty
	// for half its sidebar.
	admin := v1.Group("/admin", authmw.Auth(db), authmw.RequireRole("admin", "super_admin"))
	admin.GET("/dashboard", adminH.Dashboard)
	admin.GET("/users", adminH.ListUsers)
	admin.PUT("/users/:id/role", adminH.UpdateUserRole) // returns 400 — kept for backward compat
	admin.PUT("/users/:id/active", adminH.SetUserActive)
	admin.GET("/pitches", adminH.ListPitches)
	admin.POST("/pitches", adminH.CreatePitch)
	admin.PUT("/pitches/:id/toggle", adminH.TogglePitch)
	admin.GET("/bookings", adminH.ListBookings)
	admin.PUT("/bookings/:id/status", adminH.UpdateBookingStatus)
	admin.GET("/teams", adminH.ListTeams)
	admin.GET("/matches", adminH.ListMatches)

	// ── Turf manager panel (manager + admin) ─────────────────────────────────
	manage := v1.Group("/manage", authmw.Auth(db), authmw.RequireRole("manager", "admin"))
	manage.GET("/dashboard", manageH.Dashboard)
	manage.GET("/pitches", manageH.ListMyPitches)
	manage.POST("/pitches", manageH.CreatePitch)
	manage.PUT("/pitches/:id", manageH.UpdatePitch)
	manage.PUT("/pitches/:id/toggle", manageH.TogglePitch)
	manage.GET("/bookings", manageH.ListBookings)
	manage.PUT("/bookings/:id/confirm", manageH.ConfirmBooking)
	manage.PUT("/bookings/:id/cancel", manageH.CancelBooking)
	manage.GET("/kyc/me", manageH.GetMyKYC)
	manage.POST("/kyc", manageH.SubmitKYC)
	manage.GET("/billing", manageH.GetMyBilling)

	// ── Platform Configuration (admin) ───────────────────────────────────────
	platform := v1.Group("/admin/platform", authmw.Auth(db), authmw.RequireRole("admin", "super_admin"))
	platform.GET("/settings", platformH.GetSettings)
	platform.PUT("/settings", platformH.UpdateSettings)
	platform.GET("/settings/audit", platformH.GetSettingsAudit)
	platform.GET("/pricing-rules", platformH.ListPricingRules)
	platform.POST("/pricing-rules", platformH.CreatePricingRule)
	platform.DELETE("/pricing-rules/:id", platformH.DeletePricingRule)
	platform.GET("/flags", platformH.GetFlags)
	platform.PUT("/flags/:key", platformH.UpdateFlag)
	platform.GET("/templates", platformH.ListTemplates)
	platform.POST("/templates", platformH.CreateTemplate)
	platform.DELETE("/templates/:id", platformH.DeleteTemplate)
	platform.POST("/templates/:id/preview", platformH.PreviewTemplate)

	// Public config endpoint (no auth)
	v1.GET("/config", platformH.GetPublicConfig)

	// ── Marketing & Growth (admin) ───────────────────────────────────────────
	marketing := v1.Group("/admin/marketing", authmw.Auth(db), authmw.RequireRole("admin", "super_admin"))
	marketing.GET("/promo-codes", marketingH.ListPromoCodes)
	marketing.POST("/promo-codes", marketingH.CreatePromoCode)
	marketing.PUT("/promo-codes/:id/deactivate", marketingH.DeactivatePromoCode)
	marketing.GET("/promo-codes/:id/usage", marketingH.GetPromoUsage)
	marketing.GET("/campaigns", marketingH.ListCampaigns)
	marketing.POST("/campaigns", marketingH.CreateCampaign)
	marketing.POST("/campaigns/:id/send", marketingH.SendCampaign)
	marketing.GET("/featured-pitches", marketingH.ListFeaturedPitches)
	marketing.POST("/featured-pitches", marketingH.CreateFeaturedPitch)
	marketing.DELETE("/featured-pitches/:id", marketingH.DeleteFeaturedPitch)
	marketing.GET("/referral-stats", marketingH.GetReferralStats)
	marketing.GET("/banners", marketingH.ListBanners)
	marketing.POST("/banners", marketingH.CreateBanner)
	marketing.DELETE("/banners/:id", marketingH.DeleteBanner)

	// Active banners — public (for mobile app)
	v1.GET("/banners", marketingH.ListActiveBanners)

	// ── Disputes & Support (admin) ───────────────────────────────────────────
	disputes := v1.Group("/admin/disputes", authmw.Auth(db), authmw.RequireRole("admin", "super_admin"))
	disputes.GET("", disputeH.ListDisputes)
	disputes.GET("/:id", disputeH.GetDispute)
	disputes.POST("", disputeH.CreateDispute)
	disputes.PUT("/:id/resolve", disputeH.ResolveDispute)

	tickets := v1.Group("/admin/tickets", authmw.Auth(db), authmw.RequireRole("admin", "super_admin"))
	tickets.GET("", disputeH.ListTickets)
	tickets.GET("/:id", disputeH.GetTicket)
	tickets.POST("/:id/reply", disputeH.ReplyTicket)
	tickets.PUT("/:id/assign", disputeH.AssignTicket)

	adminReviews := v1.Group("/admin/reviews", authmw.Auth(db), authmw.RequireRole("admin", "super_admin"))
	adminReviews.GET("/flagged", disputeH.ListFlaggedReviews)
	adminReviews.PUT("/:id/moderate", disputeH.ModerateReview)

	userActions := v1.Group("/admin/user-actions", authmw.Auth(db), authmw.RequireRole("admin", "super_admin"))
	userActions.POST("/:id/warn", disputeH.WarnUser)
	userActions.POST("/:id/ban", disputeH.BanUser)
	userActions.POST("/:id/unban", disputeH.UnbanUser)

	// KYC / Verification (admin)
	kyc := v1.Group("/admin/kyc", authmw.Auth(db), authmw.RequireRole("admin", "super_admin"))
	kyc.GET("", disputeH.ListKYC)
	kyc.GET("/:id", disputeH.GetKYC)
	kyc.PUT("/:id/approve", disputeH.ApproveKYC)
	kyc.PUT("/:id/reject", disputeH.RejectKYC)

	// Player-facing: create dispute (uses same handler, auth-only)
	support := v1.Group("/support", authmw.Auth(db))
	support.POST("/disputes", disputeH.CreateDispute)

	// ── Super Admin Panel ────────────────────────────────────────────────────
	sa := v1.Group("/super-admin", authmw.Auth(db), authmw.RequireRole("super_admin"))

	// Business Intelligence
	sa.GET("/north-star", superAdminH.GetNorthStar)
	sa.GET("/cohort-retention", superAdminH.GetCohortRetention)
	sa.GET("/funnel", superAdminH.GetFunnel)
	sa.GET("/revenue", superAdminH.GetRevenueTimeSeries)

	// Booking Events (analytics ingestion)
	sa.POST("/events", superAdminH.IngestBookingEvent)
	sa.POST("/marketing-spend", superAdminH.UpsertMarketingSpend)

	// Audit Log
	sa.GET("/audit-log", superAdminH.ListAuditLog)

	// Ledger & Finance
	sa.GET("/ledger", superAdminH.ListLedger)
	sa.GET("/trial-balance", superAdminH.GetTrialBalance)
	sa.GET("/income-statement", superAdminH.GetIncomeStatement)
	sa.GET("/vat-report", superAdminH.GetVATReport)

	// Fraud
	sa.GET("/fraud-flags", superAdminH.ListFraudFlags)
	sa.PUT("/fraud-flags/:id", superAdminH.UpdateFraudFlag)

	// System Control
	sa.GET("/rate-limits", superAdminH.ListRateLimits)
	sa.PUT("/rate-limits/:group", superAdminH.UpdateRateLimit)
	sa.GET("/api-keys", superAdminH.ListAPIKeys)
	sa.POST("/api-keys", superAdminH.CreateAPIKey)
	sa.DELETE("/api-keys/:id", superAdminH.RevokeAPIKey)

	// Zones & Partners
	sa.GET("/zones", superAdminH.ListZones)
	sa.POST("/zones", superAdminH.CreateZone)
	sa.GET("/organizations", superAdminH.ListOrganizations)
	sa.POST("/organizations", superAdminH.CreateOrganization)
	sa.POST("/organizations/:id/credit", superAdminH.AddOrgCredit)
	sa.GET("/resellers", superAdminH.ListResellers)
	sa.POST("/resellers", superAdminH.CreateReseller)

	// Turf Admin (manager) registration
	sa.GET("/managers", superAdminH.ListManagers)
	sa.POST("/managers", superAdminH.CreateManager)

	// Pitch pricing (Aviv plan): per-pitch fee overrides, trial, premium,
	// add-on toggles. All gated to super_admin via the /super-admin group.
	sa.PUT("/pitches/:id/pricing", pricingH.UpdatePitchPricing)
	sa.PUT("/pitches/:id/premium", pricingH.SetPremium)
	sa.POST("/pitches/:id/addons/:kind/:action", pricingH.ToggleAddon)

	// Match-payment + refund admin tools
	sa.GET("/match-payments", matchPayH.AdminListPayments)
	sa.POST("/match-payments/:id/retry-refund", matchPayH.AdminRetryRefund)
	sa.POST("/match-payments/:id/mark-refunded", matchPayH.AdminMarkRefunded)
	sa.GET("/match-cancellations", matchPayH.AdminListCancellations)

	// ── Payment callbacks (no auth — SSLCommerz posts to these) ─────────────
	v1.POST("/payment/success", paymentH.Success)
	v1.POST("/payment/ipn", paymentH.IPN)
	v1.POST("/payment/fail", paymentH.Fail)
	v1.POST("/payment/cancel", paymentH.Cancel)
	// Match-join SSL callbacks — separate URLs so we route by path instead
	// of inspecting tran_id. Public, like the booking ones.
	v1.POST("/payment/match/success", matchPayH.Success)
	v1.POST("/payment/match/ipn", matchPayH.IPN)
	v1.POST("/payment/match/fail", matchPayH.Fail)
	v1.POST("/payment/match/cancel", matchPayH.Cancel)

	// Split-pay public surface — magic link + share claim + SSL callbacks.
	// All auth-free: friends drop into the link from WhatsApp without
	// having a Turfinn account.
	v1.GET("/split/:token", splitH.GetByToken)
	v1.POST("/split/:token/claim", splitH.Claim)
	v1.POST("/payment/split/success", splitH.Success)
	v1.POST("/payment/split/ipn", splitH.IPN)
	v1.POST("/payment/split/fail", splitH.Fail)
	v1.POST("/payment/split/cancel", splitH.Cancel)

	// ── Manager payout routes ────────────────────────────────────────────────
	manager.POST("/payout-methods", payoutH.AddPayoutMethod)
	manager.GET("/payout-methods", payoutH.ListPayoutMethods)
	manager.DELETE("/payout-methods/:id", payoutH.DeletePayoutMethod)
	manager.POST("/payouts", payoutH.RequestPayout)
	manager.GET("/payouts", payoutH.ListPayouts)

	// ── Manager finance routes ───────────────────────────────────────────────
	manager.GET("/wallet", managerFinanceH.GetWallet)
	manager.GET("/wallet/transactions", managerFinanceH.ListWalletTransactions)
	manager.GET("/financials/settlements", managerFinanceH.ListSettlements)
	manager.GET("/financials/fee-config", managerFinanceH.GetFeeConfig)
	manager.GET("/financials/analytics", managerFinanceH.GetFinancialAnalytics)
	manager.GET("/tax/wht-certificates", managerFinanceH.ListWHTCertificates)
	manager.GET("/tax/summary", managerFinanceH.GetTaxSummary)

	// ── Admin finance routes ─────────────────────────────────────────────────
	admin.GET("/payouts", adminFinanceH.ListAllPayouts)
	admin.PUT("/payouts/:id/approve", adminFinanceH.ApprovePayout)
	admin.PUT("/payouts/:id/process", adminFinanceH.ProcessPayout)
	admin.PUT("/payouts/:id/complete", adminFinanceH.CompletePayout)
	admin.PUT("/payouts/:id/reject", adminFinanceH.RejectPayout)
	admin.GET("/fee-configs", adminFinanceH.ListFeeConfigs)
	admin.POST("/fee-configs", adminFinanceH.CreateFeeConfig)
	admin.PUT("/fee-configs/:id", adminFinanceH.UpdateFeeConfig)
	admin.GET("/gateway-fee-rates", adminFinanceH.ListGatewayFeeRates)
	admin.PUT("/gateway-fee-rates/:card_type", adminFinanceH.UpdateGatewayFeeRate)
	admin.POST("/gateway-fee-reconciliations", adminFinanceH.CreateGatewayFeeReconciliation)

	// ── Super admin finance routes ───────────────────────────────────────────
	sa.GET("/finance/platform-wallet", saFinanceH.GetPlatformWallet)
	sa.GET("/finance/revenue-summary", saFinanceH.GetRevenueSummary)
	sa.GET("/finance/manager-balances", saFinanceH.GetManagerBalances)
	sa.GET("/finance/receivables", saFinanceH.GetReceivables)
	sa.GET("/tax/export", saFinanceH.ExportTaxCSV)

	return e
}
