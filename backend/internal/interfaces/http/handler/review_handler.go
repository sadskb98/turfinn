package handler

import (
	"errors"
	"strconv"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	"github.com/turfinn/backend/internal/interfaces/dto"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type ReviewHandler struct {
	reviewRepo domain.ReviewRepository
}

func NewReviewHandler(reviewRepo domain.ReviewRepository) *ReviewHandler {
	return &ReviewHandler{reviewRepo: reviewRepo}
}

// POST /api/v1/pitches/:pitch_id/reviews  (auth required)
func (h *ReviewHandler) CreateReview(c echo.Context) error {
	userID, ok := c.Get(authmw.UserIDKey).(uuid.UUID)
	if !ok {
		return response.Unauthorized(c)
	}

	pitchID, err := uuid.Parse(c.Param("pitch_id"))
	if err != nil {
		return response.BadRequest(c, "invalid pitch_id")
	}

	var req dto.CreateReviewRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}

	review := &entity.Review{
		PitchID: pitchID,
		UserID:  userID,
		Rating:  req.Rating,
		Comment: req.Comment,
	}

	if req.BookingID != "" {
		bookingID, err := uuid.Parse(req.BookingID)
		if err != nil {
			return response.BadRequest(c, "invalid booking_id")
		}
		review.BookingID = &bookingID
	}

	if err := h.reviewRepo.Create(c.Request().Context(), review); err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return response.Conflict(c, "you have already reviewed this booking")
		}
		return response.InternalError(c)
	}

	return response.Created(c, toReviewResponse(review))
}

// GET /api/v1/pitches/:pitch_id/reviews  (no auth)
func (h *ReviewHandler) ListReviews(c echo.Context) error {
	pitchID, err := uuid.Parse(c.Param("pitch_id"))
	if err != nil {
		return response.BadRequest(c, "invalid pitch_id")
	}

	page, _ := strconv.Atoi(c.QueryParam("page"))
	if page < 1 {
		page = 1
	}
	pageSize, _ := strconv.Atoi(c.QueryParam("page_size"))
	if pageSize < 1 {
		pageSize = 10
	}
	if pageSize > 50 {
		pageSize = 50
	}

	offset := (page - 1) * pageSize
	ctx := c.Request().Context()

	reviews, total, err := h.reviewRepo.ListByPitch(ctx, pitchID, pageSize, offset)
	if err != nil {
		return response.InternalError(c)
	}

	avgRating, err := h.reviewRepo.GetAverageRating(ctx, pitchID)
	if err != nil {
		// avg rating is enrichment — don't fail the whole response
		avgRating = 0.0
	}

	type ReviewsData struct {
		Reviews   []dto.ReviewResponse `json:"reviews"`
		AvgRating float64              `json:"avg_rating"`
	}

	return response.OKPaginated(c, ReviewsData{
		Reviews:   toReviewResponses(reviews),
		AvgRating: avgRating,
	}, response.Meta{
		Total: total,
		Page:  page,
		Limit: pageSize,
	})
}

func toReviewResponse(r *entity.Review) dto.ReviewResponse {
	res := dto.ReviewResponse{
		ID:        r.ID.String(),
		PitchID:   r.PitchID.String(),
		UserID:    r.UserID.String(),
		Rating:    r.Rating,
		Comment:   r.Comment,
		CreatedAt: r.CreatedAt,
	}
	if r.BookingID != nil {
		res.BookingID = r.BookingID.String()
	}
	return res
}

func toReviewResponses(reviews []entity.Review) []dto.ReviewResponse {
	out := make([]dto.ReviewResponse, len(reviews))
	for i := range reviews {
		out[i] = toReviewResponse(&reviews[i])
	}
	return out
}
