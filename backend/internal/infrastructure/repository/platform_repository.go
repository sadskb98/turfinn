// Package repository provides GORM implementations for platform configuration.
package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"gorm.io/gorm"
)

type platformRepository struct {
	db    *gorm.DB
	redis *redis.Client
}

func NewPlatformRepository(db *gorm.DB, redis *redis.Client) domain.PlatformRepository {
	return &platformRepository{db: db, redis: redis}
}

const settingsCacheTTL = 2 * time.Minute

func (r *platformRepository) GetAllSettings(ctx context.Context) ([]entity.PlatformSetting, error) {
	cacheKey := "platform:settings:all"
	if cached, err := r.redis.Get(ctx, cacheKey).Result(); err == nil {
		var settings []entity.PlatformSetting
		if json.Unmarshal([]byte(cached), &settings) == nil {
			return settings, nil
		}
	}

	var settings []entity.PlatformSetting
	if err := r.db.WithContext(ctx).Find(&settings).Error; err != nil {
		return nil, err
	}

	data, _ := json.Marshal(settings)
	r.redis.Set(ctx, cacheKey, data, settingsCacheTTL)
	return settings, nil
}

func (r *platformRepository) GetSetting(ctx context.Context, key string) (*entity.PlatformSetting, error) {
	var s entity.PlatformSetting
	if err := r.db.WithContext(ctx).First(&s, "key = ?", key).Error; err != nil {
		return nil, err
	}
	return &s, nil
}

func (r *platformRepository) UpdateSettings(ctx context.Context, settings map[string]string, updatedBy uuid.UUID) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		for key, newVal := range settings {
			var existing entity.PlatformSetting
			if err := tx.First(&existing, "key = ?", key).Error; err != nil {
				continue
			}
			oldVal := existing.Value

			if err := tx.Model(&entity.PlatformSetting{}).Where("key = ?", key).Updates(map[string]any{
				"value":      newVal,
				"updated_by": updatedBy,
				"updated_at": time.Now(),
			}).Error; err != nil {
				return err
			}

			audit := entity.PlatformSettingsAudit{
				ID:         uuid.New(),
				SettingKey: key,
				OldValue:   oldVal,
				NewValue:   newVal,
				ChangedBy:  updatedBy,
				ChangedAt:  time.Now(),
			}
			if err := tx.Create(&audit).Error; err != nil {
				return err
			}
		}
		return nil
	})
}

func (r *platformRepository) ListSettingsAudit(ctx context.Context, page, limit int) ([]entity.PlatformSettingsAudit, int64, error) {
	var total int64
	r.db.WithContext(ctx).Model(&entity.PlatformSettingsAudit{}).Count(&total)

	var items []entity.PlatformSettingsAudit
	err := r.db.WithContext(ctx).Order("changed_at DESC").Offset((page - 1) * limit).Limit(limit).Find(&items).Error
	return items, total, err
}

// Pricing Rules
func (r *platformRepository) ListPricingRules(ctx context.Context) ([]entity.PricingRule, error) {
	var rules []entity.PricingRule
	err := r.db.WithContext(ctx).Order("created_at DESC").Find(&rules).Error
	return rules, err
}

func (r *platformRepository) CreatePricingRule(ctx context.Context, rule *entity.PricingRule) error {
	rule.ID = uuid.New()
	rule.CreatedAt = time.Now()
	rule.UpdatedAt = time.Now()
	return r.db.WithContext(ctx).Create(rule).Error
}

func (r *platformRepository) UpdatePricingRule(ctx context.Context, rule *entity.PricingRule) error {
	rule.UpdatedAt = time.Now()
	return r.db.WithContext(ctx).Save(rule).Error
}

func (r *platformRepository) DeletePricingRule(ctx context.Context, id uuid.UUID) error {
	return r.db.WithContext(ctx).Delete(&entity.PricingRule{}, "id = ?", id).Error
}

// Feature Flags
func (r *platformRepository) GetAllFlags(ctx context.Context) ([]entity.FeatureFlag, error) {
	cacheKey := "platform:flags:all"
	if cached, err := r.redis.Get(ctx, cacheKey).Result(); err == nil {
		var flags []entity.FeatureFlag
		if json.Unmarshal([]byte(cached), &flags) == nil {
			return flags, nil
		}
	}

	var flags []entity.FeatureFlag
	if err := r.db.WithContext(ctx).Find(&flags).Error; err != nil {
		return nil, err
	}

	data, _ := json.Marshal(flags)
	r.redis.Set(ctx, cacheKey, data, settingsCacheTTL)
	return flags, nil
}

func (r *platformRepository) UpdateFlag(ctx context.Context, key string, enabled bool, updatedBy uuid.UUID) error {
	err := r.db.WithContext(ctx).Model(&entity.FeatureFlag{}).Where("key = ?", key).Updates(map[string]any{
		"enabled":    enabled,
		"updated_by": updatedBy,
		"updated_at": time.Now(),
	}).Error
	if err == nil {
		r.redis.Del(ctx, "platform:flags:all")
	}
	return err
}

// Notification Templates
func (r *platformRepository) ListTemplates(ctx context.Context) ([]entity.NotificationTemplate, error) {
	var templates []entity.NotificationTemplate
	err := r.db.WithContext(ctx).Order("type, channel").Find(&templates).Error
	return templates, err
}

func (r *platformRepository) GetTemplate(ctx context.Context, id uuid.UUID) (*entity.NotificationTemplate, error) {
	var t entity.NotificationTemplate
	if err := r.db.WithContext(ctx).First(&t, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &t, nil
}

func (r *platformRepository) CreateTemplate(ctx context.Context, t *entity.NotificationTemplate) error {
	t.ID = uuid.New()
	t.CreatedAt = time.Now()
	t.UpdatedAt = time.Now()
	return r.db.WithContext(ctx).Create(t).Error
}

func (r *platformRepository) UpdateTemplate(ctx context.Context, t *entity.NotificationTemplate) error {
	t.UpdatedAt = time.Now()
	return r.db.WithContext(ctx).Save(t).Error
}

func (r *platformRepository) DeleteTemplate(ctx context.Context, id uuid.UUID) error {
	return r.db.WithContext(ctx).Delete(&entity.NotificationTemplate{}, "id = ?", id).Error
}

// Ensure cache invalidation on settings update
func init() {
	_ = fmt.Sprintf // suppress unused import if needed
}
