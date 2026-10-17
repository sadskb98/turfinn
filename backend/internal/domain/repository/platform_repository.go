// Package repository defines interfaces for platform configuration data access.
package repository

import (
	"context"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
)

type PlatformRepository interface {
	// Settings
	GetAllSettings(ctx context.Context) ([]entity.PlatformSetting, error)
	GetSetting(ctx context.Context, key string) (*entity.PlatformSetting, error)
	UpdateSettings(ctx context.Context, settings map[string]string, updatedBy uuid.UUID) error
	ListSettingsAudit(ctx context.Context, page, limit int) ([]entity.PlatformSettingsAudit, int64, error)

	// Pricing Rules
	ListPricingRules(ctx context.Context) ([]entity.PricingRule, error)
	CreatePricingRule(ctx context.Context, rule *entity.PricingRule) error
	UpdatePricingRule(ctx context.Context, rule *entity.PricingRule) error
	DeletePricingRule(ctx context.Context, id uuid.UUID) error

	// Feature Flags
	GetAllFlags(ctx context.Context) ([]entity.FeatureFlag, error)
	UpdateFlag(ctx context.Context, key string, enabled bool, updatedBy uuid.UUID) error

	// Notification Templates
	ListTemplates(ctx context.Context) ([]entity.NotificationTemplate, error)
	GetTemplate(ctx context.Context, id uuid.UUID) (*entity.NotificationTemplate, error)
	CreateTemplate(ctx context.Context, t *entity.NotificationTemplate) error
	UpdateTemplate(ctx context.Context, t *entity.NotificationTemplate) error
	DeleteTemplate(ctx context.Context, id uuid.UUID) error
}
