// Package repository defines interfaces for marketing & growth data access.
package repository

import (
	"context"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
)

type MarketingRepository interface {
	// Promo Codes
	ListPromoCodes(ctx context.Context, page, limit int) ([]entity.PromoCode, int64, error)
	GetPromoCode(ctx context.Context, id uuid.UUID) (*entity.PromoCode, error)
	GetPromoByCode(ctx context.Context, code string) (*entity.PromoCode, error)
	CreatePromoCode(ctx context.Context, p *entity.PromoCode) error
	UpdatePromoCode(ctx context.Context, p *entity.PromoCode) error
	ListPromoUsage(ctx context.Context, promoID uuid.UUID, page, limit int) ([]entity.PromoCodeUse, int64, error)
	CreatePromoUse(ctx context.Context, u *entity.PromoCodeUse) error
	CountUserPromoUses(ctx context.Context, promoID, userID uuid.UUID) (int64, error)

	// Campaigns
	ListCampaigns(ctx context.Context, page, limit int) ([]entity.NotificationCampaign, int64, error)
	GetCampaign(ctx context.Context, id uuid.UUID) (*entity.NotificationCampaign, error)
	CreateCampaign(ctx context.Context, c *entity.NotificationCampaign) error
	UpdateCampaign(ctx context.Context, c *entity.NotificationCampaign) error

	// Featured Pitches
	ListFeaturedPitches(ctx context.Context) ([]entity.FeaturedPitch, error)
	CreateFeaturedPitch(ctx context.Context, f *entity.FeaturedPitch) error
	UpdateFeaturedPitch(ctx context.Context, f *entity.FeaturedPitch) error
	DeleteFeaturedPitch(ctx context.Context, id uuid.UUID) error

	// Referrals
	ListReferrals(ctx context.Context, page, limit int) ([]entity.Referral, int64, error)
	GetReferralStats(ctx context.Context) (totalReferrals int64, totalRewarded int64, totalRewardsPaisa int64, err error)

	// Banners
	ListBanners(ctx context.Context) ([]entity.Banner, error)
	ListActiveBanners(ctx context.Context) ([]entity.Banner, error)
	GetBanner(ctx context.Context, id uuid.UUID) (*entity.Banner, error)
	CreateBanner(ctx context.Context, b *entity.Banner) error
	UpdateBanner(ctx context.Context, b *entity.Banner) error
	DeleteBanner(ctx context.Context, id uuid.UUID) error
}
