// Package repository provides GORM implementations for disputes & support.
package repository

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"gorm.io/gorm"
)

type disputeRepository struct {
	db    *gorm.DB
	redis *redis.Client
}

func NewDisputeRepository(db *gorm.DB, redis *redis.Client) domain.DisputeRepository {
	return &disputeRepository{db: db, redis: redis}
}

// ── Disputes ─────────────────────────────────────────────────────────────────

func (r *disputeRepository) ListDisputes(ctx context.Context, status string, page, limit int) ([]entity.Dispute, int64, error) {
	var total int64
	q := r.db.WithContext(ctx).Model(&entity.Dispute{})
	if status != "" {
		q = q.Where("status = ?", status)
	}
	q.Count(&total)

	var items []entity.Dispute
	err := q.Preload("Booking").Preload("RaisedBy").Order("created_at DESC").
		Offset((page - 1) * limit).Limit(limit).Find(&items).Error
	return items, total, err
}

func (r *disputeRepository) GetDispute(ctx context.Context, id uuid.UUID) (*entity.Dispute, error) {
	var d entity.Dispute
	if err := r.db.WithContext(ctx).Preload("Booking").Preload("RaisedBy").First(&d, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &d, nil
}

func (r *disputeRepository) CreateDispute(ctx context.Context, d *entity.Dispute) error {
	d.ID = uuid.New()
	d.CreatedAt = time.Now()
	return r.db.WithContext(ctx).Create(d).Error
}

func (r *disputeRepository) UpdateDispute(ctx context.Context, d *entity.Dispute) error {
	return r.db.WithContext(ctx).Save(d).Error
}

// ── Support Tickets ──────────────────────────────────────────────────────────

func (r *disputeRepository) ListTickets(ctx context.Context, status string, page, limit int) ([]entity.SupportTicket, int64, error) {
	var total int64
	q := r.db.WithContext(ctx).Model(&entity.SupportTicket{})
	if status != "" {
		q = q.Where("status = ?", status)
	}
	q.Count(&total)

	var items []entity.SupportTicket
	err := q.Preload("User").Order("created_at DESC").
		Offset((page - 1) * limit).Limit(limit).Find(&items).Error
	return items, total, err
}

func (r *disputeRepository) GetTicket(ctx context.Context, id uuid.UUID) (*entity.SupportTicket, error) {
	var t entity.SupportTicket
	if err := r.db.WithContext(ctx).Preload("User").Preload("Messages").Preload("Messages.Sender").
		First(&t, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &t, nil
}

func (r *disputeRepository) CreateTicket(ctx context.Context, t *entity.SupportTicket) error {
	t.ID = uuid.New()
	t.CreatedAt = time.Now()
	return r.db.WithContext(ctx).Create(t).Error
}

func (r *disputeRepository) UpdateTicket(ctx context.Context, t *entity.SupportTicket) error {
	return r.db.WithContext(ctx).Save(t).Error
}

func (r *disputeRepository) CreateTicketMessage(ctx context.Context, m *entity.TicketMessage) error {
	m.ID = uuid.New()
	m.CreatedAt = time.Now()
	return r.db.WithContext(ctx).Create(m).Error
}

func (r *disputeRepository) ListTicketMessages(ctx context.Context, ticketID uuid.UUID) ([]entity.TicketMessage, error) {
	var items []entity.TicketMessage
	err := r.db.WithContext(ctx).Preload("Sender").Where("ticket_id = ?", ticketID).Order("created_at ASC").Find(&items).Error
	return items, err
}

// ── User Actions ─────────────────────────────────────────────────────────────

func (r *disputeRepository) ListUserActions(ctx context.Context, userID uuid.UUID) ([]entity.UserAction, error) {
	var items []entity.UserAction
	err := r.db.WithContext(ctx).Preload("Issuer").Where("user_id = ?", userID).Order("created_at DESC").Find(&items).Error
	return items, err
}

func (r *disputeRepository) CreateUserAction(ctx context.Context, a *entity.UserAction) error {
	a.ID = uuid.New()
	a.CreatedAt = time.Now()
	return r.db.WithContext(ctx).Create(a).Error
}

func (r *disputeRepository) CountWarnings(ctx context.Context, userID uuid.UUID) (int64, error) {
	var count int64
	err := r.db.WithContext(ctx).Model(&entity.UserAction{}).Where("user_id = ? AND action_type = 'warning'", userID).Count(&count).Error
	return count, err
}
