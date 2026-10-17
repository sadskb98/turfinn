package worker

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/hibiken/asynq"
	"github.com/rs/zerolog/log"
)

const TypeReferralReward = "user:referral_reward"

type ReferralRewardPayload struct {
	ReferrerUserID string `json:"referrer_user_id"`
	NewUserID      string `json:"new_user_id"`
}

// EnqueueReferralReward enqueues a referral reward task.
func EnqueueReferralReward(client *asynq.Client, p ReferralRewardPayload) error {
	data, err := json.Marshal(p)
	if err != nil {
		return fmt.Errorf("marshal referral payload: %w", err)
	}
	task := asynq.NewTask(TypeReferralReward, data)
	_, err = client.Enqueue(task, asynq.MaxRetry(3), asynq.Queue("default"))
	return err
}

// HandleReferralReward processes a referral reward task.
func HandleReferralReward(ctx context.Context, t *asynq.Task) error {
	var p ReferralRewardPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("unmarshal referral payload: %w", err)
	}
	log.Info().
		Str("referrer_id", p.ReferrerUserID).
		Str("new_user_id", p.NewUserID).
		Msg("processing referral reward")
	// TODO: credit referrer's account in a future wave
	return nil
}
