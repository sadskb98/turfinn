package repository

import (
	"context"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
)

type UserFilter struct {
	Search string
	Role   string
	Page   int
	Limit  int
}

type UserRepository interface {
	Create(ctx context.Context, user *entity.User) error
	FindByID(ctx context.Context, id uuid.UUID) (*entity.User, error)
	FindByPhone(ctx context.Context, phone string) (*entity.User, error)
	FindByEmail(ctx context.Context, email string) (*entity.User, error)
	FindByGoogleID(ctx context.Context, googleID string) (*entity.User, error)
	Update(ctx context.Context, user *entity.User) error
	Delete(ctx context.Context, id uuid.UUID) error
	UpdateFCMToken(ctx context.Context, userID uuid.UUID, token string) error
	List(ctx context.Context, filter UserFilter) ([]*entity.User, int64, error)
	Count(ctx context.Context) (int64, error)
}
