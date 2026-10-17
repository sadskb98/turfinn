package worker

import (
	"github.com/hibiken/asynq"
	"github.com/rs/zerolog/log"
	"github.com/spf13/viper"

	"github.com/turfinn/backend/internal/application/service"
)

// NewScheduler creates an asynq.Scheduler for recurring cron tasks.
func NewScheduler() *asynq.Scheduler {
	redisOpt := asynq.RedisClientOpt{
		Addr:     viper.GetString("REDIS_ADDR"),
		Password: viper.GetString("REDIS_PASSWORD"),
	}
	scheduler := asynq.NewScheduler(redisOpt, nil)

	// Finalize leaderboard every Monday at 00:05 UTC
	_, err := scheduler.Register("5 0 * * 1",
		asynq.NewTask(service.TypeLeaderboardFinalize, nil),
		asynq.Queue("default"),
	)
	if err != nil {
		log.Error().Err(err).Msg("failed to register leaderboard cron")
	}

	// Rotate weekly challenges every Monday at 00:01 UTC
	_, err = scheduler.Register("1 0 * * 1",
		asynq.NewTask(service.TypeChallengeRotate, nil),
		asynq.Queue("default"),
	)
	if err != nil {
		log.Error().Err(err).Msg("failed to register challenge rotation cron")
	}

	// Graduate manager wallet holds nightly at 02:00 UTC
	_, err = scheduler.Register("0 2 * * *",
		asynq.NewTask(service.TypeHoldGraduation, nil),
		asynq.Queue("default"),
	)
	if err != nil {
		log.Error().Err(err).Msg("failed to register hold graduation cron")
	}

	// Pull sports news every 30 minutes (~48 GNews calls/day, fits free tier).
	_, err = scheduler.Register("*/30 * * * *",
		asynq.NewTask(TypeSportsNewsFetch, nil),
		asynq.Queue("low"),
	)
	if err != nil {
		log.Error().Err(err).Msg("failed to register sports news cron")
	}

	// Pull match fixtures every 15 minutes (~96 API-Football calls/day, fits free tier).
	_, err = scheduler.Register("*/15 * * * *",
		asynq.NewTask(TypeSportsMatchesFetch, nil),
		asynq.Queue("low"),
	)
	if err != nil {
		log.Error().Err(err).Msg("failed to register sports matches cron")
	}

	// Refresh league standings every 6 hours (12 leagues × 4 = 48 calls/day).
	_, err = scheduler.Register("0 */6 * * *",
		asynq.NewTask(TypeSportsStandingsFetch, nil),
		asynq.Queue("low"),
	)
	if err != nil {
		log.Error().Err(err).Msg("failed to register sports standings cron")
	}

	// Match-payment refund retry — every 5 minutes. SSL has a per-minute
	// rate limit; the worker spaces individual calls 500ms apart.
	_, err = scheduler.Register("*/5 * * * *",
		asynq.NewTask(TypeMatchRefundRetry, nil),
		asynq.Queue("default"),
	)
	if err != nil {
		log.Error().Err(err).Msg("failed to register match refund retry cron")
	}

	// Auto-cancel match posts whose kickoff has passed without filling.
	// Triggers refunds for paid joiners.
	_, err = scheduler.Register("*/5 * * * *",
		asynq.NewTask(TypeMatchAutoCancel, nil),
		asynq.Queue("default"),
	)
	if err != nil {
		log.Error().Err(err).Msg("failed to register match auto-cancel cron")
	}

	// Weekly settlement payout — Monday 02:00 UTC = 08:00 BDT. Drains
	// every owner's running settlement_account balance into ledger
	// payout rows. Real disbursement is manual export until APIs land.
	_, err = scheduler.Register("0 2 * * 1",
		asynq.NewTask(TypeSettlementWeekly, nil),
		asynq.Queue("default"),
	)
	if err != nil {
		log.Error().Err(err).Msg("failed to register weekly settlement cron")
	}

	return scheduler
}
