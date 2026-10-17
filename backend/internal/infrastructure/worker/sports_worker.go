package worker

import (
	"context"

	"github.com/hibiken/asynq"
	"github.com/rs/zerolog/log"

	"github.com/turfinn/backend/internal/application/service"
)

const (
	TypeSportsNewsFetch      = "sports:news_fetch"
	TypeSportsMatchesFetch   = "sports:matches_fetch"
	TypeSportsStandingsFetch = "sports:standings_fetch"
)

type SportsWorker struct {
	svc *service.SportsService
}

func NewSportsWorker(svc *service.SportsService) *SportsWorker {
	return &SportsWorker{svc: svc}
}

func (w *SportsWorker) HandleNewsFetch(ctx context.Context, _ *asynq.Task) error {
	count, err := w.svc.FetchAndStoreNews(ctx)
	if err != nil {
		log.Error().Err(err).Msg("sports news fetch failed")
		return err
	}
	log.Info().Int("upserted", count).Msg("sports news fetch ok")
	return nil
}

func (w *SportsWorker) HandleMatchesFetch(ctx context.Context, _ *asynq.Task) error {
	count, err := w.svc.FetchAndStoreMatches(ctx)
	if err != nil {
		log.Error().Err(err).Msg("sports matches fetch failed")
		return err
	}
	log.Info().Int("upserted", count).Msg("sports matches fetch ok")
	return nil
}

func (w *SportsWorker) HandleStandingsFetch(ctx context.Context, _ *asynq.Task) error {
	count, err := w.svc.FetchAndStoreStandings(ctx)
	if err != nil {
		log.Error().Err(err).Msg("sports standings fetch failed")
		return err
	}
	log.Info().Int("leagues", count).Msg("sports standings fetch ok")
	return nil
}

// RegisterSportsHandlers wires the news + matches + standings fetch handlers onto the mux.
func RegisterSportsHandlers(mux *asynq.ServeMux, svc *service.SportsService) {
	w := NewSportsWorker(svc)
	mux.HandleFunc(TypeSportsNewsFetch, w.HandleNewsFetch)
	mux.HandleFunc(TypeSportsMatchesFetch, w.HandleMatchesFetch)
	mux.HandleFunc(TypeSportsStandingsFetch, w.HandleStandingsFetch)
}
