// Package entity contains pure domain structs for finance & audit.
package entity

import (
	"time"

	"github.com/google/uuid"
)

type AuditLog struct {
	ID         int64     `gorm:"primaryKey;autoIncrement"`
	ActorID    uuid.UUID `gorm:"column:actor_id"`
	ActorRole  string    `gorm:"column:actor_role"`
	Action     string    `gorm:"column:action"`
	EntityType string    `gorm:"column:entity_type"`
	EntityID   string    `gorm:"column:entity_id"`
	OldValue   string    `gorm:"column:old_value;type:jsonb"`
	NewValue   string    `gorm:"column:new_value;type:jsonb"`
	IPAddress  string    `gorm:"column:ip_address"`
	UserAgent  string    `gorm:"column:user_agent"`
	CreatedAt  time.Time `gorm:"column:created_at"`
}

func (AuditLog) TableName() string { return "audit_log" }

type LedgerEntry struct {
	ID                uuid.UUID `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	TransactionRef    string    `gorm:"column:transaction_ref"`
	EntryType         string    `gorm:"column:entry_type"`
	DebitAccount      string    `gorm:"column:debit_account"`
	CreditAccount     string    `gorm:"column:credit_account"`
	AmountPaisa       int64     `gorm:"column:amount_paisa"`
	Description       string    `gorm:"column:description"`
	RelatedEntityType string    `gorm:"column:related_entity_type"`
	RelatedEntityID   uuid.UUID `gorm:"column:related_entity_id"`
	CreatedAt         time.Time `gorm:"column:created_at"`
}

func (LedgerEntry) TableName() string { return "ledger_entries" }

type FraudFlag struct {
	ID         uuid.UUID `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	EntityType string    `gorm:"column:entity_type"`
	EntityID   uuid.UUID `gorm:"column:entity_id"`
	FlagType   string    `gorm:"column:flag_type"`
	Details    string    `gorm:"column:details;type:jsonb"`
	Status     string    `gorm:"column:status"` // active, dismissed, escalated
	ReviewedBy uuid.UUID `gorm:"column:reviewed_by"`
	CreatedAt  time.Time `gorm:"column:created_at"`
}

func (FraudFlag) TableName() string { return "fraud_flags" }
