// Package repository defines interfaces for disputes & support data access.
package repository

import (
	"context"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
)

type DisputeRepository interface {
	// Disputes
	ListDisputes(ctx context.Context, status string, page, limit int) ([]entity.Dispute, int64, error)
	GetDispute(ctx context.Context, id uuid.UUID) (*entity.Dispute, error)
	CreateDispute(ctx context.Context, d *entity.Dispute) error
	UpdateDispute(ctx context.Context, d *entity.Dispute) error

	// Support Tickets
	ListTickets(ctx context.Context, status string, page, limit int) ([]entity.SupportTicket, int64, error)
	GetTicket(ctx context.Context, id uuid.UUID) (*entity.SupportTicket, error)
	CreateTicket(ctx context.Context, t *entity.SupportTicket) error
	UpdateTicket(ctx context.Context, t *entity.SupportTicket) error
	CreateTicketMessage(ctx context.Context, m *entity.TicketMessage) error
	ListTicketMessages(ctx context.Context, ticketID uuid.UUID) ([]entity.TicketMessage, error)

	// User Actions
	ListUserActions(ctx context.Context, userID uuid.UUID) ([]entity.UserAction, error)
	CreateUserAction(ctx context.Context, a *entity.UserAction) error
	CountWarnings(ctx context.Context, userID uuid.UUID) (int64, error)
}
