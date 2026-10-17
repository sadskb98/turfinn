package worker

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/hibiken/asynq"
	"github.com/rs/zerolog/log"
	"github.com/spf13/viper"
)

const TypeSMSSend = "sms:send"

// SMSPayload holds the phone number and message text for an outbound SMS.
type SMSPayload struct {
	Phone   string `json:"phone"`
	Message string `json:"message"`
}

// EnqueueSMS enqueues an SMS task onto the default asynq queue.
func EnqueueSMS(client *asynq.Client, phone, message string) error {
	data, err := json.Marshal(SMSPayload{Phone: phone, Message: message})
	if err != nil {
		return fmt.Errorf("marshal sms payload: %w", err)
	}
	task := asynq.NewTask(TypeSMSSend, data,
		asynq.MaxRetry(3),
		asynq.Timeout(15*time.Second),
		asynq.Queue("default"),
	)
	if _, err = client.Enqueue(task); err != nil {
		return fmt.Errorf("enqueue sms task: %w", err)
	}
	return nil
}

// SMSWorker handles sms:send tasks via the SSL Wireless API.
type SMSWorker struct{}

func NewSMSWorker() *SMSWorker { return &SMSWorker{} }

func (w *SMSWorker) Handle(ctx context.Context, t *asynq.Task) error {
	var p SMSPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("decode sms payload: %w", err)
	}

	apiUser := viper.GetString("SMS_API_USER")
	apiPass := viper.GetString("SMS_API_PASS")
	apiSID := viper.GetString("SMS_SID")

	if apiUser == "" || apiPass == "" || apiSID == "" {
		log.Warn().Str("phone", p.Phone).Msg("SMS credentials not configured — skipping SMS send")
		return nil
	}

	payload := map[string]string{
		"username": apiUser,
		"password": apiPass,
		"sid":      apiSID,
		"msisdn":   p.Phone,
		"smstext":  p.Message,
		"csmsid":   "",
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal ssl wireless request: %w", err)
	}

	httpClient := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"https://api.sslwireless.com/api/v3/send-sms", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create ssl wireless request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("ssl wireless http send: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("ssl wireless returned status %d", resp.StatusCode)
	}

	log.Info().Str("phone", p.Phone).Msg("SMS sent via SSL Wireless")
	return nil
}
