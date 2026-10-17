package service

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"github.com/turfinn/backend/internal/interfaces/dto"
)

type UserService struct {
	userRepo domain.UserRepository
}

func NewUserService(repo domain.UserRepository) *UserService {
	return &UserService{userRepo: repo}
}

func (s *UserService) GetByID(ctx context.Context, id uuid.UUID) (*entity.User, error) {
	user, err := s.userRepo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("user not found: %w", err)
	}
	return user, nil
}

func (s *UserService) UpdateProfile(ctx context.Context, id uuid.UUID, req dto.UpdateProfileRequest) (*entity.User, error) {
	user, err := s.userRepo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("user not found: %w", err)
	}
	if req.Name != "" {
		user.Name = req.Name
	}
	if req.AvatarURL != "" {
		user.AvatarURL = req.AvatarURL
	}
	if req.Position != "" {
		user.Position = req.Position
	}
	if req.SkillLevel != "" {
		user.SkillLevel = req.SkillLevel
	}
	if err := s.userRepo.Update(ctx, user); err != nil {
		return nil, fmt.Errorf("update profile: %w", err)
	}
	return user, nil
}

func (s *UserService) UpdateFCMToken(ctx context.Context, userID uuid.UUID, token string) error {
	return s.userRepo.UpdateFCMToken(ctx, userID, token)
}
