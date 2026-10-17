// Package service — LedgerService records double-entry rows into
// ledger_entries. Drives the super-admin Finance & Audit views (trial
// balance, income statement, VAT) and the Ledger list.
//
// Account vocabulary (matches existing super-admin queries):
//
//	cash               — money received from the customer
//	platform_revenue   — what Turfinn keeps (the commission slice)
//	pitch_owner        — what flows to the venue owner
//	customer_refund    — money owed back to the customer
//	match_pool         — held funds for an open match (per-head + fee)
//
// Convention: amount_paisa is positive on every row; direction is
// expressed by debit_account vs credit_account.
package service

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/turfinn/backend/internal/domain/entity"
)

// Account names — the canonical set used by the super-admin queries.
const (
	AcctCash            = "cash"
	AcctPlatformRevenue = "platform_revenue"
	AcctPitchOwner      = "pitch_owner"
	AcctCustomerRefund  = "customer_refund"
	AcctMatchPool       = "match_pool"
)

// Entry types — these are the high-level event classes.
const (
	EntryBookingPayment   = "booking_payment"
	EntryBookingRefund    = "refund"
	EntryMatchPayment     = "match_payment"
	EntryMatchRefund      = "refund"
	EntryPromoExpense     = "promo_expense"
)

type LedgerService struct {
	db *gorm.DB
}

func NewLedgerService(db *gorm.DB) *LedgerService {
	return &LedgerService{db: db}
}

// Record inserts a single ledger row. Pass `tx` if the caller is already
// inside a transaction; pass nil to use the service's default DB handle.
//
// The caller is responsible for choosing debit/credit accounts that net
// out across all rows for the same transactionRef. We don't enforce that
// here — Trial Balance will surface mismatches.
func (s *LedgerService) Record(
	ctx context.Context,
	tx *gorm.DB,
	entryType, debit, credit string,
	amountPaisa int64,
	transactionRef, relatedType string,
	relatedID uuid.UUID,
	description string,
) error {
	if amountPaisa <= 0 {
		return fmt.Errorf("ledger.Record: amount must be > 0")
	}
	if entryType == "" || debit == "" || credit == "" {
		return fmt.Errorf("ledger.Record: missing entry_type/debit/credit")
	}
	db := tx
	if db == nil {
		db = s.db
	}
	row := entity.LedgerEntry{
		TransactionRef:    transactionRef,
		EntryType:         entryType,
		DebitAccount:      debit,
		CreditAccount:     credit,
		AmountPaisa:       amountPaisa,
		Description:       description,
		RelatedEntityType: relatedType,
		RelatedEntityID:   relatedID,
		CreatedAt:         time.Now(),
	}
	return db.WithContext(ctx).Create(&row).Error
}

// RecordBookingPayment splits a confirmed booking into the platform's
// commission slice and the pitch-owner share. `commissionBps` is the
// platform's cut in basis points (1500 = 15%). Both rows share the same
// transactionRef so they net cleanly in trial balance.
func (s *LedgerService) RecordBookingPayment(
	ctx context.Context,
	tx *gorm.DB,
	bookingID uuid.UUID,
	totalPaisa int64,
	commissionBps int,
) error {
	if totalPaisa <= 0 {
		return nil
	}
	if commissionBps < 0 || commissionBps > 10000 {
		commissionBps = 1500
	}
	platformShare := totalPaisa * int64(commissionBps) / 10000
	ownerShare := totalPaisa - platformShare
	ref := "BKG-" + bookingID.String()
	if err := s.Record(ctx, tx, EntryBookingPayment,
		AcctCash, AcctPlatformRevenue, platformShare,
		ref, "booking", bookingID,
		"Booking commission"); err != nil {
		return err
	}
	if ownerShare > 0 {
		if err := s.Record(ctx, tx, EntryBookingPayment,
			AcctCash, AcctPitchOwner, ownerShare,
			ref, "booking", bookingID,
			"Pitch owner share"); err != nil {
			return err
		}
	}
	return nil
}

// RecordBookingRefund records a booking-level refund (cancellation).
// Refunds are logged as `customer_refund -> cash` so the trial balance
// shows the platform's outflow.
func (s *LedgerService) RecordBookingRefund(
	ctx context.Context,
	tx *gorm.DB,
	bookingID uuid.UUID,
	amountPaisa int64,
	reason string,
) error {
	if amountPaisa <= 0 {
		return nil
	}
	return s.Record(ctx, tx, EntryBookingRefund,
		AcctCustomerRefund, AcctCash, amountPaisa,
		"BKG-"+bookingID.String(), "booking", bookingID,
		"Refund: "+reason)
}

// RecordMatchJoinPayment is the per-joiner payment for an open match.
// Treated as a deposit into match_pool until the match completes; the
// settlement worker (future) will sweep match_pool → pitch_owner +
// platform_revenue once the match is marked completed.
func (s *LedgerService) RecordMatchJoinPayment(
	ctx context.Context,
	tx *gorm.DB,
	paymentID, matchPostID uuid.UUID,
	amountPaisa int64,
) error {
	if amountPaisa <= 0 {
		return nil
	}
	return s.Record(ctx, tx, EntryMatchPayment,
		AcctCash, AcctMatchPool, amountPaisa,
		"MJP-"+paymentID.String(), "match_join_payment", paymentID,
		"Match join payment")
}

// RecordMatchJoinRefund is the inverse: money flows back out of
// match_pool to the customer.
func (s *LedgerService) RecordMatchJoinRefund(
	ctx context.Context,
	tx *gorm.DB,
	paymentID uuid.UUID,
	amountPaisa int64,
	reason string,
) error {
	if amountPaisa <= 0 {
		return nil
	}
	return s.Record(ctx, tx, EntryMatchRefund,
		AcctMatchPool, AcctCustomerRefund, amountPaisa,
		"MJP-"+paymentID.String(), "match_join_payment", paymentID,
		"Match refund: "+reason)
}
