package response

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

type Meta struct {
	Page  int   `json:"page"`
	Limit int   `json:"limit"`
	Total int64 `json:"total"`
}

func OK(c echo.Context, data any) error {
	return c.JSON(http.StatusOK, map[string]any{"success": true, "data": data})
}

func OKPaginated(c echo.Context, data any, meta Meta) error {
	return c.JSON(http.StatusOK, map[string]any{"success": true, "data": data, "meta": meta})
}

func Created(c echo.Context, data any) error {
	return c.JSON(http.StatusCreated, map[string]any{"success": true, "data": data})
}

func BadRequest(c echo.Context, msg string) error {
	return c.JSON(http.StatusBadRequest, map[string]any{"success": false, "error": msg})
}

func Unauthorized(c echo.Context) error {
	return c.JSON(http.StatusUnauthorized, map[string]any{"success": false, "error": "unauthorized"})
}

func Forbidden(c echo.Context) error {
	return c.JSON(http.StatusForbidden, map[string]any{"success": false, "error": "forbidden"})
}

func NotFound(c echo.Context, msg string) error {
	return c.JSON(http.StatusNotFound, map[string]any{"success": false, "error": msg})
}

func Conflict(c echo.Context, msg string) error {
	return c.JSON(http.StatusConflict, map[string]any{"success": false, "error": msg})
}

func InternalError(c echo.Context) error {
	return c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "error": "internal server error"})
}
