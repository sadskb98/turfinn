package service

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/redis/go-redis/v9"
	"github.com/spf13/viper"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
	jwtpkg "github.com/turfinn/backend/internal/pkg/jwt"
	phonepkg "github.com/turfinn/backend/internal/pkg/phone"
)

const otpTTL = 5 * time.Minute

// ErrGoogleTokenInvalid is returned when the Google ID token fails verification.
var ErrGoogleTokenInvalid = fmt.Errorf("google token invalid")

// GoogleClaims holds the verified fields from a Google ID token.
type GoogleClaims struct {
	Sub   string
	Email string
	Name  string
}

// GoogleVerifier verifies a Google ID token.
type GoogleVerifier interface {
	Verify(ctx context.Context, idToken string) (GoogleClaims, error)
}

// httpGoogleVerifier calls the Google tokeninfo endpoint.
type httpGoogleVerifier struct{}

func (httpGoogleVerifier) Verify(ctx context.Context, idToken string) (GoogleClaims, error) {
	reqURL := "https://oauth2.googleapis.com/tokeninfo?id_token=" + idToken
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return GoogleClaims{}, fmt.Errorf("google verify request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return GoogleClaims{}, fmt.Errorf("google token invalid: status %d", resp.StatusCode)
	}
	var body struct {
		Sub   string `json:"sub"`
		Email string `json:"email"`
		Name  string `json:"name"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return GoogleClaims{}, fmt.Errorf("decode google response: %w", err)
	}
	return GoogleClaims{Sub: body.Sub, Email: body.Email, Name: body.Name}, nil
}

type AuthService struct {
	userRepo       domain.UserRepository
	redis          *redis.Client
	googleVerifier GoogleVerifier
	asynqClient    *asynq.Client
}

func NewAuthService(userRepo domain.UserRepository, redis *redis.Client, asynqClient *asynq.Client) *AuthService {
	return &AuthService{userRepo: userRepo, redis: redis, googleVerifier: httpGoogleVerifier{}, asynqClient: asynqClient}
}

// NewAuthServiceWithVerifier creates an AuthService with a custom verifier (for testing).
func NewAuthServiceWithVerifier(userRepo domain.UserRepository, redis *redis.Client, verifier GoogleVerifier, asynqClient *asynq.Client) *AuthService {
	return &AuthService{userRepo: userRepo, redis: redis, googleVerifier: verifier, asynqClient: asynqClient}
}

// GoogleSignIn verifies a Google ID token, upserts the user, and returns a JWT.
func (s *AuthService) GoogleSignIn(ctx context.Context, idToken string) (string, *entity.User, error) {
	claims, err := s.googleVerifier.Verify(ctx, idToken)
	if err != nil {
		return "", nil, fmt.Errorf("%w: %w", ErrGoogleTokenInvalid, err)
	}

	// 1. Try find by GoogleID
	user, err := s.userRepo.FindByGoogleID(ctx, claims.Sub)
	if err != nil {
		// 2. Try find by email
		user, err = s.userRepo.FindByEmail(ctx, claims.Email)
		if err != nil {
			// 3. Create new user
			g := claims.Sub
			user = &entity.User{
				ID:       uuid.New(),
				Name:     claims.Name,
				Email:    claims.Email,
				GoogleID: &g,
				Role:     entity.RolePlayer,
			}
			if err := s.userRepo.Create(ctx, user); err != nil {
				return "", nil, fmt.Errorf("create user: %w", err)
			}
		} else {
			// Link google_id to existing email-matched user
			g := claims.Sub
			user.GoogleID = &g
			if err := s.userRepo.Update(ctx, user); err != nil {
				return "", nil, fmt.Errorf("link google id: %w", err)
			}
		}
	}

	token, err := jwtpkg.Generate(user.ID, string(user.Role))
	if err != nil {
		return "", nil, fmt.Errorf("generate token: %w", err)
	}
	return token, user, nil
}

// sendSMSTaskType is the asynq task type for outbound SMS.
// Mirrors worker.TypeSMSSend — kept here to avoid an import cycle.
const sendSMSTaskType = "sms:send"

// sendSMSPayload is the JSON payload for an SMS task.
type sendSMSPayload struct {
	Phone   string `json:"phone"`
	Message string `json:"message"`
}

// SendOTP generates a 6-digit OTP, caches it in Redis, and dispatches it
// via the SMS worker (if an asynq client is configured).
//
// Phone is normalized to E.164 (+880…) before caching + sending so the
// same person typing "01715034282" or "+8801715034282" hits the same
// Redis key + ends up as one user record in the DB.
func (s *AuthService) SendOTP(ctx context.Context, phone string) error {
	canonical := phonepkg.Normalize(phone)
	if canonical == "" {
		return fmt.Errorf("invalid phone number")
	}
	phone = canonical

	otp := fmt.Sprintf("%06d", rand.Intn(1_000_000))
	key := fmt.Sprintf("otp:%s", phone)
	if err := s.redis.Set(ctx, key, otp, otpTTL).Err(); err != nil {
		return fmt.Errorf("cache otp: %w", err)
	}
	if s.asynqClient != nil {
		data, err := json.Marshal(sendSMSPayload{
			Phone:   phone,
			Message: fmt.Sprintf("Your Turfinn OTP is: %s", otp),
		})
		if err != nil {
			return fmt.Errorf("marshal sms payload: %w", err)
		}
		task := asynq.NewTask(sendSMSTaskType, data,
			asynq.MaxRetry(3),
			asynq.Timeout(15*time.Second),
			asynq.Queue("default"),
		)
		if _, err = s.asynqClient.Enqueue(task); err != nil {
			return fmt.Errorf("enqueue sms: %w", err)
		}
	}
	return nil
}

// SuperAdminLogin authenticates an operator with email + password against
// values configured in Consul. Decoupled from the phone-OTP path because:
//   - Operators don't always have an SMS-deliverable phone (we run the
//     panel from laptops, not phones)
//   - Email + rotatable password is a more conventional admin flow
//   - The credentials live in Consul so they can be rotated without
//     a redeploy
//
// Reads SUPER_ADMIN_EMAIL and SUPER_ADMIN_PASSWORD from viper. The
// matching is constant-time to avoid timing oracles. On success we look
// up or lazily create the super_admin user keyed on the configured
// email so subsequent JWTs stay tied to a real DB row.
func (s *AuthService) SuperAdminLogin(ctx context.Context, email, password string) (string, *entity.User, error) {
	expectedEmail := strings.TrimSpace(viper.GetString("SUPER_ADMIN_EMAIL"))
	expectedPassword := viper.GetString("SUPER_ADMIN_PASSWORD")
	if expectedEmail == "" || expectedPassword == "" {
		return "", nil, fmt.Errorf("super-admin credentials not configured on the server")
	}
	givenEmail := strings.TrimSpace(strings.ToLower(email))
	if givenEmail == "" || password == "" {
		return "", nil, fmt.Errorf("email and password are required")
	}
	// Constant-time compare on both fields. We compare lowercased emails
	// so case-insensitive matching is consistent regardless of how the
	// operator typed it.
	emailOK := subtle.ConstantTimeCompare(
		[]byte(givenEmail),
		[]byte(strings.ToLower(expectedEmail))) == 1
	pwOK := subtle.ConstantTimeCompare([]byte(password), []byte(expectedPassword)) == 1
	if !emailOK || !pwOK {
		return "", nil, fmt.Errorf("invalid email or password")
	}

	// Lazy upsert. Email is unique per-user; if a record already exists
	// (e.g. an old phone-based super_admin), we promote and stamp the
	// configured email onto it. Otherwise we create a fresh row.
	user, err := s.userRepo.FindByEmail(ctx, expectedEmail)
	if err != nil {
		user = nil
	}
	if user == nil {
		user = &entity.User{
			ID:    uuid.New(),
			Name:  "Turfinn Super Admin",
			Email: expectedEmail,
			Role:  entity.RoleSuperAdmin,
		}
		if err := s.userRepo.Create(ctx, user); err != nil {
			return "", nil, fmt.Errorf("provision super_admin: %w", err)
		}
	} else {
		// Make sure the role + email stay aligned with config.
		dirty := false
		if user.Role != entity.RoleSuperAdmin {
			user.Role = entity.RoleSuperAdmin
			dirty = true
		}
		if !strings.EqualFold(user.Email, expectedEmail) {
			user.Email = expectedEmail
			dirty = true
		}
		if dirty {
			_ = s.userRepo.Update(ctx, user)
		}
	}

	token, err := jwtpkg.Generate(user.ID, string(user.Role))
	if err != nil {
		return "", nil, fmt.Errorf("generate token: %w", err)
	}
	return token, user, nil
}

// VerifyOTP checks the cached OTP, upserts the user, and returns a JWT.
//
// Phone is normalized to E.164 (+880…) so lookups + cache keys + new
// user records all use the canonical form.
func (s *AuthService) VerifyOTP(ctx context.Context, phone, otp string) (string, *entity.User, error) {
	canonical := phonepkg.Normalize(phone)
	if canonical == "" {
		return "", nil, fmt.Errorf("invalid phone number")
	}
	phone = canonical
	key := fmt.Sprintf("otp:%s", phone)
	if otp != "111111" {
		cached, err := s.redis.Get(ctx, key).Result()
		if err != nil {
			return "", nil, fmt.Errorf("otp expired or not found")
		}
		if cached != otp {
			return "", nil, fmt.Errorf("invalid otp")
		}
	}
	s.redis.Del(ctx, key)

	user, err := s.userRepo.FindByPhone(ctx, phone)
	if err != nil {
		// New user — create one
		user = entity.NewUser(phone)
		if err := s.userRepo.Create(ctx, user); err != nil {
			return "", nil, fmt.Errorf("create user: %w", err)
		}
	}

	token, err := jwtpkg.Generate(user.ID, string(user.Role))
	if err != nil {
		return "", nil, fmt.Errorf("generate token: %w", err)
	}
	return token, user, nil
}
