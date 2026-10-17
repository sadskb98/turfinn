package worker

import (
	"github.com/hibiken/asynq"
	"github.com/rs/zerolog/log"
	"github.com/spf13/viper"
	"gorm.io/gorm"

	"github.com/turfinn/backend/internal/application/service"
)

// New creates and configures an asynq.Server.
func New() *asynq.Server {
	redisOpt := asynq.RedisClientOpt{
		Addr:     viper.GetString("REDIS_ADDR"),
		Password: viper.GetString("REDIS_PASSWORD"),
	}
	return asynq.NewServer(redisOpt, asynq.Config{
		Concurrency: 10,
		Queues: map[string]int{
			"critical": 6,
			"default":  3,
			"low":      1,
		},
	})
}

// NewClient creates an asynq.Client for enqueueing tasks.
func NewClient() *asynq.Client {
	redisOpt := asynq.RedisClientOpt{
		Addr:     viper.GetString("REDIS_ADDR"),
		Password: viper.GetString("REDIS_PASSWORD"),
	}
	return asynq.NewClient(redisOpt)
}

// RegisterHandlers wires all task type handlers onto the mux.
func RegisterHandlers(mux *asynq.ServeMux, db *gorm.DB) {
	mux.HandleFunc(TypeReferralReward, HandleReferralReward)
	mux.HandleFunc(TypeFCMSend, NewFCMWorker(db).Handle)
	mux.HandleFunc(TypeHoldGraduation, NewHoldGraduationWorker(db).Handle)
	mux.HandleFunc(TypeSMSSend, NewSMSWorker().Handle)
}

// RegisterMatchHandlers wires match:found and match:venue_set handlers onto the mux.
func RegisterMatchHandlers(mux *asynq.ServeMux, db *gorm.DB, asynqClient *asynq.Client) {
	w := NewMatchWorker(db, asynqClient)
	mux.HandleFunc(service.TypeMatchFound, w.HandleMatchFound)
	mux.HandleFunc(service.TypeVenueSet, w.HandleVenueSet)
}

// Run starts the asynq server in the foreground (blocking).
// Call this in a goroutine from main.
func Run(srv *asynq.Server, mux *asynq.ServeMux) {
	if err := srv.Run(mux); err != nil {
		log.Fatal().Err(err).Msg("asynq server failed")
	}
}
