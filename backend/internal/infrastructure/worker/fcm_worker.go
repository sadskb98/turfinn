package worker

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/rs/zerolog/log"
	"github.com/spf13/viper"
	"golang.org/x/oauth2/google"
	"gorm.io/gorm"

	"github.com/turfinn/backend/internal/domain/entity"
)

const TypeFCMSend = "fcm:send"

// Keep the old TypeFCMPush alias so existing registrations don't break.
const TypeFCMPush = TypeFCMSend

type FCMPayload struct {
	UserID uuid.UUID         `json:"user_id"`
	Title  string            `json:"title"`
	Body   string            `json:"body"`
	Data   map[string]string `json:"data,omitempty"`
}

// FCMPushPayload is kept for backwards compatibility with EnqueueFCMPush.
type FCMPushPayload = FCMPayload

func EnqueueFCM(client *asynq.Client, p FCMPayload) error {
	data, err := json.Marshal(p)
	if err != nil {
		return fmt.Errorf("marshal fcm payload: %w", err)
	}
	task := asynq.NewTask(TypeFCMSend, data,
		asynq.MaxRetry(3),
		asynq.Timeout(10*time.Second),
		asynq.Queue("critical"),
	)
	if _, err = client.Enqueue(task); err != nil {
		return fmt.Errorf("enqueue fcm task: %w", err)
	}
	return nil
}

// EnqueueFCMPush is kept for backwards compatibility.
func EnqueueFCMPush(client *asynq.Client, p FCMPayload) error {
	return EnqueueFCM(client, p)
}

type FCMWorker struct{ db *gorm.DB }

func NewFCMWorker(db *gorm.DB) *FCMWorker { return &FCMWorker{db: db} }

func (w *FCMWorker) Handle(ctx context.Context, t *asynq.Task) error {
	var p FCMPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("decode fcm payload: %w", err)
	}

	var user entity.User
	if err := w.db.WithContext(ctx).Select("fcm_token").
		Where("id = ?", p.UserID).First(&user).Error; err != nil {
		return fmt.Errorf("find user: %w", err)
	}
	if user.FCMToken == nil || *user.FCMToken == "" {
		log.Debug().Str("user_id", p.UserID.String()).Msg("no FCM token, skipping")
		return nil
	}

	projectID, accessToken, err := w.fcmAuth(ctx)
	if err != nil {
		return fmt.Errorf("fcm auth: %w", err)
	}

	msg := map[string]any{
		"message": map[string]any{
			"token": *user.FCMToken,
			"notification": map[string]string{
				"title": p.Title,
				"body":  p.Body,
			},
			"data": p.Data,
		},
	}
	body, _ := json.Marshal(msg)
	url := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", projectID)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("fcm http send: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return fmt.Errorf("fcm returned status %d", resp.StatusCode)
	}

	log.Info().Str("user_id", p.UserID.String()).Str("title", p.Title).Msg("FCM notification sent")
	return nil
}

func (w *FCMWorker) fcmAuth(ctx context.Context) (projectID, accessToken string, err error) {
	saJSON := viper.GetString("FIREBASE_SERVICE_ACCOUNT_JSON")
	if saJSON == "" {
		return "", "", fmt.Errorf("FIREBASE_SERVICE_ACCOUNT_JSON not set")
	}
	cfg, err := google.CredentialsFromJSON(ctx, []byte(saJSON),
		"https://www.googleapis.com/auth/firebase.messaging")
	if err != nil {
		return "", "", fmt.Errorf("parse service account: %w", err)
	}
	token, err := cfg.TokenSource.Token()
	if err != nil {
		return "", "", fmt.Errorf("get access token: %w", err)
	}
	var sa struct {
		ProjectID string `json:"project_id"`
	}
	_ = json.NewDecoder(strings.NewReader(saJSON)).Decode(&sa)
	return sa.ProjectID, token.AccessToken, nil
}
