package realtime

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"
	"github.com/rs/zerolog/log"
)

// Message is the envelope sent over the WebSocket.
type Message struct {
	Type    string          `json:"type"`    // chat_message | status_update | notification
	Channel string          `json:"channel"` // team:id | match:id | user:id
	Payload json.RawMessage `json:"payload"`
	SentAt  time.Time       `json:"sent_at"`
}

// Hub manages WebSocket connections and Redis pub/sub fan-out.
type Hub struct {
	redis *redis.Client
	conns sync.Map // map[userID string]*websocket.Conn
}

func NewHub(redis *redis.Client) *Hub {
	return &Hub{redis: redis}
}

// Register adds a connection for a user and subscribes to their personal channel.
func (h *Hub) Register(userID string, conn *websocket.Conn) {
	h.conns.Store(userID, conn)
	go h.subscribe(userID, conn)
}

// Unregister removes a connection.
func (h *Hub) Unregister(userID string) {
	h.conns.Delete(userID)
}

// Publish sends a message to a Redis channel (fan-out to all subscribers).
func (h *Hub) Publish(ctx context.Context, channel string, msg Message) error {
	msg.SentAt = time.Now()
	data, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	return h.redis.Publish(ctx, channel, data).Err()
}

// SendToUser sends a message directly to a connected user (bypasses Redis).
func (h *Hub) SendToUser(userID string, msg Message) {
	if raw, ok := h.conns.Load(userID); ok {
		conn := raw.(*websocket.Conn)
		data, _ := json.Marshal(msg)
		conn.WriteMessage(websocket.TextMessage, data) //nolint:errcheck
	}
}

// subscribe listens to the Redis channel for this user and writes messages to their WS conn.
func (h *Hub) subscribe(userID string, conn *websocket.Conn) {
	ctx := context.Background()
	channel := fmt.Sprintf("user:%s", userID)
	sub := h.redis.Subscribe(ctx, channel)
	defer sub.Close()

	ch := sub.Channel()
	for msg := range ch {
		if _, ok := h.conns.Load(userID); !ok {
			return // connection gone
		}
		if err := conn.WriteMessage(websocket.TextMessage, []byte(msg.Payload)); err != nil {
			log.Debug().Str("user", userID).Err(err).Msg("ws write error")
			return
		}
	}
}

// SubscribeChannel subscribes a user's connection to an additional Redis channel (team, match).
func (h *Hub) SubscribeChannel(ctx context.Context, userID, channel string, conn *websocket.Conn) {
	sub := h.redis.Subscribe(ctx, channel)
	go func() {
		defer sub.Close()
		ch := sub.Channel()
		for msg := range ch {
			if _, ok := h.conns.Load(userID); !ok {
				return
			}
			conn.WriteMessage(websocket.TextMessage, []byte(msg.Payload)) //nolint:errcheck
		}
	}()
}
