package handler

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/labstack/echo/v4"
	"github.com/rs/zerolog/log"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/infrastructure/realtime"
	jwtpkg "github.com/turfinn/backend/internal/pkg/jwt"
	"github.com/turfinn/backend/internal/pkg/response"
	"gorm.io/gorm"
)

var upgrader = websocket.Upgrader{
	CheckOrigin:     func(r *http.Request) bool { return true },
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
}

type clientMessage struct {
	Type    string          `json:"type"`    // join_channel | chat_message
	Channel string          `json:"channel"` // team:id | match:id
	Payload json.RawMessage `json:"payload"`
}

type chatPayload struct {
	Content string `json:"content"`
}

type WSHandler struct {
	hub *realtime.Hub
	db  *gorm.DB
}

func NewWSHandler(hub *realtime.Hub, db *gorm.DB) *WSHandler {
	return &WSHandler{hub: hub, db: db}
}

// Connect handles GET /ws?token=<jwt>
func (h *WSHandler) Connect(c echo.Context) error {
	token := c.QueryParam("token")
	claims, err := jwtpkg.Parse(token)
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
	}
	userID := claims.UserID

	conn, err := upgrader.Upgrade(c.Response(), c.Request(), nil)
	if err != nil {
		return err
	}
	defer func() {
		h.hub.Unregister(userID.String())
		conn.Close()
	}()

	h.hub.Register(userID.String(), conn)
	log.Debug().Str("user", userID.String()).Msg("ws connected")

	for {
		_, raw, err := conn.ReadMessage()
		if err != nil {
			break
		}
		var msg clientMessage
		if err := json.Unmarshal(raw, &msg); err != nil {
			continue
		}

		switch msg.Type {
		case "join_channel":
			h.hub.SubscribeChannel(c.Request().Context(), userID.String(), msg.Channel, conn)

		case "chat_message":
			var p chatPayload
			if err := json.Unmarshal(msg.Payload, &p); err != nil || p.Content == "" {
				continue
			}
			if err := h.handleChat(c.Request().Context(), userID, msg.Channel, p.Content); err != nil {
				log.Warn().Err(err).Msg("chat message error")
			}
		}
	}
	return nil
}

func (h *WSHandler) handleChat(ctx context.Context, senderID uuid.UUID, channel, content string) error {
	switch {
	case len(channel) > 5 && channel[:5] == "team:":
		teamID, err := uuid.Parse(channel[5:])
		if err != nil {
			return nil
		}
		msg := entity.ChatMessage{TeamID: teamID, SenderID: senderID, Content: content}
		if err := h.db.Create(&msg).Error; err != nil {
			return err
		}
		payload, _ := json.Marshal(map[string]any{
			"id": msg.ID.String(), "sender_id": senderID.String(),
			"content": content, "sent_at": msg.SentAt,
		})
		return h.hub.Publish(context.Background(), channel, realtime.Message{
			Type: "chat_message", Channel: channel, Payload: payload,
		})

	case len(channel) > 6 && channel[:6] == "match:":
		matchID, err := uuid.Parse(channel[6:])
		if err != nil {
			return nil
		}
		msg := entity.MatchChatMessage{MatchID: matchID, SenderID: senderID, Content: content}
		if err := h.db.Create(&msg).Error; err != nil {
			return err
		}
		payload, _ := json.Marshal(map[string]any{
			"id": msg.ID.String(), "sender_id": senderID.String(),
			"content": content, "sent_at": msg.SentAt,
		})
		return h.hub.Publish(context.Background(), channel, realtime.Message{
			Type: "chat_message", Channel: channel, Payload: payload,
		})
	}
	return nil
}

// ListMatchMessages handles GET /api/v1/matchmaking/:id/messages?before=<sent_at>
func (h *WSHandler) ListMatchMessages(c echo.Context) error {
	matchID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid match id")
	}

	query := h.db.WithContext(c.Request().Context()).
		Where("match_id = ?", matchID).
		Order("sent_at DESC").
		Limit(50)

	if before := c.QueryParam("before"); before != "" {
		query = query.Where("sent_at < ?", before)
	}

	var msgs []entity.MatchChatMessage
	if err := query.Preload("Sender").Find(&msgs).Error; err != nil {
		return response.InternalError(c)
	}

	type msgResponse struct {
		ID         string `json:"id"`
		SenderID   string `json:"sender_id"`
		SenderName string `json:"sender_name"`
		Content    string `json:"content"`
		SentAt     string `json:"sent_at"`
	}
	out := make([]msgResponse, 0, len(msgs))
	for _, m := range msgs {
		name := ""
		if m.Sender != nil {
			name = m.Sender.Name
		}
		out = append(out, msgResponse{
			ID:         m.ID.String(),
			SenderID:   m.SenderID.String(),
			SenderName: name,
			Content:    m.Content,
			SentAt:     m.SentAt.Format("2006-01-02T15:04:05Z"),
		})
	}
	return response.OK(c, out)
}

// ListMessages handles GET /api/v1/teams/:id/messages?before=<sent_at>&limit=50
func (h *WSHandler) ListMessages(c echo.Context) error {
	teamID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return response.BadRequest(c, "invalid team id")
	}

	query := h.db.WithContext(c.Request().Context()).
		Where("team_id = ?", teamID).
		Order("sent_at DESC").
		Limit(50)

	if before := c.QueryParam("before"); before != "" {
		query = query.Where("sent_at < ?", before)
	}

	var msgs []entity.ChatMessage
	if err := query.Preload("Sender").Find(&msgs).Error; err != nil {
		return response.InternalError(c)
	}

	type msgResponse struct {
		ID         string `json:"id"`
		SenderID   string `json:"sender_id"`
		SenderName string `json:"sender_name"`
		Content    string `json:"content"`
		SentAt     string `json:"sent_at"`
	}
	out := make([]msgResponse, 0, len(msgs))
	for _, m := range msgs {
		name := ""
		if m.Sender != nil {
			name = m.Sender.Name
		}
		out = append(out, msgResponse{
			ID:         m.ID.String(),
			SenderID:   m.SenderID.String(),
			SenderName: name,
			Content:    m.Content,
			SentAt:     m.SentAt.Format("2006-01-02T15:04:05Z"),
		})
	}
	return response.OK(c, out)
}
