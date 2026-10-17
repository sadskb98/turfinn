// Package repository provides GORM implementations for marketing & growth.
package repository

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"gorm.io/gorm"
)

type marketingRepository struct {
	db    *gorm.DB
	redis *redis.Client
}

func NewMarketingRepository(db *gorm.DB, redis *redis.Client) domain.MarketingRepository {
	return &marketingRepository{db: db, redis: redis}
}

// ── Promo Codes ──────────────────────────────────────────────────────────────

func (r *marketingRepository) ListPromoCodes(ctx context.Context, page, limit int) ([]entity.PromoCode, int64, error) {
	var total int64
	r.db.WithContext(ctx).Model(&entity.PromoCode{}).Count(&total)

	var items []entity.PromoCode
	err := r.db.WithContext(ctx).Order("created_at DESC").Offset((page - 1) * limit).Limit(limit).Find(&items).Error
	return items, total, err
}

func (r *marketingRepository) GetPromoCode(ctx context.Context, id uuid.UUID) (*entity.PromoCode, error) {
	var p entity.PromoCode
	if err := r.db.WithContext(ctx).First(&p, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &p, nil
}

func (r *marketingRepository) GetPromoByCode(ctx context.Context, code string) (*entity.PromoCode, error) {
	var p entity.PromoCode
	if err := r.db.WithContext(ctx).Where("code = ? AND is_active = true", code).First(&p).Error; err != nil {
		return nil, err
	}
	return &p, nil
}

func (r *marketingRepository) CreatePromoCode(ctx context.Context, p *entity.PromoCode) error {
	p.ID = uuid.New()
	p.CreatedAt = time.Now()
	return r.db.WithContext(ctx).Create(p).Error
}

func (r *marketingRepository) UpdatePromoCode(ctx context.Context, p *entity.PromoCode) error {
	return r.db.WithContext(ctx).Save(p).Error
}

func (r *marketingRepository) ListPromoUsage(ctx context.Context, promoID uuid.UUID, page, limit int) ([]entity.PromoCodeUse, int64, error) {
	var total int64
	r.db.WithContext(ctx).Model(&entity.PromoCodeUse{}).Where("promo_code_id = ?", promoID).Count(&total)

	var items []entity.PromoCodeUse
	err := r.db.WithContext(ctx).Where("promo_code_id = ?", promoID).Order("used_at DESC").Offset((page - 1) * limit).Limit(limit).Find(&items).Error
	return items, total, err
}

func (r *marketingRepository) CreatePromoUse(ctx context.Context, u *entity.PromoCodeUse) error {
	u.ID = uuid.New()
	u.UsedAt = time.Now()
	return r.db.WithContext(ctx).Create(u).Error
}

func (r *marketingRepository) CountUserPromoUses(ctx context.Context, promoID, userID uuid.UUID) (int64, error) {
	var count int64
	err := r.db.WithContext(ctx).Model(&entity.PromoCodeUse{}).Where("promo_code_id = ? AND user_id = ?", promoID, userID).Count(&count).Error
	return count, err
}

// ── Campaigns ────────────────────────────────────────────────────────────────

func (r *marketingRepository) ListCampaigns(ctx context.Context, page, limit int) ([]entity.NotificationCampaign, int64, error) {
	var total int64
	r.db.WithContext(ctx).Model(&entity.NotificationCampaign{}).Count(&total)

	var items []entity.NotificationCampaign
	err := r.db.WithContext(ctx).Order("created_at DESC").Offset((page - 1) * limit).Limit(limit).Find(&items).Error
	return items, total, err
}

func (r *marketingRepository) GetCampaign(ctx context.Context, id uuid.UUID) (*entity.NotificationCampaign, error) {
	var c entity.NotificationCampaign
	if err := r.db.WithContext(ctx).First(&c, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &c, nil
}

func (r *marketingRepository) CreateCampaign(ctx context.Context, c *entity.NotificationCampaign) error {
	c.ID = uuid.New()
	c.CreatedAt = time.Now()
	return r.db.WithContext(ctx).Create(c).Error
}

func (r *marketingRepository) UpdateCampaign(ctx context.Context, c *entity.NotificationCampaign) error {
	return r.db.WithContext(ctx).Save(c).Error
}

// ── Featured Pitches ─────────────────────────────────────────────────────────

func (r *marketingRepository) ListFeaturedPitches(ctx context.Context) ([]entity.FeaturedPitch, error) {
	var items []entity.FeaturedPitch
	err := r.db.WithContext(ctx).Preload("Pitch").Order("position ASC").Find(&items).Error
	return items, err
}

func (r *marketingRepository) CreateFeaturedPitch(ctx context.Context, f *entity.FeaturedPitch) error {
	f.ID = uuid.New()
	f.CreatedAt = time.Now()
	return r.db.WithContext(ctx).Create(f).Error
}

func (r *marketingRepository) UpdateFeaturedPitch(ctx context.Context, f *entity.FeaturedPitch) error {
	return r.db.WithContext(ctx).Save(f).Error
}

func (r *marketingRepository) DeleteFeaturedPitch(ctx context.Context, id uuid.UUID) error {
	return r.db.WithContext(ctx).Delete(&entity.FeaturedPitch{}, "id = ?", id).Error
}

// ── Referrals ────────────────────────────────────────────────────────────────

func (r *marketingRepository) ListReferrals(ctx context.Context, page, limit int) ([]entity.Referral, int64, error) {
	var total int64
	r.db.WithContext(ctx).Model(&entity.Referral{}).Count(&total)

	var items []entity.Referral
	err := r.db.WithContext(ctx).Preload("Referrer").Preload("ReferredUser").Order("created_at DESC").Offset((page - 1) * limit).Limit(limit).Find(&items).Error
	return items, total, err
}

func (r *marketingRepository) GetReferralStats(ctx context.Context) (int64, int64, int64, error) {
	var totalReferrals, totalRewarded, totalRewardsPaisa int64

	r.db.WithContext(ctx).Model(&entity.Referral{}).Count(&totalReferrals)
	r.db.WithContext(ctx).Model(&entity.Referral{}).Where("status = 'rewarded'").Count(&totalRewarded)

	var result struct{ Sum int64 }
	r.db.WithContext(ctx).Model(&entity.Referral{}).Select("COALESCE(SUM(reward_amount), 0) as sum").Where("status = 'rewarded'").Scan(&result)
	totalRewardsPaisa = result.Sum

	return totalReferrals, totalRewarded, totalRewardsPaisa, nil
}

// ── Banners ──────────────────────────────────────────────────────────────────

func (r *marketingRepository) ListBanners(ctx context.Context) ([]entity.Banner, error) {
	var items []entity.Banner
	err := r.db.WithContext(ctx).Order("display_order ASC").Find(&items).Error
	return items, err
}

func (r *marketingRepository) ListActiveBanners(ctx context.Context) ([]entity.Banner, error) {
	now := time.Now()
	var items []entity.Banner
	err := r.db.WithContext(ctx).
		Where("is_active = true AND (starts_at IS NULL OR starts_at <= ?) AND (ends_at IS NULL OR ends_at >= ?)", now, now).
		Order("display_order ASC").Find(&items).Error
	return items, err
}

func (r *marketingRepository) GetBanner(ctx context.Context, id uuid.UUID) (*entity.Banner, error) {
	var b entity.Banner
	if err := r.db.WithContext(ctx).First(&b, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &b, nil
}

func (r *marketingRepository) CreateBanner(ctx context.Context, b *entity.Banner) error {
	b.ID = uuid.New()
	b.CreatedAt = time.Now()
	return r.db.WithContext(ctx).Create(b).Error
}

func (r *marketingRepository) UpdateBanner(ctx context.Context, b *entity.Banner) error {
	return r.db.WithContext(ctx).Save(b).Error
}

func (r *marketingRepository) DeleteBanner(ctx context.Context, id uuid.UUID) error {
	return r.db.WithContext(ctx).Delete(&entity.Banner{}, "id = ?", id).Error
}
