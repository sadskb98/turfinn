// Package entity contains pure domain structs for disputes & support.
package entity

import (
	"time"

	"github.com/google/uuid"
)

type Dispute struct {
	ID              uuid.UUID  `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	BookingID       uuid.UUID  `gorm:"column:booking_id"`
	RaisedByUserID  uuid.UUID  `gorm:"column:raised_by_user_id"`
	AgainstUserID   uuid.UUID  `gorm:"column:against_user_id"`
	Reason          string     `gorm:"column:reason"`
	Description     string     `gorm:"column:description"`
	EvidenceURLs    string     `gorm:"column:evidence_urls;type:jsonb"`
	Status          string     `gorm:"column:status"` // open, under_review, awaiting_evidence, resolved
	Resolution      string     `gorm:"column:resolution"`
	ResolvedBy      uuid.UUID  `gorm:"column:resolved_by"`
	InternalNotes   string     `gorm:"column:internal_notes"`
	CreatedAt       time.Time  `gorm:"column:created_at"`
	ResolvedAt      *time.Time `gorm:"column:resolved_at"`

	Booking  *Booking `gorm:"foreignKey:BookingID"`
	RaisedBy *User    `gorm:"foreignKey:RaisedByUserID"`
}

func (Dispute) TableName() string { return "disputes" }

type SupportTicket struct {
	ID          uuid.UUID  `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	UserID      uuid.UUID  `gorm:"column:user_id"`
	Category    string     `gorm:"column:category"`
	Subject     string     `gorm:"column:subject"`
	Description string     `gorm:"column:description"`
	Priority    string     `gorm:"column:priority"` // low, medium, high, urgent
	Status      string     `gorm:"column:status"`   // open, in_progress, waiting_reply, resolved, closed
	AssignedTo  uuid.UUID  `gorm:"column:assigned_to"`
	CreatedAt   time.Time  `gorm:"column:created_at"`
	ResolvedAt  *time.Time `gorm:"column:resolved_at"`

	User     *User           `gorm:"foreignKey:UserID"`
	Messages []TicketMessage `gorm:"foreignKey:TicketID"`
}

func (SupportTicket) TableName() string { return "support_tickets" }

type TicketMessage struct {
	ID         uuid.UUID `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	TicketID   uuid.UUID `gorm:"column:ticket_id"`
	SenderID   uuid.UUID `gorm:"column:sender_id"`
	Body       string    `gorm:"column:body"`
	IsInternal bool      `gorm:"column:is_internal"`
	CreatedAt  time.Time `gorm:"column:created_at"`

	Sender *User `gorm:"foreignKey:SenderID"`
}

func (TicketMessage) TableName() string { return "ticket_messages" }

type UserAction struct {
	ID         uuid.UUID  `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	UserID     uuid.UUID  `gorm:"column:user_id"`
	ActionType string     `gorm:"column:action_type"` // warning, suspend, ban, unban
	Reason     string     `gorm:"column:reason"`
	IssuedBy   uuid.UUID  `gorm:"column:issued_by"`
	ExpiresAt  *time.Time `gorm:"column:expires_at"`
	CreatedAt  time.Time  `gorm:"column:created_at"`

	User   *User `gorm:"foreignKey:UserID"`
	Issuer *User `gorm:"foreignKey:IssuedBy"`
}

func (UserAction) TableName() string { return "user_actions" }
