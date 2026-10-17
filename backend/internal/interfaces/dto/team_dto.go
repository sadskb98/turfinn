package dto

import (
	"time"

	"github.com/google/uuid"
)

// ── Requests ─────────────────────────────────────────────────────────────────

type CreateTeamRequest struct {
	Name      string `json:"name" validate:"required"`
	Format    string `json:"format" validate:"required"` // "7 vs 7"
	Formation string `json:"formation"`                  // "2-3-1"
}

type JoinTeamRequest struct {
	Code string `json:"code" validate:"required,len=6"`
}

type FindMatchRequest struct {
	TeamID       uuid.UUID `json:"team_id" validate:"required"`
	WantedFormat string    `json:"wanted_format"`       // "5v5","6v6","7v7","8v8","11v11","open"
	Latitude     float64   `json:"latitude"`            // device GPS lat; 0 = not provided
	Longitude    float64   `json:"longitude"`           // device GPS lng; 0 = not provided
	RadiusKM     float64   `json:"radius_km"`           // search radius; 0 = use default (30 km)
	City         string    `json:"city"`                // fallback if no GPS
}

type SetVenueRequest struct {
	PitchID     uuid.UUID `json:"pitch_id" validate:"required"`
	ScheduledAt time.Time `json:"scheduled_at" validate:"required"`
}

type UpdateFormationRequest struct {
	Formation string `json:"formation" validate:"required"`
}

// ── Responses ────────────────────────────────────────────────────────────────

type TeamResponse struct {
	ID         string               `json:"id"`
	Name       string               `json:"name"`
	Code       string               `json:"code"`
	Format     string               `json:"format"`
	Formation  string               `json:"formation"`
	CaptainID  string               `json:"captain_id"`
	MaxPlayers int                  `json:"max_players"`
	Status     string               `json:"status"`
	Members    []TeamMemberResponse `json:"members"`
	CreatedAt  string               `json:"created_at"`
}

type TeamMemberResponse struct {
	ID       string `json:"id"`
	UserID   string `json:"user_id"`
	Name     string `json:"name"`
	Phone    string `json:"phone"`
	Position string `json:"position"`
	Number   int    `json:"number"`
	Role     string `json:"role"`
}

type MatchResponse struct {
	ID          string        `json:"id"`
	HomeTeam    *TeamResponse `json:"home_team,omitempty"`
	AwayTeam    *TeamResponse `json:"away_team,omitempty"`
	Format      string        `json:"format"`
	Status      string        `json:"status"`
	PitchID     *string       `json:"pitch_id,omitempty"`
	ScheduledAt *string       `json:"scheduled_at,omitempty"`
	CreatedAt   string        `json:"created_at"`
}
