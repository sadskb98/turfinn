package entity

import (
	"time"

	"github.com/google/uuid"
)

// PartnerFeeConfig holds the commission and payout rules for a manager.
// When ManagerID is nil the row is the global default applied to all managers
// that do not have their own config.
type PartnerFeeConfig struct {
	ID                       uuid.UUID  `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	ManagerID                *uuid.UUID `gorm:"type:uuid;uniqueIndex;column:manager_id"`
	CommissionBps            int        `gorm:"column:commission_bps;not null;default:1500"`
	PayoutMinThresholdPaisa  int64      `gorm:"column:payout_min_threshold_paisa;not null;default:50000"`
	HoldDays                 int        `gorm:"column:hold_days;not null;default:3"`
	ValidFrom                *time.Time `gorm:"column:valid_from;type:date"`
	ValidTo                  *time.Time `gorm:"column:valid_to;type:date"`
	CreatedAt                time.Time
	UpdatedAt                time.Time
}

// GatewayFeeRate stores the SSLCommerz fee rate (basis points) for each card /
// mobile-money type. Used when estimating and reconciling gateway charges.
type GatewayFeeRate struct {
	ID        uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	CardType  string    `gorm:"column:card_type;type:varchar(30);uniqueIndex;not null"`
	FeeBps    int       `gorm:"column:fee_bps;not null"`
	CreatedAt time.Time
	UpdatedAt time.Time
}

// TaxRate stores VAT / WHT rates with optional validity windows.
// Multiple rows may exist for the same tax_type when rates change over time.
type TaxRate struct {
	ID        uuid.UUID  `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	TaxType   string     `gorm:"column:tax_type;type:varchar(20);not null"`
	RateBps   int        `gorm:"column:rate_bps;not null"`
	ValidFrom *time.Time `gorm:"column:valid_from;type:date"`
	ValidTo   *time.Time `gorm:"column:valid_to;type:date"`
	CreatedAt time.Time
}
