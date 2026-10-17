package service

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
	"gorm.io/gorm"
)

type FeeService struct {
	db *gorm.DB
}

func NewFeeService(db *gorm.DB) *FeeService {
	return &FeeService{db: db}
}

// GetConfig returns the fee config for the given manager. If no manager-specific
// config exists, it falls back to the global default (manager_id IS NULL).
func (s *FeeService) GetConfig(ctx context.Context, managerID uuid.UUID) (*entity.PartnerFeeConfig, error) {
	var cfg entity.PartnerFeeConfig
	err := s.db.WithContext(ctx).
		Where("manager_id = ? AND (valid_to IS NULL OR valid_to >= CURRENT_DATE)", managerID).
		Order("valid_from DESC").
		Limit(1).
		First(&cfg).Error
	if err == nil {
		return &cfg, nil
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, fmt.Errorf("fee: query manager config: %w", err)
	}

	// Fallback: global default row (manager_id IS NULL)
	if err := s.db.WithContext(ctx).
		Where("manager_id IS NULL").
		Order("valid_from DESC").
		Limit(1).
		First(&cfg).Error; err != nil {
		return nil, fmt.Errorf("fee: query global default config: %w", err)
	}
	return &cfg, nil
}

// GetGatewayRate returns the gateway fee rate for the given card type. If not
// found, it falls back to the 'other' catch-all row.
func (s *FeeService) GetGatewayRate(ctx context.Context, cardType string) (*entity.GatewayFeeRate, error) {
	var rate entity.GatewayFeeRate
	err := s.db.WithContext(ctx).
		Where("card_type = ?", cardType).
		First(&rate).Error
	if err == nil {
		return &rate, nil
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, fmt.Errorf("fee: query gateway rate for card type %q: %w", cardType, err)
	}

	// Fallback: 'other' catch-all
	if err := s.db.WithContext(ctx).
		Where("card_type = ?", "other").
		First(&rate).Error; err != nil {
		return nil, fmt.Errorf("fee: query gateway rate fallback 'other': %w", err)
	}
	return &rate, nil
}
