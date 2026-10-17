package repository

import (
	"context"
	"time"

	"github.com/google/uuid"

	"github.com/turfinn/backend/internal/domain/entity"
)

// BookingShareRepository is the persistence boundary for split-pay shares.
// Split-pay state is dual-tracked: each share row carries its own status,
// and the parent booking carries split_paid_count + split_share_count for
// fast quorum checks without scanning shares on every callback.
type BookingShareRepository interface {
	// CreateBatch atomically inserts all shares for a freshly initiated
	// split booking. Should be called inside the same tx as the booking
	// row insert so we never observe a booking without its shares.
	CreateBatch(ctx context.Context, shares []*entity.BookingShare) error

	// FindByBooking returns shares ordered by share_no.
	FindByBooking(ctx context.Context, bookingID uuid.UUID) ([]*entity.BookingShare, error)

	// FindUnclaimedShare returns the first pending share with no payer
	// phone yet — what a fresh visitor to the magic link gets assigned.
	// Locked FOR UPDATE to prevent two concurrent guests claiming the
	// same slot.
	FindUnclaimedShare(ctx context.Context, bookingID uuid.UUID) (*entity.BookingShare, error)

	// ClaimShare atomically assigns payer_phone (and optional user_id)
	// to a pending share. Used right before kicking off SSL Commerz.
	ClaimShare(ctx context.Context, shareID uuid.UUID, phone string, userID *uuid.UUID) error

	// MarkPaid flips a share to paid and records the SSL transaction
	// IDs. Idempotent: re-marking an already-paid share is a no-op so
	// duplicate IPN callbacks don't double-bump split_paid_count.
	MarkPaid(ctx context.Context, shareID uuid.UUID, sslTxID, sslValID string, paidAt time.Time) (alreadyPaid bool, err error)

	// MarkRefunded transitions a paid share to refunded after SSL
	// confirms the refund — see split-deadline expiry worker.
	MarkRefunded(ctx context.Context, shareID uuid.UUID, refundedAt time.Time) error

	// ListPaidForBooking is what the deadline worker uses to know which
	// shares need refunding. Excludes captain-cover entries since those
	// were paid via the captain's normal booking-payment row, not a
	// share-specific SSL tx.
	ListPaidForBooking(ctx context.Context, bookingID uuid.UUID) ([]*entity.BookingShare, error)
}
