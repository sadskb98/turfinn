// Package service — AuditService records mutations performed by admins
// and managers into audit_log. Drives the super-admin Audit Log view.
//
// We record the actor (who), action (verb), and entity (what was
// touched), plus before/after JSON snapshots when available. IP and
// user-agent come from the HTTP request when available.
package service

import (
	"context"
	"encoding/json"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/turfinn/backend/internal/domain/entity"
)

type AuditService struct {
	db *gorm.DB
}

func NewAuditService(db *gorm.DB) *AuditService {
	return &AuditService{db: db}
}

// Record inserts an audit_log row. Both old and new are optional — pass
// nil if the action doesn't have a before/after shape (e.g. retry-refund).
//
// Failure is logged by the caller but never blocks the underlying action;
// audit gaps are tolerated, audit-driven bugs are not.
func (s *AuditService) Record(
	ctx context.Context,
	actorID uuid.UUID,
	actorRole, action, entityType, entityID string,
	old, new any,
	ip, userAgent string,
) error {
	row := entity.AuditLog{
		ActorID:    actorID,
		ActorRole:  actorRole,
		Action:     action,
		EntityType: entityType,
		EntityID:   entityID,
		IPAddress:  ip,
		UserAgent:  userAgent,
		CreatedAt:  time.Now(),
	}
	if old != nil {
		if b, err := json.Marshal(old); err == nil {
			row.OldValue = string(b)
		}
	}
	if new != nil {
		if b, err := json.Marshal(new); err == nil {
			row.NewValue = string(b)
		}
	}
	return s.db.WithContext(ctx).Create(&row).Error
}
