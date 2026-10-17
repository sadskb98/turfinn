package service

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
	"gorm.io/gorm"
)

type WalletService struct {
	db *gorm.DB
}

func NewWalletService(db *gorm.DB) *WalletService {
	return &WalletService{db: db}
}

func (s *WalletService) GetOrCreateWallet(ctx context.Context, userID uuid.UUID) (*entity.Wallet, error) {
	var wallet entity.Wallet
	err := s.db.WithContext(ctx).Where("user_id = ?", userID).First(&wallet).Error
	if err == gorm.ErrRecordNotFound {
		wallet = entity.Wallet{UserID: userID, Balance: 0}
		if err := s.db.WithContext(ctx).Create(&wallet).Error; err != nil {
			return nil, err
		}
	} else if err != nil {
		return nil, err
	}
	return &wallet, nil
}

func (s *WalletService) GetBalance(ctx context.Context, userID uuid.UUID) (int, error) {
	w, err := s.GetOrCreateWallet(ctx, userID)
	if err != nil {
		return 0, err
	}
	return w.Balance, nil
}

func (s *WalletService) TopUp(ctx context.Context, userID uuid.UUID, amount int) error {
	if amount <= 0 {
		return fmt.Errorf("amount must be positive")
	}
	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var wallet entity.Wallet
		if err := tx.Where("user_id = ?", userID).First(&wallet).Error; err != nil {
			return err
		}
		wallet.Balance += amount
		if err := tx.Save(&wallet).Error; err != nil {
			return err
		}
		return tx.Create(&entity.WalletTransaction{
			WalletID: wallet.ID,
			Amount:   amount,
			Type:     "topup",
		}).Error
	})
}

// CreditCoins adds coins to user's wallet with a transaction record.
func (s *WalletService) CreditCoins(ctx context.Context, userID uuid.UUID, amount int, txType, reference string) error {
	if amount <= 0 {
		return nil
	}
	w, err := s.GetOrCreateWallet(ctx, userID)
	if err != nil {
		return err
	}
	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&entity.Wallet{}).Where("id = ?", w.ID).
			Update("balance", gorm.Expr("balance + ?", amount)).Error; err != nil {
			return err
		}
		return tx.Create(&entity.WalletTransaction{
			WalletID:  w.ID,
			Amount:    amount,
			Type:      txType,
			Reference: reference,
		}).Error
	})
}

// DebitCoins removes coins from user's wallet with a transaction record.
func (s *WalletService) DebitCoins(ctx context.Context, userID uuid.UUID, amount int, txType, reference string) error {
	if amount <= 0 {
		return nil
	}
	w, err := s.GetOrCreateWallet(ctx, userID)
	if err != nil {
		return err
	}
	if w.Balance < amount {
		return fmt.Errorf("insufficient balance")
	}
	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&entity.Wallet{}).Where("id = ? AND balance >= ?", w.ID, amount).
			Update("balance", gorm.Expr("balance - ?", amount)).Error; err != nil {
			return err
		}
		return tx.Create(&entity.WalletTransaction{
			WalletID:  w.ID,
			Amount:    -amount,
			Type:      txType,
			Reference: reference,
		}).Error
	})
}

func (s *WalletService) ListTransactions(ctx context.Context, userID uuid.UUID, page, limit int) ([]entity.WalletTransaction, int64, error) {
	w, err := s.GetOrCreateWallet(ctx, userID)
	if err != nil {
		return nil, 0, err
	}
	var txs []entity.WalletTransaction
	var total int64
	q := s.db.WithContext(ctx).Model(&entity.WalletTransaction{}).Where("wallet_id = ?", w.ID).Order("created_at DESC")
	countQ := q.Session(&gorm.Session{})
	if err := countQ.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	if err := q.Offset((page-1)*limit).Limit(limit).Find(&txs).Error; err != nil {
		return nil, 0, err
	}
	return txs, total, nil
}

func (s *WalletService) GetProfile(ctx context.Context, userID uuid.UUID) (map[string]interface{}, error) {
	var user entity.User
	if err := s.db.WithContext(ctx).First(&user, "id = ?", userID).Error; err != nil {
		return nil, err
	}

	var bookingCount int64
	s.db.WithContext(ctx).Model(&entity.Booking{}).Where("user_id = ? AND status = 'confirmed'", userID).Count(&bookingCount)

	balance, _ := s.GetBalance(ctx, userID)

	var badges []entity.UserBadge
	s.db.WithContext(ctx).Preload("Badge").Where("user_id = ?", userID).Find(&badges)

	badgeList := make([]map[string]interface{}, len(badges))
	for i, ub := range badges {
		badgeList[i] = map[string]interface{}{
			"key":         ub.Badge.Key,
			"name":        ub.Badge.Name,
			"description": ub.Badge.Description,
			"earned_at":   ub.EarnedAt,
		}
	}

	name := user.Name
	phone := ""
	if user.Phone != nil {
		phone = *user.Phone
	}

	return map[string]interface{}{
		"id":             user.ID,
		"name":           name,
		"phone":          phone,
		"role":           user.Role,
		"coins_balance":  balance,
		"total_bookings": bookingCount,
		"badges":         badgeList,
	}, nil
}

// AwardBadge awards a badge to the user if they don't already have it.
// Returns true if newly awarded, false if already had it.
func (s *WalletService) AwardBadge(ctx context.Context, userID uuid.UUID, badgeKey string) (bool, error) {
	// 1. Find the badge by key
	var badge entity.Badge
	if err := s.db.WithContext(ctx).Where("key = ?", badgeKey).First(&badge).Error; err != nil {
		return false, nil // badge doesn't exist, skip silently
	}

	// 2. Check if user already has it
	var count int64
	s.db.WithContext(ctx).Model(&entity.UserBadge{}).
		Where("user_id = ? AND badge_id = ?", userID, badge.ID).
		Count(&count)
	if count > 0 {
		return false, nil // already awarded
	}

	// 3. Award badge + credit coins in a transaction
	return true, s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Insert user_badge
		ub := entity.UserBadge{UserID: userID, BadgeID: badge.ID}
		if err := tx.Create(&ub).Error; err != nil {
			return err
		}

		// Credit coins if badge has a reward
		if badge.CoinsReward > 0 {
			var wallet entity.Wallet
			err := tx.Where("user_id = ?", userID).First(&wallet).Error
			if err == gorm.ErrRecordNotFound {
				wallet = entity.Wallet{UserID: userID, Balance: 0}
				if err := tx.Create(&wallet).Error; err != nil {
					return err
				}
			} else if err != nil {
				return err
			}

			wallet.Balance += badge.CoinsReward
			if err := tx.Save(&wallet).Error; err != nil {
				return err
			}

			// Record transaction
			return tx.Create(&entity.WalletTransaction{
				WalletID:  wallet.ID,
				Amount:    badge.CoinsReward,
				Type:      "reward",
				Reference: fmt.Sprintf("badge:%s", badgeKey),
			}).Error
		}
		return nil
	})
}

// CheckBookingBadges checks and awards booking-related badges after a booking is created.
// Fire-and-forget: errors are silently ignored so the booking flow is never blocked.
func (s *WalletService) CheckBookingBadges(ctx context.Context, userID uuid.UUID, startsAt time.Time) {
	var bookingCount int64
	s.db.WithContext(ctx).Model(&entity.Booking{}).
		Where("user_id = ? AND status IN ('pending','confirmed','completed')", userID).
		Count(&bookingCount)

	if bookingCount >= 1 {
		s.AwardBadge(ctx, userID, "first_booking") //nolint:errcheck
	}

	if startsAt.Hour() < 10 {
		s.AwardBadge(ctx, userID, "early_bird") //nolint:errcheck
	}

	if bookingCount >= 10 {
		s.AwardBadge(ctx, userID, "regular_player") //nolint:errcheck
	}
}

// CheckFeedBadges checks and awards feed-related badges.
// Fire-and-forget: errors are silently ignored so the feed flow is never blocked.
func (s *WalletService) CheckFeedBadges(ctx context.Context, userID uuid.UUID, action string) {
	if action == "create" {
		s.AwardBadge(ctx, userID, "team_captain") //nolint:errcheck
		return
	}

	if action == "join" {
		var joinCount int64
		s.db.WithContext(ctx).Model(&entity.MatchPostJoin{}).
			Where("user_id = ?", userID).
			Count(&joinCount)
		if joinCount >= 5 {
			s.AwardBadge(ctx, userID, "social_butterfly") //nolint:errcheck
		}
	}
}
