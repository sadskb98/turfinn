// Package entity contains pure domain structs for platform configuration.
package entity

import (
	"time"

	"github.com/google/uuid"
)

type PlatformSetting struct {
	Key         string    `gorm:"primaryKey;column:key"`
	Value       string    `gorm:"column:value"`
	Description string    `gorm:"column:description"`
	UpdatedBy   uuid.UUID `gorm:"column:updated_by"`
	UpdatedAt   time.Time `gorm:"column:updated_at"`
}

func (PlatformSetting) TableName() string { return "platform_settings" }

type PlatformSettingsAudit struct {
	ID         uuid.UUID `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	SettingKey string    `gorm:"column:setting_key"`
	OldValue   string    `gorm:"column:old_value"`
	NewValue   string    `gorm:"column:new_value"`
	ChangedBy  uuid.UUID `gorm:"column:changed_by"`
	ChangedAt  time.Time `gorm:"column:changed_at"`
}

func (PlatformSettingsAudit) TableName() string { return "platform_settings_audit" }

type PricingRule struct {
	ID            uuid.UUID  `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	RuleType      string     `gorm:"column:rule_type"`
	Name          string     `gorm:"column:name"`
	Multiplier    float64    `gorm:"column:multiplier"`
	FixedAmount   float64    `gorm:"column:fixed_amount"`
	AppliesToDays string     `gorm:"column:applies_to_days;type:jsonb"` // JSON array of day numbers
	TimeFrom      string     `gorm:"column:time_from"`
	TimeTo        string     `gorm:"column:time_to"`
	IsActive      bool       `gorm:"column:is_active"`
	OwnerID       *uuid.UUID `gorm:"column:owner_id;type:uuid"`  // NULL = platform-wide rule
	PitchID       *uuid.UUID `gorm:"column:pitch_id;type:uuid"`  // NULL = applies to all owner pitches
	CreatedBy     uuid.UUID  `gorm:"column:created_by"`
	CreatedAt     time.Time  `gorm:"column:created_at"`
	UpdatedAt     time.Time  `gorm:"column:updated_at"`
}

func (PricingRule) TableName() string { return "pricing_rules" }

type FeatureFlag struct {
	Key         string    `gorm:"primaryKey;column:key"`
	Enabled     bool      `gorm:"column:enabled"`
	Description string    `gorm:"column:description"`
	UpdatedBy   uuid.UUID `gorm:"column:updated_by"`
	UpdatedAt   time.Time `gorm:"column:updated_at"`
}

func (FeatureFlag) TableName() string { return "feature_flags" }

type NotificationTemplate struct {
	ID        uuid.UUID `gorm:"primaryKey;type:uuid;default:gen_random_uuid()"`
	Type      string    `gorm:"column:type"`
	Channel   string    `gorm:"column:channel"`
	Subject   string    `gorm:"column:subject"`
	Body      string    `gorm:"column:body"`
	Variables string    `gorm:"column:variables;type:jsonb"`
	IsActive  bool      `gorm:"column:is_active"`
	CreatedAt time.Time `gorm:"column:created_at"`
	UpdatedAt time.Time `gorm:"column:updated_at"`
}

func (NotificationTemplate) TableName() string { return "notification_templates" }
