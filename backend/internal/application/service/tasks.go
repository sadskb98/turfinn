package service

import (
	"context"
	"encoding/json"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"gorm.io/gorm"
)

// Task type constants — shared between API (enqueue) and worker (dequeue)
const (
	TypeGamificationBooking   = "gamification:booking"
	TypeGamificationMatchPost = "gamification:match_post"
	TypeGamificationReview    = "gamification:review"
	TypeLeaderboardFinalize   = "gamification:leaderboard_finalize"
	TypeChallengeRotate       = "gamification:challenge_rotate"
	TypeHoldGraduation        = "finance:hold_graduation"
)

// fcmSendTaskType mirrors worker.TypeFCMSend — duplicated to avoid import cycle.
const fcmSendTaskType = "fcm:send"

type fcmPayload struct {
	UserID string            `json:"user_id"`
	Title  string            `json:"title"`
	Body   string            `json:"body"`
	Data   map[string]string `json:"data,omitempty"`
}

func enqueueFCM(client *asynq.Client, userID uuid.UUID, title, body string, data map[string]string) {
	if client == nil {
		return
	}
	p := fcmPayload{UserID: userID.String(), Title: title, Body: body, Data: data}
	b, _ := json.Marshal(p)
	_, _ = client.Enqueue(
		asynq.NewTask(fcmSendTaskType, b),
		asynq.MaxRetry(3),
		asynq.Timeout(10*time.Second),
		asynq.Queue("critical"),
	)
}

// smsSendTaskType mirrors worker.TypeSMSSend — duplicated to avoid import cycle.
const smsSendTaskType = "sms:send"

type smsPayload struct {
	Phone   string `json:"phone"`
	Message string `json:"message"`
}

// enqueueSMSToUser looks up the user's phone and queues an SMS. Best-effort:
// if the user has no phone or the lookup fails, we skip silently — SMS is an
// auxiliary channel and must never block the underlying action.
func enqueueSMSToUser(client *asynq.Client, db *gorm.DB, userID uuid.UUID, message string) {
	if client == nil || db == nil {
		return
	}
	var phone string
	if err := db.WithContext(context.Background()).
		Table("users").Select("phone").
		Where("id = ?", userID).
		Scan(&phone).Error; err != nil || phone == "" {
		return
	}
	p := smsPayload{Phone: phone, Message: message}
	b, _ := json.Marshal(p)
	_, _ = client.Enqueue(
		asynq.NewTask(smsSendTaskType, b),
		asynq.MaxRetry(3),
		asynq.Timeout(15*time.Second),
		asynq.Queue("default"),
	)
}

type BookingGamificationPayload struct {
	UserID    string `json:"user_id"`
	BookingID string `json:"booking_id"`
	StartsAt  string `json:"starts_at"`
}

type MatchPostGamificationPayload struct {
	UserID string `json:"user_id"`
	PostID string `json:"post_id"`
	Action string `json:"action"`
}

type ReviewGamificationPayload struct {
	UserID   string `json:"user_id"`
	ReviewID string `json:"review_id"`
}

func EnqueueBookingGamification(client *asynq.Client, userID, bookingID uuid.UUID, startsAt time.Time) error {
	data, _ := json.Marshal(BookingGamificationPayload{
		UserID:    userID.String(),
		BookingID: bookingID.String(),
		StartsAt:  startsAt.Format(time.RFC3339),
	})
	_, err := client.Enqueue(asynq.NewTask(TypeGamificationBooking, data), asynq.MaxRetry(3), asynq.Queue("default"))
	return err
}

func EnqueueMatchPostGamification(client *asynq.Client, userID, postID uuid.UUID, action string) error {
	data, _ := json.Marshal(MatchPostGamificationPayload{
		UserID: userID.String(),
		PostID: postID.String(),
		Action: action,
	})
	_, err := client.Enqueue(asynq.NewTask(TypeGamificationMatchPost, data), asynq.MaxRetry(3), asynq.Queue("default"))
	return err
}

func EnqueueReviewGamification(client *asynq.Client, userID, reviewID uuid.UUID) error {
	data, _ := json.Marshal(ReviewGamificationPayload{
		UserID:   userID.String(),
		ReviewID: reviewID.String(),
	})
	_, err := client.Enqueue(asynq.NewTask(TypeGamificationReview, data), asynq.MaxRetry(3), asynq.Queue("default"))
	return err
}
