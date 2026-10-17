package service

import (
	"context"
	"fmt"

	"github.com/turfinn/backend/internal/domain/entity"
	"gorm.io/gorm"
)

type TaxService struct {
	db *gorm.DB
}

func NewTaxService(db *gorm.DB) *TaxService {
	return &TaxService{db: db}
}

// GetRate returns the currently active tax rate for the given tax type.
// "Active" means valid_to is NULL or >= NOW(), ordered by valid_from DESC so the
// most recently started rate wins when multiple rows overlap.
func (s *TaxService) GetRate(ctx context.Context, taxType string) (*entity.TaxRate, error) {
	var rate entity.TaxRate
	// Include rates with bounded validity windows (valid_to set) as well as open-ended ones.
	if err := s.db.WithContext(ctx).
		Where("tax_type = ? AND (valid_to IS NULL OR valid_to >= NOW())", taxType).
		Order("valid_from DESC").
		Limit(1).
		First(&rate).Error; err != nil {
		return nil, fmt.Errorf("tax: query active rate for type %q: %w", taxType, err)
	}
	return &rate, nil
}
