package service

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"gorm.io/gorm"

	"github.com/turfinn/backend/internal/config"
	"github.com/turfinn/backend/internal/domain/entity"
	domain "github.com/turfinn/backend/internal/domain/repository"
)

type MatchPostService struct {
	repo         domain.MatchPostRepository
	pitchRepo    domain.PitchRepository
	walletSvc    *WalletService
	gameSvc      *GamificationService
	reportRepo   domain.MatchReportRepository
	cancelRepo   domain.MatchCancellationRepository
	externalRepo domain.ExternalPitchRepository
	asynq        *asynq.Client
	db           *gorm.DB
	cfg          config.MatchConfig
}

func NewMatchPostService(repo domain.MatchPostRepository, walletSvc *WalletService, gameSvc *GamificationService, asynqClient *asynq.Client, db *gorm.DB) *MatchPostService {
	return &MatchPostService{
		repo:      repo,
		walletSvc: walletSvc,
		gameSvc:   gameSvc,
		asynq:     asynqClient,
		db:        db,
		cfg:       config.LoadMatchConfig(),
	}
}

// SetSafetyDeps wires optional safety repos. Kept as a setter so the existing
// constructor signature stays stable for callers that haven't been updated.
func (s *MatchPostService) SetSafetyDeps(reportRepo domain.MatchReportRepository, cancelRepo domain.MatchCancellationRepository, externalRepo domain.ExternalPitchRepository) {
	s.reportRepo = reportRepo
	s.cancelRepo = cancelRepo
	s.externalRepo = externalRepo
}

// SetPitchRepo wires the pitch repo for slot validation + per-head cost calc.
func (s *MatchPostService) SetPitchRepo(pitchRepo domain.PitchRepository) {
	s.pitchRepo = pitchRepo
}

// ExternalPitchRepo exposes the external-pitch repo so handlers can search/create.
func (s *MatchPostService) ExternalPitchRepo() domain.ExternalPitchRepository {
	return s.externalRepo
}

// Config exposes the loaded match config so handlers can apply defaults.
func (s *MatchPostService) Config() config.MatchConfig {
	return s.cfg
}

// CreateRequest is the slim input the service needs to materialize a match
// post. The handler builds this from the HTTP DTO; the service handles all
// validation, pitch lookup, slot conflict check, per-head cost calc, and
// expiry computation.
type CreateMatchPostInput struct {
	AuthorID        uuid.UUID
	PitchID         uuid.UUID
	Title           string
	Description     string
	MatchDate       time.Time
	DurationMinutes int
	Format          string
	SpotsTotal      int
	PostType        string
}

// CreateForPitch validates inputs against an existing Turfinn pitch, checks
// slot availability against confirmed bookings, and computes per-head cost
// from the pitch hourly rate. Returns the persisted match post.
func (s *MatchPostService) CreateForPitch(ctx context.Context, in CreateMatchPostInput) (*entity.MatchPost, error) {
	if s.pitchRepo == nil {
		return nil, fmt.Errorf("pitch repo not wired")
	}
	pitch, err := s.pitchRepo.FindByID(ctx, in.PitchID)
	if err != nil {
		return nil, fmt.Errorf("lookup pitch: %w", err)
	}
	if pitch == nil {
		return nil, fmt.Errorf("pitch not found")
	}
	if !pitch.IsActive {
		return nil, fmt.Errorf("pitch is not active")
	}

	duration := in.DurationMinutes
	if duration <= 0 {
		duration = s.cfg.DefaultDurationMinutes
	}
	end := in.MatchDate.Add(time.Duration(duration) * time.Minute)

	// Slot conflict check — block if another confirmed booking overlaps.
	bookings, err := s.pitchRepo.FindBookingsInRange(ctx, in.PitchID, in.MatchDate, end)
	if err != nil {
		return nil, fmt.Errorf("check bookings: %w", err)
	}
	for _, b := range bookings {
		if b.Status == "cancelled" {
			continue
		}
		// Overlap: existing.start < requested.end AND existing.end > requested.start
		if b.StartsAt.Before(end) && b.EndsAt.After(in.MatchDate) {
			return nil, fmt.Errorf("slot already booked at %s", b.StartsAt.Format("3:04 PM"))
		}
	}

	postType := in.PostType
	if postType == "" {
		postType = "open_match"
	}

	// Per-head cost = (hourly rate × duration_hours) ÷ spots
	perHead := 0
	if in.SpotsTotal > 0 && pitch.PricePerHour > 0 {
		totalCost := pitch.PricePerHour * float64(duration) / 60.0
		perHead = int(totalCost / float64(in.SpotsTotal))
	}
	perHeadPtr := &perHead

	expiresAt := end

	post := &entity.MatchPost{
		AuthorID:        in.AuthorID,
		PitchID:         &in.PitchID,
		Title:           in.Title,
		Description:     in.Description,
		MatchDate:       in.MatchDate,
		DurationMinutes: duration,
		Format:          in.Format,
		SpotsTotal:      in.SpotsTotal,
		SpotsFilled:     1,
		JoinFeeBDT:      s.cfg.JoinFeeBDT,
		PerHeadCostBDT:  perHeadPtr,
		ExpiresAt:       &expiresAt,
		PostType:        postType,
		Latitude:        pitch.Latitude,
		Longitude:       pitch.Longitude,
	}

	if err := s.repo.Create(ctx, post); err != nil {
		return nil, err
	}
	if s.asynq != nil {
		EnqueueMatchPostGamification(s.asynq, post.AuthorID, post.ID, "create")
	}
	if post.PostType == "need_teammates" && post.Latitude != 0 && s.asynq != nil {
		go s.notifyNearby(*post)
	}
	return post, nil
}

func (s *MatchPostService) notifyNearby(post entity.MatchPost) {
	ids, err := s.repo.FindNearbyUserIDs(context.Background(), post.Latitude, post.Longitude, 5.0)
	if err != nil {
		return
	}
	for _, uid := range ids {
		if uid == post.AuthorID {
			continue
		}
		enqueueFCM(s.asynq, uid, "Players Wanted Nearby!",
			"A team is looking for players in your area.",
			map[string]string{"type": "match_post_need_teammates", "post_id": post.ID.String()},
		)
	}
}

// Create — legacy direct-create entry. Kept for the few callers that still
// build the entity themselves; new callers should use CreateForPitch.
func (s *MatchPostService) Create(ctx context.Context, post *entity.MatchPost) error {
	if err := s.repo.Create(ctx, post); err != nil {
		return err
	}
	if s.asynq != nil {
		EnqueueMatchPostGamification(s.asynq, post.AuthorID, post.ID, "create")
	}
	// Notify nearby players for need_teammates posts
	if post.PostType == "need_teammates" && post.Latitude != 0 && s.asynq != nil {
		go func() {
			ids, err := s.repo.FindNearbyUserIDs(context.Background(), post.Latitude, post.Longitude, 5.0)
			if err != nil {
				return
			}
			for _, uid := range ids {
				if uid == post.AuthorID {
					continue
				}
				enqueueFCM(s.asynq, uid,
					"Match Near You!",
					"Someone is looking for teammates in your area.",
					map[string]string{"type": "nearby_match", "post_id": post.ID.String()},
				)
			}
		}()
	}
	return nil
}

func (s *MatchPostService) List(ctx context.Context, f domain.MatchPostFilter) ([]entity.MatchPost, int64, error) {
	if f.Page < 1 {
		f.Page = 1
	}
	if f.Limit < 1 {
		f.Limit = 20
	}
	if f.Limit > 50 {
		f.Limit = 50
	}
	return s.repo.List(ctx, f)
}

func (s *MatchPostService) FindByID(ctx context.Context, id uuid.UUID) (*entity.MatchPost, error) {
	return s.repo.FindByID(ctx, id)
}

// ListMine returns matches the user is involved in (hosted + joined).
func (s *MatchPostService) ListMine(ctx context.Context, userID uuid.UUID, scope string, page, limit int) ([]entity.MatchPost, int64, error) {
	return s.repo.ListMine(ctx, userID, scope, page, limit)
}

// JoinedPostIDs proxies to the repo so handlers can mark `is_joined` on
// list/detail responses.
func (s *MatchPostService) JoinedPostIDs(ctx context.Context, userID uuid.UUID, postIDs []uuid.UUID) (map[uuid.UUID]bool, error) {
	return s.repo.JoinedPostIDs(ctx, userID, postIDs)
}

func (s *MatchPostService) Join(ctx context.Context, id uuid.UUID, userID uuid.UUID) error {
	post, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return err
	}
	if post == nil {
		return fmt.Errorf("match not found")
	}
	if post.AuthorID == userID {
		// Host joins their own match — no fee, no debit.
		if err := s.repo.JoinPost(ctx, id, userID); err != nil {
			return err
		}
		if s.asynq != nil {
			EnqueueMatchPostGamification(s.asynq, userID, id, "join")
		}
		return nil
	}

	// Atomic seat reservation only — payment goes through SSLCommerz in a
	// follow-up plan. The repo's UPDATE … WHERE spots_filled < spots_total
	// is the race-safe gate; concurrent joins on the last seat result in
	// exactly one success.
	//
	// TODO(payments): replace with a payment-intent flow that opens an SSL
	// gateway session for `post.PerHeadCostBDT + post.JoinFeeBDT`. The seat
	// reservation should be a "pending" hold until the IPN confirms; a cron
	// releases holds older than ~5 minutes.
	if err := s.repo.JoinPost(ctx, id, userID); err != nil {
		return err
	}

	if s.asynq != nil {
		EnqueueMatchPostGamification(s.asynq, userID, id, "join")
	}
	go func() {
		if s.asynq == nil {
			return
		}
		enqueueFCM(s.asynq, post.AuthorID, "Someone Joined Your Match!",
			"A player has joined your match post.",
			map[string]string{"type": "match_post_join", "post_id": id.String()},
		)
	}()
	return nil
}

// Report records a complaint about a match post / venue / host.
func (s *MatchPostService) Report(ctx context.Context, postID, reporterID uuid.UUID, targetKind, reason, note string) error {
	if s.reportRepo == nil {
		return fmt.Errorf("report repo not wired")
	}
	if targetKind == "" {
		targetKind = "post"
	}
	if reason == "" {
		return fmt.Errorf("reason required")
	}
	return s.reportRepo.Create(ctx, &entity.MatchReport{
		ReporterID:  reporterID,
		MatchPostID: postID,
		TargetKind:  targetKind,
		Reason:      reason,
		Note:        note,
	})
}

func (s *MatchPostService) Delete(ctx context.Context, id uuid.UUID) error {
	return s.repo.Delete(ctx, id)
}

// UpdateUserLocation persists the caller's last-known GPS position.
func (s *MatchPostService) UpdateUserLocation(ctx context.Context, userID uuid.UUID, lat, lng float64) {
	if s.db == nil {
		return
	}
	now := time.Now()
	s.db.WithContext(ctx).Model(&entity.User{}).Where("id = ?", userID).Updates(map[string]any{
		"last_lat":            lat,
		"last_lng":            lng,
		"location_updated_at": now,
	})
}
