package handler

import (
	"errors"

	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/interfaces/dto"
	"github.com/turfinn/backend/internal/pkg/response"
)

type AuthHandler struct {
	authSvc *service.AuthService
}

func NewAuthHandler(authSvc *service.AuthService) *AuthHandler {
	return &AuthHandler{authSvc: authSvc}
}

// POST /api/v1/auth/send-otp
func (h *AuthHandler) SendOTP(c echo.Context) error {
	var req dto.SendOTPRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	if err := h.authSvc.SendOTP(c.Request().Context(), req.Phone); err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, map[string]string{"message": "OTP sent"})
}

// POST /api/v1/auth/google
func (h *AuthHandler) GoogleSignIn(c echo.Context) error {
	var req dto.GoogleSignInRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	token, user, err := h.authSvc.GoogleSignIn(c.Request().Context(), req.IDToken)
	if err != nil {
		if errors.Is(err, service.ErrGoogleTokenInvalid) {
			return response.BadRequest(c, "invalid google token")
		}
		return response.InternalError(c)
	}
	return response.OK(c, dto.AuthResponse{
		Token: token,
		User: dto.UserResponse{
			ID:        user.ID.String(),
			Phone:     func() string { if user.Phone == nil { return "" }; return *user.Phone }(),
			Name:      user.Name,
			AvatarURL: user.AvatarURL,
			Role:      string(user.Role),
		},
	})
}

// POST /api/v1/auth/verify-otp
func (h *AuthHandler) VerifyOTP(c echo.Context) error {
	var req dto.VerifyOTPRequest
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	token, user, err := h.authSvc.VerifyOTP(c.Request().Context(), req.Phone, req.OTP)
	if err != nil {
		return response.BadRequest(c, err.Error())
	}
	return response.OK(c, dto.AuthResponse{
		Token: token,
		User: dto.UserResponse{
			ID:        user.ID.String(),
			Phone:     func() string { if user.Phone == nil { return "" }; return *user.Phone }(),
			Name:      user.Name,
			AvatarURL: user.AvatarURL,
			Role:      string(user.Role),
		},
	})
}

// SuperAdminLogin authenticates an operator with email + password against
// values in Consul. Returns the same AuthResponse shape as VerifyOTP so
// the panel doesn't have to special-case it.
func (h *AuthHandler) SuperAdminLogin(c echo.Context) error {
	var req struct {
		Email    string `json:"email" validate:"required,email"`
		Password string `json:"password" validate:"required,min=6"`
	}
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request body")
	}
	if err := c.Validate(&req); err != nil {
		return response.BadRequest(c, err.Error())
	}
	token, user, err := h.authSvc.SuperAdminLogin(c.Request().Context(), req.Email, req.Password)
	if err != nil {
		return response.Unauthorized(c)
	}
	return response.OK(c, dto.AuthResponse{
		Token: token,
		User: dto.UserResponse{
			ID:        user.ID.String(),
			Phone:     func() string { if user.Phone == nil { return "" }; return *user.Phone }(),
			Name:      user.Name,
			AvatarURL: user.AvatarURL,
			Role:      string(user.Role),
		},
	})
}
