package dto

import "time"

type CreateReviewRequest struct {
	BookingID string `json:"booking_id,omitempty" validate:"omitempty,uuid"`
	Rating    int16  `json:"rating" validate:"required,min=1,max=5"`
	Comment   string `json:"comment" validate:"max=1000"`
}

type ReviewResponse struct {
	ID        string    `json:"id"`
	PitchID   string    `json:"pitch_id"`
	UserID    string    `json:"user_id"`
	BookingID string    `json:"booking_id,omitempty"`
	Rating    int16     `json:"rating"`
	Comment   string    `json:"comment,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}
