package worker

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/rs/zerolog/log"

	"github.com/turfinn/backend/internal/application/service"
)

type gamificationWorker struct {
	gameSvc   *service.GamificationService
	walletSvc *service.WalletService
}

func RegisterGamificationHandlers(mux *asynq.ServeMux, gameSvc *service.GamificationService, walletSvc *service.WalletService) {
	w := &gamificationWorker{gameSvc: gameSvc, walletSvc: walletSvc}
	mux.HandleFunc(service.TypeGamificationBooking, w.handleBooking)
	mux.HandleFunc(service.TypeGamificationMatchPost, w.handleMatchPost)
	mux.HandleFunc(service.TypeGamificationReview, w.handleReview)
	mux.HandleFunc(service.TypeLeaderboardFinalize, w.handleLeaderboardFinalize)
	mux.HandleFunc(service.TypeChallengeRotate, w.handleChallengeRotate)
}

func (w *gamificationWorker) handleBooking(ctx context.Context, t *asynq.Task) error {
	var p service.BookingGamificationPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("decode: %w", err)
	}
	userID, _ := uuid.Parse(p.UserID)
	bookingID, _ := uuid.Parse(p.BookingID)
	startsAt, _ := time.Parse(time.RFC3339, p.StartsAt)

	log.Info().Str("user", p.UserID).Msg("processing booking gamification")
	w.gameSvc.OnBookingCreated(ctx, userID, bookingID, startsAt)
	return nil
}

func (w *gamificationWorker) handleMatchPost(ctx context.Context, t *asynq.Task) error {
	var p service.MatchPostGamificationPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("decode: %w", err)
	}
	userID, _ := uuid.Parse(p.UserID)
	postID, _ := uuid.Parse(p.PostID)

	log.Info().Str("user", p.UserID).Str("action", p.Action).Msg("processing match post gamification")
	if p.Action == "create" {
		w.gameSvc.OnMatchPostCreated(ctx, userID, postID)
	} else {
		w.gameSvc.OnMatchPostJoined(ctx, userID, postID)
	}
	return nil
}

func (w *gamificationWorker) handleReview(ctx context.Context, t *asynq.Task) error {
	var p service.ReviewGamificationPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("decode: %w", err)
	}
	userID, _ := uuid.Parse(p.UserID)
	reviewID, _ := uuid.Parse(p.ReviewID)

	log.Info().Str("user", p.UserID).Msg("processing review gamification")
	w.gameSvc.OnReviewCreated(ctx, userID, reviewID)
	return nil
}

func (w *gamificationWorker) handleLeaderboardFinalize(ctx context.Context, _ *asynq.Task) error {
	log.Info().Msg("finalizing weekly leaderboard")
	return w.gameSvc.FinalizeWeek(ctx)
}

func (w *gamificationWorker) handleChallengeRotate(ctx context.Context, _ *asynq.Task) error {
	log.Info().Msg("rotating weekly challenges")
	_, err := w.gameSvc.GetWeeklyChallenges(ctx, uuid.Nil)
	return err
}
