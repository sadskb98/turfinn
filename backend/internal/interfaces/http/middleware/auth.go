package middleware

import (
	"strings"

	"github.com/labstack/echo/v4"
	jwtpkg "github.com/turfinn/backend/internal/pkg/jwt"
	"github.com/turfinn/backend/internal/pkg/response"
	"gorm.io/gorm"
)

const UserIDKey = "user_id"
const UserRoleKey = "user_role"

func Auth(optDB ...*gorm.DB) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			header := c.Request().Header.Get("Authorization")
			if !strings.HasPrefix(header, "Bearer ") {
				return response.Unauthorized(c)
			}
			token := strings.TrimPrefix(header, "Bearer ")
			claims, err := jwtpkg.Parse(token)
			if err != nil {
				return response.Unauthorized(c)
			}
			c.Set(UserIDKey, claims.UserID)
			if len(optDB) > 0 && optDB[0] != nil {
				var row struct {
					Role     string
					IsActive bool
				}
				err := optDB[0].Table("users").
					Select("role, is_active").
					Where("id = ?", claims.UserID).
					Scan(&row).Error
				if err == nil && row.Role != "" {
					// Deactivated users can hold a still-valid JWT but
					// must not be allowed to act on it. 401 forces them
					// back through login (which their account state will
					// also block).
					if !row.IsActive {
						return response.Unauthorized(c)
					}
					c.Set(UserRoleKey, row.Role)
				} else {
					c.Set(UserRoleKey, claims.Role)
				}
			} else {
				c.Set(UserRoleKey, claims.Role)
			}
			return next(c)
		}
	}
}

// RequireManager rejects requests where the authenticated user is not a manager.
// Must be used after Auth() (or as a middleware chain: Auth(), RequireManager()).
func RequireManager() echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			role, _ := c.Get(UserRoleKey).(string)
			if role != "manager" {
				return response.Forbidden(c)
			}
			return next(c)
		}
	}
}

// RequireRole creates middleware that checks the JWT role against allowed roles.
func RequireRole(roles ...string) echo.MiddlewareFunc {
	allowed := make(map[string]bool, len(roles))
	for _, r := range roles {
		allowed[r] = true
	}
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			role, _ := c.Get(UserRoleKey).(string)
			if !allowed[role] {
				return response.Forbidden(c)
			}
			return next(c)
		}
	}
}

// OptionalAuth populates user_id/role in context if a valid Bearer token is present,
// but does NOT reject requests without a token.
func OptionalAuth(optDB ...*gorm.DB) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			header := c.Request().Header.Get("Authorization")
			if strings.HasPrefix(header, "Bearer ") {
				token := strings.TrimPrefix(header, "Bearer ")
				if claims, err := jwtpkg.Parse(token); err == nil {
					c.Set(UserIDKey, claims.UserID)
					if len(optDB) > 0 && optDB[0] != nil {
						var role string
						if err := optDB[0].Table("users").Select("role").Where("id = ?", claims.UserID).Scan(&role).Error; err == nil && role != "" {
							c.Set(UserRoleKey, role)
						} else {
							c.Set(UserRoleKey, claims.Role)
						}
					} else {
						c.Set(UserRoleKey, claims.Role)
					}
				}
			}
			return next(c)
		}
	}
}
