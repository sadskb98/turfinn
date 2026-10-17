package service_test

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/application/service"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
)

// mockUserRepo is a minimal in-memory mock satisfying domain.UserRepository.
type mockUserRepo struct {
	byGoogleID map[string]*entity.User
	byEmail    map[string]*entity.User
	created    []*entity.User
}

func newMockUserRepo() *mockUserRepo {
	return &mockUserRepo{
		byGoogleID: map[string]*entity.User{},
		byEmail:    map[string]*entity.User{},
	}
}

func (m *mockUserRepo) Create(ctx context.Context, u *entity.User) error {
	m.created = append(m.created, u)
	return nil
}
func (m *mockUserRepo) FindByID(_ context.Context, _ uuid.UUID) (*entity.User, error) {
	return nil, errors.New("not found")
}
func (m *mockUserRepo) FindByPhone(_ context.Context, _ string) (*entity.User, error) {
	return nil, errors.New("not found")
}
func (m *mockUserRepo) FindByEmail(_ context.Context, email string) (*entity.User, error) {
	u, ok := m.byEmail[email]
	if !ok {
		return nil, errors.New("not found")
	}
	return u, nil
}
func (m *mockUserRepo) FindByGoogleID(_ context.Context, gid string) (*entity.User, error) {
	u, ok := m.byGoogleID[gid]
	if !ok {
		return nil, errors.New("not found")
	}
	return u, nil
}
func (m *mockUserRepo) Update(_ context.Context, _ *entity.User) error               { return nil }
func (m *mockUserRepo) Delete(_ context.Context, _ uuid.UUID) error                  { return nil }
func (m *mockUserRepo) UpdateFCMToken(_ context.Context, _ uuid.UUID, _ string) error { return nil }
func (m *mockUserRepo) List(_ context.Context, _ domain.UserFilter) ([]*entity.User, int64, error) {
	return nil, 0, nil
}
func (m *mockUserRepo) Count(_ context.Context) (int64, error) { return 0, nil }

// Compile-time check: mockUserRepo satisfies domain.UserRepository
var _ domain.UserRepository = (*mockUserRepo)(nil)

// fakeVerifier replaces the real Google token verifier in tests.
type fakeVerifier struct {
	googleID string
	email    string
	name     string
	err      error
}

func (f *fakeVerifier) Verify(_ context.Context, _ string) (service.GoogleClaims, error) {
	if f.err != nil {
		return service.GoogleClaims{}, f.err
	}
	return service.GoogleClaims{Sub: f.googleID, Email: f.email, Name: f.name}, nil
}

func TestGoogleSignIn_NewUser(t *testing.T) {
	repo := newMockUserRepo()
	svc := service.NewAuthServiceWithVerifier(repo, nil, &fakeVerifier{
		googleID: "google-abc", email: "new@example.com", name: "New User",
	}, nil)
	token, user, err := svc.GoogleSignIn(context.Background(), "fake-id-token")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if token == "" {
		t.Fatal("expected JWT token, got empty string")
	}
	if user.Email != "new@example.com" {
		t.Errorf("expected email new@example.com, got %q", user.Email)
	}
	if len(repo.created) != 1 {
		t.Errorf("expected 1 user created, got %d", len(repo.created))
	}
}

func TestGoogleSignIn_ExistingByGoogleID(t *testing.T) {
	existing := &entity.User{ID: uuid.New(), Email: "old@example.com", Role: entity.RolePlayer}
	repo := newMockUserRepo()
	repo.byGoogleID["google-xyz"] = existing
	svc := service.NewAuthServiceWithVerifier(repo, nil, &fakeVerifier{
		googleID: "google-xyz", email: "old@example.com",
	}, nil)
	_, user, err := svc.GoogleSignIn(context.Background(), "fake-id-token")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if user.ID != existing.ID {
		t.Errorf("expected same user ID")
	}
	if len(repo.created) != 0 {
		t.Errorf("expected no new user created, got %d", len(repo.created))
	}
}

func TestGoogleSignIn_ExistingByEmail(t *testing.T) {
	existing := &entity.User{ID: uuid.New(), Email: "match@example.com", Role: entity.RolePlayer}
	repo := newMockUserRepo()
	repo.byEmail["match@example.com"] = existing
	svc := service.NewAuthServiceWithVerifier(repo, nil, &fakeVerifier{
		googleID: "new-google-id", email: "match@example.com",
	}, nil)
	_, user, err := svc.GoogleSignIn(context.Background(), "fake-id-token")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if user.ID != existing.ID {
		t.Errorf("expected same user from email match")
	}
}

func TestGoogleSignIn_InvalidToken(t *testing.T) {
	repo := newMockUserRepo()
	svc := service.NewAuthServiceWithVerifier(repo, nil, &fakeVerifier{
		err: errors.New("invalid token"),
	}, nil)
	_, _, err := svc.GoogleSignIn(context.Background(), "bad-token")
	if err == nil {
		t.Fatal("expected error for invalid token")
	}
}
