package handler

import (
	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/domain/entity"
	"github.com/turfinn/backend/internal/interfaces/dto"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type UserHandler struct {
	userSvc *service.UserService
}

func NewUserHandler(userSvc *service.UserService) *UserHandler {
	return &UserHandler{userSvc: userSvc}
}

type updateFCMTokenReq struct {
	Token string `json:"token" validate:"required,min=10"`
}

// GET /api/v1/users/me
func (h *UserHandler) GetMe(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	user, err := h.userSvc.GetByID(c.Request().Context(), userID)
	if err != nil {
		return response.NotFound(c, "user not found")
	}
	return response.OK(c, toUserResponse(user))
}

// PUT /api/v1/users/me
func (h *UserHandler) UpdateMe(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	var req dto.UpdateProfileRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	user, err := h.userSvc.UpdateProfile(c.Request().Context(), userID, req)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, toUserResponse(user))
}

// PUT /api/v1/users/me/fcm-token
func (h *UserHandler) UpdateFCMToken(c echo.Context) error {
	userID, ok := c.Get(authmw.UserIDKey).(uuid.UUID)
	if !ok {
		return response.Unauthorized(c)
	}
	var req updateFCMTokenReq
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	if err := h.userSvc.UpdateFCMToken(c.Request().Context(), userID, req.Token); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"message": "fcm token updated"})
}

func toUserResponse(u *entity.User) dto.UserResponse {
	phone := ""
	if u.Phone != nil {
		phone = *u.Phone
	}
	return dto.UserResponse{
		ID:        u.ID.String(),
		Phone:     phone,
		Name:      u.Name,
		AvatarURL: u.AvatarURL,
		Role:      string(u.Role),
	}
}
