package main

import (
	"context"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/hibiken/asynq"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
	"github.com/spf13/viper"
	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/config"
	"github.com/turfinn/backend/internal/infrastructure/database"
	redisdb "github.com/turfinn/backend/internal/infrastructure/redis"
	"github.com/turfinn/backend/internal/infrastructure/realtime"
	infrarepo "github.com/turfinn/backend/internal/infrastructure/repository"
	"github.com/turfinn/backend/internal/infrastructure/sportsapi"
	"github.com/turfinn/backend/internal/infrastructure/sslcommerz"
	"github.com/turfinn/backend/internal/infrastructure/storage"
	"github.com/turfinn/backend/internal/infrastructure/worker"
	"github.com/turfinn/backend/internal/interfaces/http/handler"
	httpserver "github.com/turfinn/backend/internal/interfaces/http"
)

func main() {
	log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr})

	// Config — load from Consul first (if configured), then .env, then env vars
	config.LoadConsul()
	viper.SetConfigFile(".env")
	viper.AutomaticEnv()
	_ = viper.ReadInConfig()

	port := viper.GetString("APP_PORT")
	if port == "" {
		port = "8080"
	}

	if secret := viper.GetString("JWT_SECRET"); secret == "" || secret == "change-me-in-production" {
		log.Fatal().Msg("JWT_SECRET must be set to a secure value before starting")
	}

	// DB
	db, err := database.NewPostgresDB()
	if err != nil {
		log.Fatal().Err(err).Msg("postgres connection failed")
	}

	// Redis
	redisClient, err := redisdb.NewRedisClient()
	if err != nil {
		log.Fatal().Err(err).Msg("redis connection failed")
	}

	// WebSocket hub
	hub := realtime.NewHub(redisClient)

	// Asynq worker
	asynqClient := worker.NewClient()
	defer asynqClient.Close()
	asynqServer := worker.New()
	mux := asynq.NewServeMux()
	worker.RegisterHandlers(mux, db)
	worker.RegisterMatchHandlers(mux, db, asynqClient)
	go worker.Run(asynqServer, mux)

	// MinIO
	storageClient, err := storage.NewClient(context.Background(), storage.Config{
		Endpoint:  viper.GetString("MINIO_ENDPOINT"),
		AccessKey: viper.GetString("MINIO_ACCESS_KEY"),
		SecretKey: viper.GetString("MINIO_SECRET_KEY"),
		UseSSL:    viper.GetBool("MINIO_USE_SSL"),
	})
	if err != nil {
		log.Fatal().Err(err).Msg("minio connection failed")
	}

	// Repositories
	userRepo := infrarepo.NewUserRepository(db, redisClient)
	pitchRepo := infrarepo.NewPitchRepository(db, redisClient)
	bookingRepo := infrarepo.NewBookingRepository(db, redisClient)
	reviewRepo := infrarepo.NewReviewRepository(db, redisClient)
	matchPostRepo := infrarepo.NewMatchPostRepository(db, redisClient)
	externalPitchRepo := infrarepo.NewExternalPitchRepository(db)
	matchReportRepo := infrarepo.NewMatchReportRepository(db)
	matchCancelRepo := infrarepo.NewMatchCancellationRepository(db)
	teamRepo := infrarepo.NewTeamRepository(db, redisClient)
	platformRepo := infrarepo.NewPlatformRepository(db, redisClient)
	marketingRepo := infrarepo.NewMarketingRepository(db, redisClient)
	disputeRepo := infrarepo.NewDisputeRepository(db, redisClient)
	verificationRepo := infrarepo.NewVerificationRepository(db, redisClient)
	superAdminRepo := infrarepo.NewSuperAdminRepository(db, redisClient)
	newsRepo := infrarepo.NewNewsRepository(db)
	matchEventRepo := infrarepo.NewMatchEventRepository(db)
	matchStandingRepo := infrarepo.NewMatchStandingRepository(db)

	// Services
	authSvc := service.NewAuthService(userRepo, redisClient, asynqClient)
	pitchSvc := service.NewPitchService(pitchRepo)
	walletSvc := service.NewWalletService(db)
	gamificationSvc := service.NewGamificationService(db, walletSvc)
	bookingSvc := service.NewBookingService(bookingRepo, pitchRepo, walletSvc, gamificationSvc, db, asynqClient)
	userSvc := service.NewUserService(userRepo)
	analyticsSvc := service.NewAnalyticsService(db)
	matchPostSvc := service.NewMatchPostService(matchPostRepo, walletSvc, gamificationSvc, asynqClient, db)
	matchPostSvc.SetSafetyDeps(matchReportRepo, matchCancelRepo, externalPitchRepo)
	matchPostSvc.SetPitchRepo(pitchRepo)
	teamSvc := service.NewTeamService(teamRepo, userRepo, asynqClient)
	tournamentSvc := service.NewTournamentService(db, walletSvc)

	// Split-payment ledger services
	ledgerWalletSvc := service.NewLedgerWalletService(db)
	feeSvc          := service.NewFeeService(db)
	taxSvc          := service.NewTaxService(db)
	settlementSvc   := service.NewSettlementService(db, feeSvc, taxSvc, ledgerWalletSvc)

	sslczClient := sslcommerz.NewClient(
		viper.GetString("SSLCZ_STORE_ID"),
		viper.GetString("SSLCZ_STORE_PASSWD"),
		viper.GetString("SSLCZ_BASE_URL"),
	)
	paymentSvc      := service.NewPaymentService(db, userRepo, sslczClient, settlementSvc,
		viper.GetString("SSLCZ_STORE_PASSWD"),
		viper.GetString("APP_BASE_URL"),
	)
	payoutSvc       := service.NewPayoutService(db, ledgerWalletSvc)
	adminFinanceSvc := service.NewAdminFinanceService(db, ledgerWalletSvc)

	// Handlers
	authH := handler.NewAuthHandler(authSvc)
	pitchH := handler.NewPitchHandler(pitchSvc)
	bookingH := handler.NewBookingHandler(bookingSvc, asynqClient)
	uploadH := handler.NewUploadHandler(storageClient)
	eventsH := handler.NewEventsHandler(db)
	reviewH := handler.NewReviewHandler(reviewRepo)
	userH := handler.NewUserHandler(userSvc)
	wsH := handler.NewWSHandler(hub, db)
	managerAnalyticsSvc := service.NewManagerAnalyticsService(db)
	managerH := handler.NewManagerHandler(analyticsSvc, managerAnalyticsSvc, bookingSvc)
	// feedH wired below, after matchJoinPaySvc is constructed.
	walletH := handler.NewWalletHandler(walletSvc, gamificationSvc)
	gamificationH := handler.NewGamificationHandler(gamificationSvc)
	teamH := handler.NewTeamHandler(teamSvc)
	adminH := handler.NewAdminHandler(userRepo, pitchRepo, bookingRepo, teamRepo)
	manageH := handler.NewManageHandler(pitchRepo, bookingRepo, verificationRepo, userRepo, db)
	platformH := handler.NewPlatformHandler(platformRepo)
	marketingH := handler.NewMarketingHandler(marketingRepo)
	disputeH := handler.NewDisputeHandler(disputeRepo, verificationRepo, userRepo)
	superAdminH := handler.NewSuperAdminHandler(superAdminRepo, userRepo)
	campaignsH := handler.NewManagerCampaignsHandler(db)
	tournamentH := handler.NewTournamentHandler(tournamentSvc)

	// Split-payment ledger handlers
	paymentH        := handler.NewPaymentHandler(paymentSvc, viper.GetString("APP_BASE_URL"))
	payoutH         := handler.NewPayoutHandler(payoutSvc)
	adminFinanceH   := handler.NewAdminFinanceHandler(adminFinanceSvc)
	managerFinanceH := handler.NewManagerFinanceHandler(db)
	saFinanceH      := handler.NewSuperAdminFinanceHandler(db)

	// Match-join SSL payment session
	matchJoinPaySvc := service.NewMatchJoinPaymentService(
		db, matchPostRepo, userRepo, sslczClient,
		viper.GetString("SSLCZ_STORE_PASSWD"),
		viper.GetString("APP_BASE_URL"),
	).WithAsynq(asynqClient)
	auditSvc := service.NewAuditService(db)
	matchPayH := handler.NewMatchPaymentHandler(matchJoinPaySvc, auditSvc)
	pricingH := handler.NewPricingHandler(db)
	feedH := handler.NewMatchPostHandler(matchPostSvc, matchJoinPaySvc)

	// Split-pay (group bookings) — captain initiates, friends pay shares
	// via a public magic-link page. SSL Commerz reused for each share.
	bookingShareRepo := infrarepo.NewBookingShareRepository(db)
	bookingSplitSvc := service.NewBookingSplitService(
		db, bookingRepo, bookingShareRepo, pitchRepo, userRepo,
		sslczClient,
		viper.GetString("SSLCZ_STORE_PASSWD"),
		viper.GetString("APP_BASE_URL"),
	).WithAsynq(asynqClient)
	splitH := handler.NewBookingSplitHandler(bookingSplitSvc)

	// Sports content (news + match events + standings)
	footballAPI := sportsapi.NewAPIFootballClient(viper.GetString("API_FOOTBALL_KEY"))
	gnews := sportsapi.NewGNewsClient(viper.GetString("GNEWS_KEY"))
	sportsSvc := service.NewSportsService(newsRepo, matchEventRepo, matchStandingRepo, footballAPI, gnews)
	sportsH := handler.NewSportsHandler(newsRepo, matchEventRepo, sportsSvc)

	// Router
	e := httpserver.NewRouter(
		db,
		authH, pitchH, bookingH, uploadH, eventsH, reviewH, userH, wsH, managerH, feedH, walletH,
		teamH, adminH, manageH, platformH, marketingH, disputeH, superAdminH, campaignsH, gamificationH,
		tournamentH,
		paymentH, payoutH, adminFinanceH, managerFinanceH, saFinanceH,
		sportsH,
		matchPayH,
		pricingH,
		splitH,
	)

	// Graceful shutdown
	go func() {
		if err := e.Start(":" + port); err != nil {
			log.Info().Msg("server stopped")
		}
	}()
	log.Info().Str("port", port).Msg("turfinn api started")

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := e.Shutdown(ctx); err != nil {
		log.Fatal().Err(err).Msg("server shutdown failed")
	}
	asynqServer.Shutdown()
}
