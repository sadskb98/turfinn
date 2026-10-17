package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/labstack/echo/v4"
)

type visitor struct {
	count    int
	lastSeen time.Time
}

// RateLimiter returns middleware that limits requests per IP.
// limit = max requests per window, window = time window duration.
// Optional skipper funcs: if any returns true the request is passed through uncounted.
func RateLimiter(limit int, window time.Duration, skipper ...func(echo.Context) bool) echo.MiddlewareFunc {
	var mu sync.Mutex
	visitors := make(map[string]*visitor)

	go func() {
		for {
			time.Sleep(window)
			mu.Lock()
			for ip, v := range visitors {
				if time.Since(v.lastSeen) > window {
					delete(visitors, ip)
				}
			}
			mu.Unlock()
		}
	}()

	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			for _, skip := range skipper {
				if skip(c) {
					return next(c)
				}
			}
			ip := c.RealIP()
			mu.Lock()
			v, exists := visitors[ip]
			if !exists || time.Since(v.lastSeen) > window {
				visitors[ip] = &visitor{count: 1, lastSeen: time.Now()}
				mu.Unlock()
				return next(c)
			}
			v.count++
			v.lastSeen = time.Now()
			if v.count > limit {
				mu.Unlock()
				return c.JSON(http.StatusTooManyRequests, map[string]any{
					"success": false, "error": "too many requests",
				})
			}
			mu.Unlock()
			return next(c)
		}
	}
}
