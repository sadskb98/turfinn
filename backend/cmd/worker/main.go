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
	infrarepo "github.com/turfinn/backend/internal/infrastructure/repository"
	"github.com/turfinn/backend/internal/infrastructure/sportsapi"
	"github.com/turfinn/backend/internal/infrastructure/sslcommerz"
	"github.com/turfinn/backend/internal/infrastructure/worker"
)

func main() {
	log.Logger = zerolog.New(zerolog.ConsoleWriter{Out: os.Stdout}).
		With().Timestamp().Str("service", "worker").Logger()

	config.LoadConsul()
	viper.AutomaticEnv()
	viper.SetDefault("REDIS_ADDR", "localhost:6379")
	viper.SetDefault("DB_HOST", "localhost")
	viper.SetDefault("DB_PORT", "5432")
	viper.SetDefault("DB_USER", "turfinn")
	viper.SetDefault("DB_PASSWORD", "turfinn")
	viper.SetDefault("DB_NAME", "turfinn")

	db, err := database.NewPostgresDB()
	if err != nil {
		log.Fatal().Err(err).Msg("database connection failed")
	}

	walletSvc := service.NewWalletService(db)
	gameSvc := service.NewGamificationService(db, walletSvc)

	// Match payment / refund retry — needs the SSLCommerz client.
	sslczClient := sslcommerz.NewClient(
		viper.GetString("SSLCZ_STORE_ID"),
		viper.GetString("SSLCZ_STORE_PASSWD"),
		viper.GetString("SSLCZ_BASE_URL"),
	)
	matchPostRepo := infrarepo.NewMatchPostRepository(db, nil)
	userRepoForPay := infrarepo.NewUserRepository(db, nil)
	asynqClientForPay := worker.NewClient()
	defer asynqClientForPay.Close()
	matchPaySvc := service.NewMatchJoinPaymentService(
		db, matchPostRepo, userRepoForPay, sslczClient,
		viper.GetString("SSLCZ_STORE_PASSWD"),
		viper.GetString("APP_BASE_URL"),
	).WithAsynq(asynqClientForPay)
	matchRefundWorker := worker.NewMatchRefundWorker(db, matchPaySvc)

	// Split-pay deadline expiry worker — refunds paid shares + cancels
	// the booking when split_deadline_at passes without quorum hit.
	bookingRepoForSplit := infrarepo.NewBookingRepository(db, nil)
	bookingShareRepo := infrarepo.NewBookingShareRepository(db)
	pitchRepoForSplit := infrarepo.NewPitchRepository(db, nil)
	bookingSplitSvc := service.NewBookingSplitService(
		db, bookingRepoForSplit, bookingShareRepo, pitchRepoForSplit, userRepoForPay,
		sslczClient,
		viper.GetString("SSLCZ_STORE_PASSWD"),
		viper.GetString("APP_BASE_URL"),
	).WithAsynq(asynqClientForPay)
	splitDeadlineWorker := worker.NewSplitDeadlineWorker(bookingSplitSvc)

	// Aviv weekly-settlement worker. Drains owner balances every Monday.
	weeklySettleSvc := service.NewWeeklySettlementService(db)
	weeklySettleWorker := worker.NewWeeklySettlementWorker(weeklySettleSvc)

	// Sports content fetch (cron-driven, see scheduler.go)
	newsRepo := infrarepo.NewNewsRepository(db)
	matchEventRepo := infrarepo.NewMatchEventRepository(db)
	matchStandingRepo := infrarepo.NewMatchStandingRepository(db)
	footballAPI := sportsapi.NewAPIFootballClient(viper.GetString("API_FOOTBALL_KEY"))
	gnews := sportsapi.NewGNewsClient(viper.GetString("GNEWS_KEY"))
	sportsSvc := service.NewSportsService(newsRepo, matchEventRepo, matchStandingRepo, footballAPI, gnews)

	srv := worker.New()
	mux := asynq.NewServeMux()
	worker.RegisterHandlers(mux, db)
	worker.RegisterGamificationHandlers(mux, gameSvc, walletSvc)
	worker.RegisterSportsHandlers(mux, sportsSvc)
	worker.RegisterMatchRefundHandlers(mux, matchRefundWorker)
	worker.RegisterWeeklySettlementHandlers(mux, weeklySettleWorker)
	worker.RegisterSplitDeadlineHandlers(mux, splitDeadlineWorker)
	asynqClient := worker.NewClient()
	defer asynqClient.Close()
	worker.RegisterMatchHandlers(mux, db, asynqClient)

	// Scheduler for cron tasks (challenge rotation, leaderboard finalization)
	scheduler := worker.NewScheduler()
	go func() {
		if err := scheduler.Run(); err != nil {
			log.Error().Err(err).Msg("scheduler stopped")
		}
	}()

	// Real-time live-score poller — gated by SPORTS_LIVE_POLL_ENABLED so it
	// only runs on a paid API-Football plan. Free tier (100 calls/day) would
	// be exhausted in ~25 minutes at this cadence.
	pollerCtx, pollerCancel := context.WithCancel(context.Background())
	defer pollerCancel()
	if viper.GetBool("SPORTS_LIVE_POLL_ENABLED") {
		interval := viper.GetDuration("SPORTS_LIVE_POLL_INTERVAL")
		if interval < 5*time.Second {
			interval = 15 * time.Second
		}
		go runLiveScorePoller(pollerCtx, sportsSvc, interval)
		log.Info().Dur("interval", interval).Msg("live-score poller started")
	} else {
		log.Info().Msg("live-score poller disabled (set SPORTS_LIVE_POLL_ENABLED=true to enable)")
	}

	go func() {
		log.Info().Msg("worker started")
		if err := srv.Run(mux); err != nil {
			log.Fatal().Err(err).Msg("worker crashed")
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Info().Msg("shutting down...")
	pollerCancel()
	srv.Shutdown()
	scheduler.Shutdown()
}

// runLiveScorePoller calls PollLiveScores on a fixed interval until ctx done.
// Errors are logged and the loop continues — transient API hiccups shouldn't
// kill the poller.
func runLiveScorePoller(ctx context.Context, svc *service.SportsService, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			n, err := svc.PollLiveScores(ctx)
			if err != nil {
				log.Warn().Err(err).Msg("live poll failed")
				continue
			}
			if n > 0 {
				log.Debug().Int("upserted", n).Msg("live poll ok")
			}
		}
	}
}
