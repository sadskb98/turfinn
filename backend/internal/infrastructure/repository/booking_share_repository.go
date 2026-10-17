package repository

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
)

type bookingShareRepository struct {
	db *gorm.DB
}

func NewBookingShareRepository(db *gorm.DB) domain.BookingShareRepository {
	return &bookingShareRepository{db: db}
}

func (r *bookingShareRepository) CreateBatch(ctx context.Context, shares []*entity.BookingShare) error {
	if len(shares) == 0 {
		return nil
	}
	for _, s := range shares {
		if s.ID == uuid.Nil {
			s.ID = uuid.New()
		}
	}
	return r.db.WithContext(ctx).Create(shares).Error
}

func (r *bookingShareRepository) FindByBooking(ctx context.Context, bookingID uuid.UUID) ([]*entity.BookingShare, error) {
	var rows []*entity.BookingShare
	err := r.db.WithContext(ctx).
		Where("booking_id = ?", bookingID).
		Order("share_no ASC").
		Find(&rows).Error
	return rows, err
}

// FindUnclaimedShare locks the row to keep two simultaneous guests from
// landing on the same share — without the FOR UPDATE we'd race when both
// tap the WhatsApp link within the same second.
func (r *bookingShareRepository) FindUnclaimedShare(ctx context.Context, bookingID uuid.UUID) (*entity.BookingShare, error) {
	var s entity.BookingShare
	err := r.db.WithContext(ctx).
		Clauses().
		Raw(`SELECT * FROM booking_shares
		     WHERE booking_id = ? AND status = 'pending' AND payer_phone IS NULL
		     ORDER BY share_no ASC
		     LIMIT 1
		     FOR UPDATE SKIP LOCKED`, bookingID).
		Scan(&s).Error
	if err != nil {
		return nil, err
	}
	if s.ID == uuid.Nil {
		return nil, gorm.ErrRecordNotFound
	}
	return &s, nil
}

func (r *bookingShareRepository) ClaimShare(ctx context.Context, shareID uuid.UUID, phone string, userID *uuid.UUID) error {
	updates := map[string]any{
		"payer_phone": phone,
		"updated_at":  time.Now(),
	}
	if userID != nil {
		updates["payer_user_id"] = *userID
	}
	return r.db.WithContext(ctx).
		Model(&entity.BookingShare{}).
		Where("id = ? AND status = 'pending'", shareID).
		Updates(updates).Error
}

// MarkPaid is idempotent — duplicate IPNs from SSL Commerz happen, and
// we cannot afford to double-bump split_paid_count. A single SQL with a
// status guard means the second call updates zero rows and we report it
// to the caller via alreadyPaid=true.
func (r *bookingShareRepository) MarkPaid(ctx context.Context, shareID uuid.UUID, sslTxID, sslValID string, paidAt time.Time) (bool, error) {
	res := r.db.WithContext(ctx).
		Model(&entity.BookingShare{}).
		Where("id = ? AND status = 'pending'", shareID).
		Updates(map[string]any{
			"status":      entity.SharePaid,
			"paid_at":     paidAt,
			"ssl_tx_id":   sslTxID,
			"ssl_val_id":  sslValID,
			"updated_at":  time.Now(),
		})
	if res.Error != nil {
		return false, res.Error
	}
	if res.RowsAffected == 0 {
		// Either share doesn't exist or it's already paid/refunded/expired —
		// treat as duplicate IPN. Caller decides what to do.
		var existing entity.BookingShare
		if err := r.db.WithContext(ctx).First(&existing, "id = ?", shareID).Error; err != nil {
			return false, err
		}
		return existing.Status == entity.SharePaid, errors.New("share not in pending state")
	}
	return false, nil
}

func (r *bookingShareRepository) MarkRefunded(ctx context.Context, shareID uuid.UUID, refundedAt time.Time) error {
	return r.db.WithContext(ctx).
		Model(&entity.BookingShare{}).
		Where("id = ? AND status = ?", shareID, entity.SharePaid).
		Updates(map[string]any{
			"status":       entity.ShareRefunded,
			"refunded_at":  refundedAt,
			"updated_at":   time.Now(),
		}).Error
}

func (r *bookingShareRepository) ListPaidForBooking(ctx context.Context, bookingID uuid.UUID) ([]*entity.BookingShare, error) {
	var rows []*entity.BookingShare
	err := r.db.WithContext(ctx).
		Where("booking_id = ? AND status = ? AND is_captain_cover = false", bookingID, entity.SharePaid).
		Order("share_no ASC").
		Find(&rows).Error
	return rows, err
}
