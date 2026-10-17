package service

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"github.com/turfinn/backend/internal/interfaces/dto"
)

type PitchService struct {
	pitchRepo domain.PitchRepository
}

func NewPitchService(pitchRepo domain.PitchRepository) *PitchService {
	return &PitchService{pitchRepo: pitchRepo}
}

func (s *PitchService) Create(ctx context.Context, ownerID uuid.UUID, req dto.CreatePitchRequest) (*entity.Pitch, error) {
	pitch := entity.NewPitch(req.Name, req.Address, req.City, ownerID, req.PricePerHour)
	pitch.Description = req.Description
	pitch.Latitude = req.Latitude
	pitch.Longitude = req.Longitude
	pitch.Surface = req.Surface
	pitch.Capacity = req.Capacity
	if err := s.pitchRepo.Create(ctx, pitch); err != nil {
		return nil, fmt.Errorf("create pitch: %w", err)
	}
	return pitch, nil
}

func (s *PitchService) GetByID(ctx context.Context, id uuid.UUID) (*entity.Pitch, error) {
	pitch, err := s.pitchRepo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("pitch not found: %w", err)
	}
	return pitch, nil
}

func (s *PitchService) List(ctx context.Context, filter domain.PitchFilter) ([]*entity.Pitch, int64, error) {
	if filter.Page < 1 {
		filter.Page = 1
	}
	if filter.Limit < 1 || filter.Limit > 50 {
		filter.Limit = 20
	}
	return s.pitchRepo.List(ctx, filter)
}

func (s *PitchService) GetBookingsForSlots(ctx context.Context, pitchID uuid.UUID, from, to time.Time) ([]*entity.Booking, error) {
	return s.pitchRepo.FindBookingsInRange(ctx, pitchID, from, to)
}
