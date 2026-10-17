# Gamification & Data Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up existing badges/coins/wallet to mobile UI, add XP/levels, streaks, daily check-in, weekly challenges, tiered leaderboards, and referrals. Fix all hardcoded data and silent errors in the Flutter app.

**Architecture:** New `GamificationService` becomes the central coordinator — other services call it fire-and-forget after their main operation (same pattern as existing `CheckBookingBadges`). New entities/tables for XP events, streaks, check-ins, challenges, leaderboards, referrals. Flutter side gets new freezed models, remote sources, and providers to replace all hardcoded demo data.

**Tech Stack:** Go (Echo + GORM), PostgreSQL, Flutter (Riverpod + Freezed + GoRouter + Dio)

**Spec:** `docs/superpowers/specs/2026-04-11-gamification-design.md`

---

## Task 1: Database Migration — Gamification V2 Tables

**Files:**
- Create: `backend/migrations/016_gamification_v2.sql`

- [ ] **Step 1: Write the migration file**

```sql
-- 016_gamification_v2.sql
-- Gamification V2: XP, streaks, check-ins, challenges, leaderboards, referrals

-- XP columns on users
ALTER TABLE users ADD COLUMN IF NOT EXISTS xp INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS level INTEGER DEFAULT 1;

-- XP event log
CREATE TABLE IF NOT EXISTS xp_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    source VARCHAR(50) NOT NULL,
    source_id UUID,
    amount INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_xp_events_user ON xp_events(user_id);
CREATE INDEX IF NOT EXISTS idx_xp_events_created ON xp_events(created_at);

-- User streaks
CREATE TABLE IF NOT EXISTS user_streaks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) UNIQUE,
    current_streak INTEGER DEFAULT 0,
    longest_streak INTEGER DEFAULT 0,
    last_booking_week INTEGER NOT NULL DEFAULT 0,
    last_booking_year INTEGER NOT NULL DEFAULT 0,
    streak_freezes_remaining INTEGER DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Daily check-ins
CREATE TABLE IF NOT EXISTS daily_checkins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    checked_in_at DATE NOT NULL DEFAULT CURRENT_DATE,
    day_in_cycle INTEGER NOT NULL,
    coins_earned INTEGER NOT NULL,
    UNIQUE(user_id, checked_in_at)
);

-- Challenge templates (seed pool)
CREATE TABLE IF NOT EXISTS challenge_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug VARCHAR(50) UNIQUE NOT NULL,
    title VARCHAR(100) NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    type VARCHAR(30) NOT NULL,
    target INTEGER NOT NULL,
    difficulty VARCHAR(10) NOT NULL,
    coin_reward INTEGER NOT NULL,
    xp_reward INTEGER NOT NULL,
    active BOOLEAN DEFAULT true
);

-- Weekly challenge rotation
CREATE TABLE IF NOT EXISTS weekly_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    week_start DATE NOT NULL,
    challenge_template_id UUID NOT NULL REFERENCES challenge_templates(id),
    UNIQUE(week_start, challenge_template_id)
);

-- User progress per weekly challenge
CREATE TABLE IF NOT EXISTS user_challenge_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    weekly_challenge_id UUID NOT NULL REFERENCES weekly_challenges(id),
    progress INTEGER DEFAULT 0,
    completed BOOLEAN DEFAULT false,
    completed_at TIMESTAMPTZ,
    UNIQUE(user_id, weekly_challenge_id)
);

-- Leaderboard entries
CREATE TABLE IF NOT EXISTS leaderboard_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    week_start DATE NOT NULL,
    tier VARCHAR(10) NOT NULL,
    xp_earned INTEGER DEFAULT 0,
    rank INTEGER,
    reward_coins INTEGER DEFAULT 0,
    UNIQUE(user_id, week_start)
);
CREATE INDEX IF NOT EXISTS idx_leaderboard_week_tier ON leaderboard_entries(week_start, tier, xp_earned DESC);

-- Referral codes
CREATE TABLE IF NOT EXISTS referral_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) UNIQUE,
    code VARCHAR(10) UNIQUE NOT NULL,
    total_referrals INTEGER DEFAULT 0,
    total_coins_earned INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Referrals
CREATE TABLE IF NOT EXISTS referrals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id UUID NOT NULL REFERENCES users(id),
    referred_id UUID NOT NULL REFERENCES users(id) UNIQUE,
    status VARCHAR(20) DEFAULT 'pending',
    referrer_coins INTEGER DEFAULT 0,
    referred_coins INTEGER DEFAULT 0,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add wallet_transactions type for new transaction types
ALTER TABLE wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;
ALTER TABLE wallet_transactions ADD CONSTRAINT wallet_transactions_type_check
    CHECK (type IN ('topup', 'booking_payment', 'reward', 'refund', 'checkin', 'challenge', 'leaderboard', 'referral', 'streak_freeze', 'level_up'));

-- Seed streak badges
INSERT INTO badges (key, name, description, coins_reward) VALUES
    ('streak_3', '3 Week Streak', 'Booked 3 weeks in a row', 100),
    ('streak_5', '5 Week Streak', 'Booked 5 weeks in a row', 200),
    ('streak_10', '10 Week Streak', 'Booked 10 weeks in a row', 500),
    ('streak_20', '20 Week Streak', 'Booked 20 weeks in a row', 1000)
ON CONFLICT (key) DO NOTHING;

-- Seed challenge templates
INSERT INTO challenge_templates (slug, title, description, type, target, difficulty, coin_reward, xp_reward) VALUES
    ('book_2', 'Book 2 Times', 'Complete 2 bookings this week', 'booking_count', 2, 'easy', 50, 75),
    ('book_4', 'Book 4 Times', 'Complete 4 bookings this week', 'booking_count', 4, 'hard', 150, 150),
    ('new_pitch', 'Try a New Pitch', 'Book a pitch you have not visited before', 'unique_pitches', 1, 'medium', 75, 100),
    ('two_pitches', 'Visit 2 Different Pitches', 'Book at 2 different pitches this week', 'unique_pitches', 2, 'medium', 100, 125),
    ('create_post', 'Create a Match Post', 'Create a match post in the feed', 'match_posts', 1, 'easy', 50, 75),
    ('join_2_posts', 'Join 2 Match Posts', 'Join 2 match posts this week', 'match_post_joins', 2, 'medium', 75, 100),
    ('write_review', 'Write a Review', 'Leave a review on a pitch', 'reviews', 1, 'easy', 50, 75),
    ('refer_1', 'Refer a Friend', 'Invite a friend who signs up', 'referrals', 1, 'medium', 100, 125)
ON CONFLICT (slug) DO NOTHING;
```

- [ ] **Step 2: Verify migration loads cleanly**

Run: `cd backend && docker compose down -v && docker compose up -d --build`

Wait for containers to start, then:

Run: `docker compose logs postgres --tail 20`

Expected: no SQL errors, all tables created.

- [ ] **Step 3: Commit**

```bash
git add backend/migrations/016_gamification_v2.sql
git commit -m "migration: add gamification v2 tables — XP, streaks, checkins, challenges, leaderboards, referrals"
```

---

## Task 2: Backend Entities — Gamification Domain Models

**Files:**
- Modify: `backend/internal/domain/entity/user.go` (add XP, Level fields)
- Create: `backend/internal/domain/entity/gamification.go`

- [ ] **Step 1: Add XP and Level to User entity**

In `backend/internal/domain/entity/user.go`, add two fields to the `User` struct after `ReferralCode`:

```go
XP    int `gorm:"column:xp;default:0"`
Level int `gorm:"column:level;default:1"`
```

- [ ] **Step 2: Create gamification entities**

Create `backend/internal/domain/entity/gamification.go`:

```go
package entity

import (
	"time"

	"github.com/google/uuid"
)

type XPEvent struct {
	ID        uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	UserID    uuid.UUID `gorm:"type:uuid;index;not null"`
	Source    string    `gorm:"not null"` // booking, review, match_post, checkin, referral, challenge
	SourceID  *uuid.UUID `gorm:"type:uuid"`
	Amount    int       `gorm:"not null"`
	CreatedAt time.Time
}

type UserStreak struct {
	ID                    uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	UserID                uuid.UUID `gorm:"type:uuid;uniqueIndex;not null"`
	CurrentStreak         int       `gorm:"default:0"`
	LongestStreak         int       `gorm:"default:0"`
	LastBookingWeek       int       `gorm:"not null;default:0"`
	LastBookingYear       int       `gorm:"not null;default:0"`
	StreakFreezesRemaining int      `gorm:"default:0"`
	UpdatedAt             time.Time
}

type DailyCheckin struct {
	ID          uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	UserID      uuid.UUID `gorm:"type:uuid;not null"`
	CheckedInAt time.Time `gorm:"type:date;not null"`
	DayInCycle  int       `gorm:"not null"`
	CoinsEarned int       `gorm:"not null"`
}

func (DailyCheckin) TableName() string { return "daily_checkins" }

type ChallengeTemplate struct {
	ID         uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	Slug       string    `gorm:"uniqueIndex;not null"`
	Title      string    `gorm:"not null"`
	Description string
	Type       string    `gorm:"not null"` // booking_count, unique_pitches, match_posts, match_post_joins, reviews, referrals
	Target     int       `gorm:"not null"`
	Difficulty string    `gorm:"not null"` // easy, medium, hard
	CoinReward int       `gorm:"not null"`
	XPReward   int       `gorm:"not null"`
	Active     bool      `gorm:"default:true"`
}

type WeeklyChallenge struct {
	ID                  uuid.UUID          `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	WeekStart           time.Time          `gorm:"type:date;not null"`
	ChallengeTemplateID uuid.UUID          `gorm:"type:uuid;not null"`
	Template            ChallengeTemplate  `gorm:"foreignKey:ChallengeTemplateID"`
}

type UserChallengeProgress struct {
	ID                uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	UserID            uuid.UUID `gorm:"type:uuid;not null"`
	WeeklyChallengeID uuid.UUID `gorm:"type:uuid;not null"`
	Progress          int       `gorm:"default:0"`
	Completed         bool      `gorm:"default:false"`
	CompletedAt       *time.Time
}

type LeaderboardEntry struct {
	ID         uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	UserID     uuid.UUID `gorm:"type:uuid;not null"`
	WeekStart  time.Time `gorm:"type:date;not null"`
	Tier       string    `gorm:"not null"` // bronze, silver, gold
	XPEarned   int       `gorm:"default:0"`
	Rank       *int
	RewardCoins int      `gorm:"default:0"`
}

type ReferralCode struct {
	ID              uuid.UUID `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	UserID          uuid.UUID `gorm:"type:uuid;uniqueIndex;not null"`
	Code            string    `gorm:"uniqueIndex;not null"`
	TotalReferrals  int       `gorm:"default:0"`
	TotalCoinsEarned int     `gorm:"default:0"`
	CreatedAt       time.Time
}

type Referral struct {
	ID            uuid.UUID  `gorm:"type:uuid;default:gen_random_uuid();primaryKey"`
	ReferrerID    uuid.UUID  `gorm:"type:uuid;not null"`
	ReferredID    uuid.UUID  `gorm:"type:uuid;not null;uniqueIndex"`
	Status        string     `gorm:"default:pending"` // pending, completed
	ReferrerCoins int        `gorm:"default:0"`
	ReferredCoins int        `gorm:"default:0"`
	CompletedAt   *time.Time
	CreatedAt     time.Time
}

// Level thresholds — index is level number (0-indexed, so level 1 = index 0)
var LevelThresholds = []struct {
	Title     string
	XPRequired int
	CoinReward int
}{
	{"Rookie", 0, 0},        // Level 1
	{"Beginner", 200, 50},   // Level 2
	{"Regular", 500, 75},    // Level 3
	{"Enthusiast", 1000, 100}, // Level 4
	{"Veteran", 2000, 150},  // Level 5
	{"Pro", 4000, 200},      // Level 6
	{"Elite", 7500, 300},    // Level 7
	{"Champion", 12000, 500}, // Level 8
	{"Legend", 20000, 750},  // Level 9
	{"GOAT", 35000, 1000},   // Level 10
}
```

- [ ] **Step 3: Verify compilation**

Run: `cd backend && go build ./...`

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add backend/internal/domain/entity/user.go backend/internal/domain/entity/gamification.go
git commit -m "feat: add gamification domain entities — XP, streaks, checkins, challenges, leaderboards, referrals"
```

---

## Task 3: Backend Service — GamificationService (XP + Levels)

**Files:**
- Create: `backend/internal/application/service/gamification_service.go`

- [ ] **Step 1: Create the GamificationService**

```go
package service

import (
	"context"
	"fmt"
	"math/rand"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/turfinn/backend/internal/domain/entity"
	"gorm.io/gorm"
)

type GamificationService struct {
	db        *gorm.DB
	walletSvc *WalletService
}

func NewGamificationService(db *gorm.DB, walletSvc *WalletService) *GamificationService {
	return &GamificationService{db: db, walletSvc: walletSvc}
}

// AwardXP inserts an XP event, updates user.xp, checks level-up, awards coins if leveled.
func (s *GamificationService) AwardXP(ctx context.Context, userID uuid.UUID, source string, sourceID *uuid.UUID, amount int) error {
	if amount <= 0 {
		return nil
	}

	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Insert XP event
		evt := entity.XPEvent{UserID: userID, Source: source, SourceID: sourceID, Amount: amount}
		if err := tx.Create(&evt).Error; err != nil {
			return err
		}

		// Update user XP
		var user entity.User
		if err := tx.First(&user, "id = ?", userID).Error; err != nil {
			return err
		}

		oldLevel := user.Level
		user.XP += amount

		// Calculate new level
		newLevel := 1
		for i := len(entity.LevelThresholds) - 1; i >= 0; i-- {
			if user.XP >= entity.LevelThresholds[i].XPRequired {
				newLevel = i + 1
				break
			}
		}
		user.Level = newLevel

		if err := tx.Save(&user).Error; err != nil {
			return err
		}

		// Level-up coin reward
		if newLevel > oldLevel {
			reward := entity.LevelThresholds[newLevel-1].CoinReward
			if reward > 0 {
				s.walletSvc.CreditCoins(ctx, userID, reward, "level_up", fmt.Sprintf("level:%d", newLevel))
			}
		}

		// Upsert leaderboard entry for this week
		s.upsertLeaderboardXP(ctx, userID, user.Level, amount)

		return nil
	})
}

// LevelTitle returns the title for a given level.
func LevelTitle(level int) string {
	if level < 1 || level > len(entity.LevelThresholds) {
		return "Rookie"
	}
	return entity.LevelThresholds[level-1].Title
}

// XPToNextLevel returns XP remaining to reach the next level.
func XPToNextLevel(currentXP, currentLevel int) int {
	if currentLevel >= len(entity.LevelThresholds) {
		return 0 // max level
	}
	return entity.LevelThresholds[currentLevel].XPRequired - currentXP
}

// ── Event hooks — called fire-and-forget from other services ──

func (s *GamificationService) OnBookingCreated(ctx context.Context, userID uuid.UUID, bookingID uuid.UUID, startsAt time.Time) {
	xp := 100
	if startsAt.Hour() < 10 {
		xp += 50 // early bird bonus
	}
	s.AwardXP(ctx, userID, "booking", &bookingID, xp)
	s.updateStreak(ctx, userID)
	s.updateChallengeProgress(ctx, userID, "booking_count", 1)
	s.updateUniquePitchChallenge(ctx, userID, bookingID)
	s.walletSvc.CheckBookingBadges(ctx, userID, startsAt)
	s.checkStreakBadges(ctx, userID)
	s.completeReferralIfFirst(ctx, userID)
}

func (s *GamificationService) OnMatchPostCreated(ctx context.Context, userID uuid.UUID, postID uuid.UUID) {
	s.AwardXP(ctx, userID, "match_post", &postID, 40)
	s.updateChallengeProgress(ctx, userID, "match_posts", 1)
	s.walletSvc.CheckFeedBadges(ctx, userID, "create")
}

func (s *GamificationService) OnMatchPostJoined(ctx context.Context, userID uuid.UUID, postID uuid.UUID) {
	s.AwardXP(ctx, userID, "match_post", &postID, 25)
	s.updateChallengeProgress(ctx, userID, "match_post_joins", 1)
	s.walletSvc.CheckFeedBadges(ctx, userID, "join")
}

func (s *GamificationService) OnReviewCreated(ctx context.Context, userID uuid.UUID, reviewID uuid.UUID) {
	s.AwardXP(ctx, userID, "review", &reviewID, 30)
	s.updateChallengeProgress(ctx, userID, "reviews", 1)
}

func (s *GamificationService) OnReferralCompleted(ctx context.Context, referrerID uuid.UUID) {
	s.AwardXP(ctx, referrerID, "referral", nil, 200)
	s.updateChallengeProgress(ctx, referrerID, "referrals", 1)
}

// ── Streak logic ──

func (s *GamificationService) updateStreak(ctx context.Context, userID uuid.UUID) {
	now := time.Now()
	isoYear, isoWeek := now.ISOWeek()

	var streak entity.UserStreak
	err := s.db.WithContext(ctx).Where("user_id = ?", userID).First(&streak).Error
	if err == gorm.ErrRecordNotFound {
		streak = entity.UserStreak{
			UserID:          userID,
			CurrentStreak:   1,
			LongestStreak:   1,
			LastBookingWeek: isoWeek,
			LastBookingYear: isoYear,
		}
		s.db.WithContext(ctx).Create(&streak)
		return
	}
	if err != nil {
		return
	}

	// Same week — no change
	if streak.LastBookingYear == isoYear && streak.LastBookingWeek == isoWeek {
		return
	}

	// Calculate week distance
	prevWeekAbs := streak.LastBookingYear*52 + streak.LastBookingWeek
	currWeekAbs := isoYear*52 + isoWeek
	gap := currWeekAbs - prevWeekAbs

	if gap == 1 {
		// Consecutive week
		streak.CurrentStreak++
	} else if gap == 2 && streak.StreakFreezesRemaining > 0 {
		// Used a freeze
		streak.CurrentStreak++
		streak.StreakFreezesRemaining--
	} else {
		// Streak broken
		streak.CurrentStreak = 1
	}

	if streak.CurrentStreak > streak.LongestStreak {
		streak.LongestStreak = streak.CurrentStreak
	}
	streak.LastBookingWeek = isoWeek
	streak.LastBookingYear = isoYear
	streak.UpdatedAt = now

	s.db.WithContext(ctx).Save(&streak)
}

func (s *GamificationService) checkStreakBadges(ctx context.Context, userID uuid.UUID) {
	var streak entity.UserStreak
	if err := s.db.WithContext(ctx).Where("user_id = ?", userID).First(&streak).Error; err != nil {
		return
	}

	milestones := map[int]string{3: "streak_3", 5: "streak_5", 10: "streak_10", 20: "streak_20"}
	for threshold, badge := range milestones {
		if streak.CurrentStreak >= threshold {
			s.walletSvc.AwardBadge(ctx, userID, badge)
		}
	}
}

func (s *GamificationService) GetStreak(ctx context.Context, userID uuid.UUID) (*entity.UserStreak, error) {
	var streak entity.UserStreak
	err := s.db.WithContext(ctx).Where("user_id = ?", userID).First(&streak).Error
	if err == gorm.ErrRecordNotFound {
		return &entity.UserStreak{UserID: userID}, nil
	}
	return &streak, err
}

func (s *GamificationService) BuyStreakFreeze(ctx context.Context, userID uuid.UUID) error {
	const cost = 200

	// Check balance
	balance, err := s.walletSvc.GetBalance(ctx, userID)
	if err != nil {
		return err
	}
	if balance < cost {
		return fmt.Errorf("insufficient coins (need %d, have %d)", cost, balance)
	}

	var streak entity.UserStreak
	err = s.db.WithContext(ctx).Where("user_id = ?", userID).First(&streak).Error
	if err == gorm.ErrRecordNotFound {
		return fmt.Errorf("no streak record found")
	}
	if err != nil {
		return err
	}

	// Max 1 freeze at a time
	if streak.StreakFreezesRemaining > 0 {
		return fmt.Errorf("you already have a streak freeze active")
	}

	// Debit coins
	if err := s.walletSvc.DebitCoins(ctx, userID, cost, "streak_freeze", "streak_freeze"); err != nil {
		return err
	}

	streak.StreakFreezesRemaining = 1
	return s.db.WithContext(ctx).Save(&streak).Error
}

// ── Check-in logic ──

func (s *GamificationService) Checkin(ctx context.Context, userID uuid.UUID) (map[string]interface{}, error) {
	today := time.Now().Truncate(24 * time.Hour)

	// Check if already checked in today
	var existing entity.DailyCheckin
	err := s.db.WithContext(ctx).Where("user_id = ? AND checked_in_at = ?", userID, today).First(&existing).Error
	if err == nil {
		return nil, fmt.Errorf("already checked in today")
	}

	// Find yesterday's check-in to determine cycle day
	yesterday := today.Add(-24 * time.Hour)
	var prev entity.DailyCheckin
	err = s.db.WithContext(ctx).Where("user_id = ? AND checked_in_at = ?", userID, yesterday).First(&prev).Error

	dayInCycle := 1
	if err == nil {
		dayInCycle = prev.DayInCycle%7 + 1
	}

	coins := 10
	if dayInCycle == 7 {
		coins = 50
	}

	checkin := entity.DailyCheckin{
		UserID:      userID,
		CheckedInAt: today,
		DayInCycle:  dayInCycle,
		CoinsEarned: coins,
	}
	if err := s.db.WithContext(ctx).Create(&checkin).Error; err != nil {
		return nil, err
	}

	// Credit coins
	s.walletSvc.CreditCoins(ctx, userID, coins, "checkin", fmt.Sprintf("day:%d", dayInCycle))

	// Award XP
	s.AwardXP(ctx, userID, "checkin", nil, 15)

	// Build cycle status
	cycle := s.buildCheckinCycle(ctx, userID, today)

	return map[string]interface{}{
		"day":          dayInCycle,
		"coins_earned": coins,
		"cycle":        cycle,
	}, nil
}

func (s *GamificationService) GetCheckinStatus(ctx context.Context, userID uuid.UUID) map[string]interface{} {
	today := time.Now().Truncate(24 * time.Hour)

	var todayCheckin entity.DailyCheckin
	checkedIn := s.db.WithContext(ctx).Where("user_id = ? AND checked_in_at = ?", userID, today).First(&todayCheckin).Error == nil

	cycle := s.buildCheckinCycle(ctx, userID, today)

	currentDay := 0
	if checkedIn {
		currentDay = todayCheckin.DayInCycle
	}

	return map[string]interface{}{
		"checked_in_today": checkedIn,
		"current_day":      currentDay,
		"cycle":            cycle,
	}
}

func (s *GamificationService) buildCheckinCycle(ctx context.Context, userID uuid.UUID, today time.Time) []bool {
	cycle := make([]bool, 7)

	// Find the most recent check-in to determine where in cycle we are
	var recent entity.DailyCheckin
	err := s.db.WithContext(ctx).Where("user_id = ?", userID).
		Order("checked_in_at DESC").First(&recent).Error
	if err != nil {
		return cycle
	}

	// Look back up to 7 days
	for i := 0; i < 7; i++ {
		day := today.Add(-time.Duration(i) * 24 * time.Hour)
		var c entity.DailyCheckin
		if s.db.WithContext(ctx).Where("user_id = ? AND checked_in_at = ?", userID, day).First(&c).Error == nil {
			if c.DayInCycle >= 1 && c.DayInCycle <= 7 {
				cycle[c.DayInCycle-1] = true
			}
		}
	}

	return cycle
}

// ── Challenge logic ──

func (s *GamificationService) GetWeeklyChallenges(ctx context.Context, userID uuid.UUID) ([]map[string]interface{}, error) {
	weekStart := currentWeekStart()

	// Ensure challenges are rotated for this week
	s.ensureWeeklyChallenges(ctx, weekStart)

	var challenges []entity.WeeklyChallenge
	if err := s.db.WithContext(ctx).Preload("Template").
		Where("week_start = ?", weekStart).
		Find(&challenges).Error; err != nil {
		return nil, err
	}

	result := make([]map[string]interface{}, 0, len(challenges))
	for _, wc := range challenges {
		var progress entity.UserChallengeProgress
		s.db.WithContext(ctx).Where("user_id = ? AND weekly_challenge_id = ?", userID, wc.ID).First(&progress)

		result = append(result, map[string]interface{}{
			"id":          wc.ID,
			"slug":        wc.Template.Slug,
			"title":       wc.Template.Title,
			"description": wc.Template.Description,
			"type":        wc.Template.Type,
			"target":      wc.Template.Target,
			"difficulty":  wc.Template.Difficulty,
			"coin_reward": wc.Template.CoinReward,
			"xp_reward":   wc.Template.XPReward,
			"progress":    progress.Progress,
			"completed":   progress.Completed,
		})
	}

	return result, nil
}

func (s *GamificationService) ensureWeeklyChallenges(ctx context.Context, weekStart time.Time) {
	var count int64
	s.db.WithContext(ctx).Model(&entity.WeeklyChallenge{}).Where("week_start = ?", weekStart).Count(&count)
	if count > 0 {
		return
	}

	// Pick 4 challenges: 1 easy, 2 medium, 1 hard
	var easy, medium, hard []entity.ChallengeTemplate
	s.db.WithContext(ctx).Where("active = true AND difficulty = 'easy'").Find(&easy)
	s.db.WithContext(ctx).Where("active = true AND difficulty = 'medium'").Find(&medium)
	s.db.WithContext(ctx).Where("active = true AND difficulty = 'hard'").Find(&hard)

	var picks []entity.ChallengeTemplate
	if len(easy) > 0 {
		picks = append(picks, easy[rand.Intn(len(easy))])
	}
	if len(medium) >= 2 {
		rand.Shuffle(len(medium), func(i, j int) { medium[i], medium[j] = medium[j], medium[i] })
		picks = append(picks, medium[0], medium[1])
	} else if len(medium) > 0 {
		picks = append(picks, medium[0])
	}
	if len(hard) > 0 {
		picks = append(picks, hard[rand.Intn(len(hard))])
	}

	for _, tmpl := range picks {
		wc := entity.WeeklyChallenge{WeekStart: weekStart, ChallengeTemplateID: tmpl.ID}
		s.db.WithContext(ctx).Create(&wc)
	}
}

func (s *GamificationService) updateChallengeProgress(ctx context.Context, userID uuid.UUID, challengeType string, delta int) {
	weekStart := currentWeekStart()

	var challenges []entity.WeeklyChallenge
	s.db.WithContext(ctx).Preload("Template").
		Where("week_start = ?", weekStart).
		Find(&challenges)

	for _, wc := range challenges {
		if wc.Template.Type != challengeType {
			continue
		}

		// Upsert progress
		var progress entity.UserChallengeProgress
		err := s.db.WithContext(ctx).Where("user_id = ? AND weekly_challenge_id = ?", userID, wc.ID).First(&progress).Error
		if err == gorm.ErrRecordNotFound {
			progress = entity.UserChallengeProgress{UserID: userID, WeeklyChallengeID: wc.ID, Progress: delta}
			s.db.WithContext(ctx).Create(&progress)
		} else if err == nil && !progress.Completed {
			progress.Progress += delta
			s.db.WithContext(ctx).Save(&progress)
		} else {
			continue
		}

		// Check completion
		if progress.Progress >= wc.Template.Target && !progress.Completed {
			now := time.Now()
			progress.Completed = true
			progress.CompletedAt = &now
			s.db.WithContext(ctx).Save(&progress)

			// Award challenge rewards
			s.walletSvc.CreditCoins(ctx, userID, wc.Template.CoinReward, "challenge", wc.Template.Slug)
			s.AwardXP(ctx, userID, "challenge", &wc.ID, wc.Template.XPReward)

			// Check "Perfect Week" — all 4 completed
			s.checkPerfectWeek(ctx, userID, weekStart)
		}
	}
}

func (s *GamificationService) updateUniquePitchChallenge(ctx context.Context, userID uuid.UUID, bookingID uuid.UUID) {
	weekStart := currentWeekStart()

	// Count distinct pitches booked this week
	var count int64
	s.db.WithContext(ctx).Model(&entity.Booking{}).
		Where("user_id = ? AND created_at >= ? AND status IN ('pending','confirmed','completed')", userID, weekStart).
		Distinct("pitch_id").Count(&count)

	// Find unique_pitches challenges for this week
	var challenges []entity.WeeklyChallenge
	s.db.WithContext(ctx).Preload("Template").
		Where("week_start = ?", weekStart).
		Find(&challenges)

	for _, wc := range challenges {
		if wc.Template.Type != "unique_pitches" {
			continue
		}

		var progress entity.UserChallengeProgress
		err := s.db.WithContext(ctx).Where("user_id = ? AND weekly_challenge_id = ?", userID, wc.ID).First(&progress).Error
		if err == gorm.ErrRecordNotFound {
			progress = entity.UserChallengeProgress{UserID: userID, WeeklyChallengeID: wc.ID, Progress: int(count)}
			s.db.WithContext(ctx).Create(&progress)
		} else if err == nil && !progress.Completed {
			progress.Progress = int(count)
			s.db.WithContext(ctx).Save(&progress)
		}

		if int(count) >= wc.Template.Target && !progress.Completed {
			now := time.Now()
			progress.Completed = true
			progress.CompletedAt = &now
			s.db.WithContext(ctx).Save(&progress)
			s.walletSvc.CreditCoins(ctx, userID, wc.Template.CoinReward, "challenge", wc.Template.Slug)
			s.AwardXP(ctx, userID, "challenge", &wc.ID, wc.Template.XPReward)
			s.checkPerfectWeek(ctx, userID, weekStart)
		}
	}
}

func (s *GamificationService) checkPerfectWeek(ctx context.Context, userID uuid.UUID, weekStart time.Time) {
	var total, completed int64
	s.db.WithContext(ctx).Model(&entity.WeeklyChallenge{}).Where("week_start = ?", weekStart).Count(&total)

	s.db.WithContext(ctx).Model(&entity.UserChallengeProgress{}).
		Joins("JOIN weekly_challenges ON weekly_challenges.id = user_challenge_progress.weekly_challenge_id").
		Where("user_challenge_progress.user_id = ? AND weekly_challenges.week_start = ? AND user_challenge_progress.completed = true", userID, weekStart).
		Count(&completed)

	if total > 0 && completed == total {
		s.walletSvc.CreditCoins(ctx, userID, 200, "challenge", "perfect_week")
		s.AwardXP(ctx, userID, "challenge", nil, 300)
	}
}

// ── Leaderboard logic ──

func (s *GamificationService) upsertLeaderboardXP(ctx context.Context, userID uuid.UUID, userLevel, xpDelta int) {
	weekStart := currentWeekStart()
	tier := levelToTier(userLevel)

	var entry entity.LeaderboardEntry
	err := s.db.WithContext(ctx).Where("user_id = ? AND week_start = ?", userID, weekStart).First(&entry).Error
	if err == gorm.ErrRecordNotFound {
		entry = entity.LeaderboardEntry{UserID: userID, WeekStart: weekStart, Tier: tier, XPEarned: xpDelta}
		s.db.WithContext(ctx).Create(&entry)
	} else if err == nil {
		entry.XPEarned += xpDelta
		s.db.WithContext(ctx).Save(&entry)
	}
}

func (s *GamificationService) GetLeaderboard(ctx context.Context, userID uuid.UUID) (map[string]interface{}, error) {
	weekStart := currentWeekStart()

	// Get user's tier
	var user entity.User
	if err := s.db.WithContext(ctx).First(&user, "id = ?", userID).Error; err != nil {
		return nil, err
	}
	tier := levelToTier(user.Level)

	// Top 10 in tier
	var entries []entity.LeaderboardEntry
	s.db.WithContext(ctx).Where("week_start = ? AND tier = ?", weekStart, tier).
		Order("xp_earned DESC").Limit(10).Find(&entries)

	// Enrich with user names
	top := make([]map[string]interface{}, 0, len(entries))
	for i, e := range entries {
		var u entity.User
		s.db.WithContext(ctx).First(&u, "id = ?", e.UserID)
		top = append(top, map[string]interface{}{
			"rank":      i + 1,
			"user_id":   e.UserID,
			"name":      u.Name,
			"avatar_url": u.AvatarURL,
			"xp_earned": e.XPEarned,
		})
	}

	// User's own position
	var userEntry entity.LeaderboardEntry
	var userRank int64
	if s.db.WithContext(ctx).Where("user_id = ? AND week_start = ?", userID, weekStart).First(&userEntry).Error == nil {
		s.db.WithContext(ctx).Model(&entity.LeaderboardEntry{}).
			Where("week_start = ? AND tier = ? AND xp_earned > ?", weekStart, tier, userEntry.XPEarned).
			Count(&userRank)
		userRank++ // 1-indexed
	}

	return map[string]interface{}{
		"tier":          tier,
		"week_start":    weekStart.Format("2006-01-02"),
		"top":           top,
		"your_rank":     userRank,
		"your_xp":      userEntry.XPEarned,
	}, nil
}

func (s *GamificationService) GetPreviousLeaderboard(ctx context.Context, userID uuid.UUID) (map[string]interface{}, error) {
	prevWeekStart := currentWeekStart().Add(-7 * 24 * time.Hour)

	var user entity.User
	if err := s.db.WithContext(ctx).First(&user, "id = ?", userID).Error; err != nil {
		return nil, err
	}
	tier := levelToTier(user.Level)

	var entries []entity.LeaderboardEntry
	s.db.WithContext(ctx).Where("week_start = ? AND tier = ?", prevWeekStart, tier).
		Order("xp_earned DESC").Limit(10).Find(&entries)

	top := make([]map[string]interface{}, 0, len(entries))
	for i, e := range entries {
		var u entity.User
		s.db.WithContext(ctx).First(&u, "id = ?", e.UserID)
		top = append(top, map[string]interface{}{
			"rank":        i + 1,
			"user_id":     e.UserID,
			"name":        u.Name,
			"avatar_url":  u.AvatarURL,
			"xp_earned":   e.XPEarned,
			"reward_coins": e.RewardCoins,
		})
	}

	// User's result
	var userEntry entity.LeaderboardEntry
	s.db.WithContext(ctx).Where("user_id = ? AND week_start = ?", userID, prevWeekStart).First(&userEntry)

	return map[string]interface{}{
		"tier":          tier,
		"week_start":    prevWeekStart.Format("2006-01-02"),
		"top":           top,
		"your_rank":     userEntry.Rank,
		"your_xp":      userEntry.XPEarned,
		"your_reward":  userEntry.RewardCoins,
	}, nil
}

// FinalizeWeek — call via cron Monday 00:05. Ranks previous week, awards coins to top 3 per tier.
func (s *GamificationService) FinalizeWeek(ctx context.Context) error {
	prevWeekStart := currentWeekStart().Add(-7 * 24 * time.Hour)

	tiers := []string{"bronze", "silver", "gold"}
	rewards := []int{300, 200, 100} // top 1, 2, 3

	for _, tier := range tiers {
		var entries []entity.LeaderboardEntry
		s.db.WithContext(ctx).Where("week_start = ? AND tier = ? AND rank IS NULL", prevWeekStart, tier).
			Order("xp_earned DESC").Find(&entries)

		for i, e := range entries {
			rank := i + 1
			e.Rank = &rank
			if rank <= 3 {
				e.RewardCoins = rewards[rank-1]
				s.walletSvc.CreditCoins(ctx, e.UserID, rewards[rank-1], "leaderboard", fmt.Sprintf("%s_rank_%d", tier, rank))
			}
			s.db.WithContext(ctx).Save(&e)
		}
	}

	return nil
}

// ── Referral logic ──

func (s *GamificationService) GetOrCreateReferralCode(ctx context.Context, userID uuid.UUID) (*entity.ReferralCode, error) {
	var rc entity.ReferralCode
	err := s.db.WithContext(ctx).Where("user_id = ?", userID).First(&rc).Error
	if err == gorm.ErrRecordNotFound {
		rc = entity.ReferralCode{
			UserID: userID,
			Code:   generateReferralCode(),
		}
		if err := s.db.WithContext(ctx).Create(&rc).Error; err != nil {
			return nil, err
		}
	} else if err != nil {
		return nil, err
	}
	return &rc, nil
}

func (s *GamificationService) ApplyReferralCode(ctx context.Context, userID uuid.UUID, code string) error {
	code = strings.ToUpper(strings.TrimSpace(code))

	var rc entity.ReferralCode
	if err := s.db.WithContext(ctx).Where("code = ?", code).First(&rc).Error; err != nil {
		return fmt.Errorf("invalid referral code")
	}

	if rc.UserID == userID {
		return fmt.Errorf("cannot use your own referral code")
	}

	if rc.TotalReferrals >= 50 {
		return fmt.Errorf("referral code has reached maximum uses")
	}

	// Check if user already used a referral code
	var existing entity.Referral
	if s.db.WithContext(ctx).Where("referred_id = ?", userID).First(&existing).Error == nil {
		return fmt.Errorf("you have already used a referral code")
	}

	referral := entity.Referral{
		ReferrerID: rc.UserID,
		ReferredID: userID,
		Status:     "pending",
	}
	return s.db.WithContext(ctx).Create(&referral).Error
}

func (s *GamificationService) completeReferralIfFirst(ctx context.Context, userID uuid.UUID) {
	// Check if this is user's first booking
	var bookingCount int64
	s.db.WithContext(ctx).Model(&entity.Booking{}).
		Where("user_id = ? AND status IN ('pending','confirmed','completed')", userID).
		Count(&bookingCount)
	if bookingCount != 1 {
		return // not first booking
	}

	var referral entity.Referral
	if err := s.db.WithContext(ctx).Where("referred_id = ? AND status = 'pending'", userID).First(&referral).Error; err != nil {
		return
	}

	referral.Status = "completed"
	now := time.Now()
	referral.CompletedAt = &now
	referral.ReferrerCoins = 200
	referral.ReferredCoins = 100
	s.db.WithContext(ctx).Save(&referral)

	// Credit both parties
	s.walletSvc.CreditCoins(ctx, referral.ReferrerID, 200, "referral", userID.String())
	s.walletSvc.CreditCoins(ctx, userID, 100, "referral", referral.ReferrerID.String())

	// Update referral code stats
	s.db.WithContext(ctx).Model(&entity.ReferralCode{}).
		Where("user_id = ?", referral.ReferrerID).
		Updates(map[string]interface{}{
			"total_referrals":   gorm.Expr("total_referrals + 1"),
			"total_coins_earned": gorm.Expr("total_coins_earned + 200"),
		})

	// Award XP to referrer
	s.OnReferralCompleted(ctx, referral.ReferrerID)
}

func (s *GamificationService) GetReferralInfo(ctx context.Context, userID uuid.UUID) (map[string]interface{}, error) {
	rc, err := s.GetOrCreateReferralCode(ctx, userID)
	if err != nil {
		return nil, err
	}

	return map[string]interface{}{
		"code":              rc.Code,
		"total_referrals":   rc.TotalReferrals,
		"total_coins_earned": rc.TotalCoinsEarned,
	}, nil
}

// ── Helpers ──

func currentWeekStart() time.Time {
	now := time.Now()
	weekday := int(now.Weekday())
	if weekday == 0 {
		weekday = 7
	}
	monday := now.AddDate(0, 0, -(weekday - 1))
	return time.Date(monday.Year(), monday.Month(), monday.Day(), 0, 0, 0, 0, now.Location())
}

func levelToTier(level int) string {
	if level <= 3 {
		return "bronze"
	}
	if level <= 6 {
		return "silver"
	}
	return "gold"
}

func generateReferralCode() string {
	const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // no I/O/0/1 to avoid confusion
	b := make([]byte, 6)
	for i := range b {
		b[i] = chars[rand.Intn(len(chars))]
	}
	return string(b)
}
```

- [ ] **Step 2: Add CreditCoins and DebitCoins to WalletService**

In `backend/internal/application/service/wallet_service.go`, add after the `TopUp` method (after line 62):

```go
// CreditCoins adds coins to user's wallet with a transaction record.
func (s *WalletService) CreditCoins(ctx context.Context, userID uuid.UUID, amount int, txType, reference string) error {
	if amount <= 0 {
		return nil
	}
	w, err := s.GetOrCreateWallet(ctx, userID)
	if err != nil {
		return err
	}
	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&entity.Wallet{}).Where("id = ?", w.ID).
			Update("balance", gorm.Expr("balance + ?", amount)).Error; err != nil {
			return err
		}
		return tx.Create(&entity.WalletTransaction{
			WalletID:  w.ID,
			Amount:    amount,
			Type:      txType,
			Reference: reference,
		}).Error
	})
}

// DebitCoins removes coins from user's wallet with a transaction record.
func (s *WalletService) DebitCoins(ctx context.Context, userID uuid.UUID, amount int, txType, reference string) error {
	if amount <= 0 {
		return nil
	}
	w, err := s.GetOrCreateWallet(ctx, userID)
	if err != nil {
		return err
	}
	if w.Balance < amount {
		return fmt.Errorf("insufficient balance")
	}
	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&entity.Wallet{}).Where("id = ? AND balance >= ?", w.ID, amount).
			Update("balance", gorm.Expr("balance - ?", amount)).Error; err != nil {
			return err
		}
		return tx.Create(&entity.WalletTransaction{
			WalletID:  w.ID,
			Amount:    -amount,
			Type:      txType,
			Reference: reference,
		}).Error
	})
}
```

- [ ] **Step 3: Verify compilation**

Run: `cd backend && go build ./...`

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add backend/internal/application/service/gamification_service.go backend/internal/application/service/wallet_service.go
git commit -m "feat: add GamificationService — XP, levels, streaks, checkins, challenges, leaderboards, referrals"
```

---

## Task 4: Backend Handler + Routes — Gamification API

**Files:**
- Create: `backend/internal/interfaces/http/handler/gamification_handler.go`
- Modify: `backend/internal/interfaces/http/router.go`
- Modify: `backend/cmd/api/main.go`
- Modify: `backend/internal/interfaces/http/handler/wallet_handler.go` (expand GetProfile)

- [ ] **Step 1: Create the GamificationHandler**

Create `backend/internal/interfaces/http/handler/gamification_handler.go`:

```go
package handler

import (
	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/turfinn/backend/internal/application/service"
	authmw "github.com/turfinn/backend/internal/interfaces/http/middleware"
	"github.com/turfinn/backend/internal/pkg/response"
)

type GamificationHandler struct {
	svc *service.GamificationService
}

func NewGamificationHandler(svc *service.GamificationService) *GamificationHandler {
	return &GamificationHandler{svc: svc}
}

// POST /api/v1/checkin
func (h *GamificationHandler) Checkin(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	result, err := h.svc.Checkin(c.Request().Context(), userID)
	if err != nil {
		return response.BadRequest(c, err.Error())
	}
	return response.OK(c, result)
}

// GET /api/v1/checkin/status
func (h *GamificationHandler) GetCheckinStatus(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	status := h.svc.GetCheckinStatus(c.Request().Context(), userID)
	return response.OK(c, status)
}

// GET /api/v1/challenges
func (h *GamificationHandler) GetChallenges(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	challenges, err := h.svc.GetWeeklyChallenges(c.Request().Context(), userID)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, challenges)
}

// GET /api/v1/leaderboard
func (h *GamificationHandler) GetLeaderboard(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	lb, err := h.svc.GetLeaderboard(c.Request().Context(), userID)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, lb)
}

// GET /api/v1/leaderboard/previous
func (h *GamificationHandler) GetPreviousLeaderboard(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	lb, err := h.svc.GetPreviousLeaderboard(c.Request().Context(), userID)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, lb)
}

// GET /api/v1/referral
func (h *GamificationHandler) GetReferral(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	info, err := h.svc.GetReferralInfo(c.Request().Context(), userID)
	if err != nil {
		return response.InternalError(c)
	}
	return response.OK(c, info)
}

// POST /api/v1/referral/apply  body: {"code": "ABC123"}
func (h *GamificationHandler) ApplyReferral(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	var req struct {
		Code string `json:"code" validate:"required"`
	}
	if err := c.Bind(&req); err != nil {
		return response.BadRequest(c, "invalid request")
	}
	if err := h.svc.ApplyReferralCode(c.Request().Context(), userID, req.Code); err != nil {
		return response.BadRequest(c, err.Error())
	}
	return response.OK(c, map[string]string{"status": "applied"})
}

// POST /api/v1/store/streak-freeze
func (h *GamificationHandler) BuyStreakFreeze(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	if err := h.svc.BuyStreakFreeze(c.Request().Context(), userID); err != nil {
		return response.BadRequest(c, err.Error())
	}
	return response.OK(c, map[string]string{"status": "purchased"})
}
```

- [ ] **Step 2: Expand GetProfile in WalletHandler**

In `backend/internal/interfaces/http/handler/wallet_handler.go`, the `WalletHandler` struct needs access to `GamificationService`. Change the struct and constructor:

Replace the existing struct and constructor (lines 13-19):

```go
type WalletHandler struct {
	svc     *service.WalletService
	gameSvc *service.GamificationService
}

func NewWalletHandler(svc *service.WalletService, gameSvc *service.GamificationService) *WalletHandler {
	return &WalletHandler{svc: svc, gameSvc: gameSvc}
}
```

Replace the `GetProfile` method (lines 78-85) to include gamification data:

```go
// GET /api/v1/profile
func (h *WalletHandler) GetProfile(c echo.Context) error {
	userID := c.Get(authmw.UserIDKey).(uuid.UUID)
	profile, err := h.svc.GetProfile(c.Request().Context(), userID)
	if err != nil {
		return response.InternalError(c)
	}

	// Enrich with gamification data
	streak, _ := h.gameSvc.GetStreak(c.Request().Context(), userID)
	referral, _ := h.gameSvc.GetOrCreateReferralCode(c.Request().Context(), userID)

	profile["xp"] = profile["xp"] // will come from user entity after Task 2
	// Read XP and level from user directly
	ctx := c.Request().Context()
	var user struct {
		XP    int
		Level int
	}
	h.gameSvc.DB().WithContext(ctx).Model(&struct{}{}).Table("users").Select("xp, level").Where("id = ?", userID).Scan(&user)

	profile["xp"] = user.XP
	profile["level"] = user.Level
	profile["level_title"] = service.LevelTitle(user.Level)
	profile["xp_to_next_level"] = service.XPToNextLevel(user.XP, user.Level)
	profile["current_streak"] = streak.CurrentStreak
	profile["longest_streak"] = streak.LongestStreak
	profile["streak_freezes"] = streak.StreakFreezesRemaining
	profile["referral_code"] = referral.Code

	return response.OK(c, profile)
}
```

Also add a `DB()` accessor to `GamificationService` (append to `gamification_service.go`):

```go
func (s *GamificationService) DB() *gorm.DB { return s.db }
```

- [ ] **Step 3: Also fix the ListTransactions bug**

In `wallet_handler.go` line 68, there's a typo: `"68"` should be `"amount"`. Fix:

```go
"amount":     t.Amount,
```

- [ ] **Step 4: Register routes in router.go**

In `backend/internal/interfaces/http/router.go`, add after the wallet/profile route block (after line 152):

```go
// Gamification (auth required)
gamification := v1.Group("", authmw.Auth())
gamification.POST("/checkin", gamificationH.Checkin)
gamification.GET("/checkin/status", gamificationH.GetCheckinStatus)
gamification.GET("/challenges", gamificationH.GetChallenges)
gamification.GET("/leaderboard", gamificationH.GetLeaderboard)
gamification.GET("/leaderboard/previous", gamificationH.GetPreviousLeaderboard)
gamification.GET("/referral", gamificationH.GetReferral)
gamification.POST("/referral/apply", gamificationH.ApplyReferral)
gamification.POST("/store/streak-freeze", gamificationH.BuyStreakFreeze)
```

The router function signature needs to accept `gamificationH`:

Add `gamificationH *handler.GamificationHandler` as a parameter to `RegisterRoutes`.

- [ ] **Step 5: Wire in main.go**

In `backend/cmd/api/main.go`, after the `walletSvc` line (line 89):

```go
gamificationSvc := service.NewGamificationService(db, walletSvc)
```

Update `bookingSvc` to use `gamificationSvc` instead of just `walletSvc` (we'll do this in Task 5).

After the `walletH` line (line 108), add:

```go
gamificationH := handler.NewGamificationHandler(gamificationSvc)
```

Update `NewWalletHandler` call to pass `gamificationSvc`:

```go
walletH := handler.NewWalletHandler(walletSvc, gamificationSvc)
```

Pass `gamificationH` to `RegisterRoutes`.

- [ ] **Step 6: Verify compilation**

Run: `cd backend && go build ./...`

Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add backend/internal/interfaces/http/handler/gamification_handler.go \
       backend/internal/interfaces/http/handler/wallet_handler.go \
       backend/internal/interfaces/http/router.go \
       backend/cmd/api/main.go
git commit -m "feat: add gamification API endpoints — checkin, challenges, leaderboard, referral, streak-freeze"
```

---

## Task 5: Backend — Hook GamificationService into Existing Services

**Files:**
- Modify: `backend/internal/application/service/booking_service.go`
- Modify: `backend/internal/application/service/match_post_service.go`

- [ ] **Step 1: Update BookingService to use GamificationService**

The `BookingService` struct currently holds `walletSvc *WalletService`. Add `gameSvc *GamificationService` and update the constructor.

In `booking_service.go`, update the struct:

```go
type BookingService struct {
	bookingRepo domain.BookingRepository
	pitchRepo   domain.PitchRepository
	walletSvc   *WalletService
	gameSvc     *GamificationService
	db          *gorm.DB
}

func NewBookingService(bookingRepo domain.BookingRepository, pitchRepo domain.PitchRepository, walletSvc *WalletService, gameSvc *GamificationService, db *gorm.DB) *BookingService {
	return &BookingService{
		bookingRepo: bookingRepo,
		pitchRepo:   pitchRepo,
		walletSvc:   walletSvc,
		gameSvc:     gameSvc,
		db:          db,
	}
}
```

Replace the fire-and-forget badge line (line 94):

```go
// Fire-and-forget gamification hooks — do not block or fail the booking
go s.gameSvc.OnBookingCreated(ctx, userID, booking.ID, req.StartsAt)
```

- [ ] **Step 2: Update MatchPostService to use GamificationService**

In `match_post_service.go`, update the struct:

```go
type MatchPostService struct {
	repo      domain.MatchPostRepository
	walletSvc *WalletService
	gameSvc   *GamificationService
}

func NewMatchPostService(repo domain.MatchPostRepository, walletSvc *WalletService, gameSvc *GamificationService) *MatchPostService {
	return &MatchPostService{repo: repo, walletSvc: walletSvc, gameSvc: gameSvc}
}
```

Replace the fire-and-forget lines in `Create` and `Join`:

```go
func (s *MatchPostService) Create(ctx context.Context, post *entity.MatchPost) error {
	if err := s.repo.Create(ctx, post); err != nil {
		return err
	}
	go s.gameSvc.OnMatchPostCreated(ctx, post.AuthorID, post.ID)
	return nil
}

func (s *MatchPostService) Join(ctx context.Context, id uuid.UUID, userID uuid.UUID) error {
	if err := s.repo.JoinPost(ctx, id, userID); err != nil {
		return err
	}
	go s.gameSvc.OnMatchPostJoined(ctx, userID, id)
	return nil
}
```

- [ ] **Step 3: Update main.go wiring**

In `main.go`, update the service construction order:

```go
walletSvc := service.NewWalletService(db)
gamificationSvc := service.NewGamificationService(db, walletSvc)
bookingSvc := service.NewBookingService(bookingRepo, pitchRepo, walletSvc, gamificationSvc, db)
matchPostSvc := service.NewMatchPostService(matchPostRepo, walletSvc, gamificationSvc)
```

- [ ] **Step 4: Verify compilation**

Run: `cd backend && go build ./...`

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/application/service/booking_service.go \
       backend/internal/application/service/match_post_service.go \
       backend/cmd/api/main.go
git commit -m "feat: hook GamificationService into booking and feed flows"
```

---

## Task 6: Flutter Models — Gamification Freezed Models

**Files:**
- Create: `lib/data/models/gamification_models.dart`

- [ ] **Step 1: Create gamification models**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'gamification_models.freezed.dart';
part 'gamification_models.g.dart';

@freezed
class PlayerProfile with _$PlayerProfile {
  const factory PlayerProfile({
    required String id,
    @Default('') String name,
    @Default('') String phone,
    @Default('') String role,
    @Default('') @JsonKey(name: 'avatar_url') String avatarUrl,
    @Default(0) int xp,
    @Default(1) int level,
    @Default('Rookie') @JsonKey(name: 'level_title') String levelTitle,
    @Default(0) @JsonKey(name: 'xp_to_next_level') int xpToNextLevel,
    @Default(0) @JsonKey(name: 'coins_balance') int coinsBalance,
    @Default(0) @JsonKey(name: 'total_bookings') int totalBookings,
    @Default(0) @JsonKey(name: 'current_streak') int currentStreak,
    @Default(0) @JsonKey(name: 'longest_streak') int longestStreak,
    @Default(0) @JsonKey(name: 'streak_freezes') int streakFreezes,
    @Default('') @JsonKey(name: 'referral_code') String referralCode,
    @Default([]) List<PlayerBadge> badges,
  }) = _PlayerProfile;

  factory PlayerProfile.fromJson(Map<String, dynamic> json) =>
      _$PlayerProfileFromJson(json);
}

@freezed
class PlayerBadge with _$PlayerBadge {
  const factory PlayerBadge({
    required String key,
    required String name,
    @Default('') String description,
    @JsonKey(name: 'earned_at') String? earnedAt,
  }) = _PlayerBadge;

  factory PlayerBadge.fromJson(Map<String, dynamic> json) =>
      _$PlayerBadgeFromJson(json);
}

@freezed
class CheckinStatus with _$CheckinStatus {
  const factory CheckinStatus({
    @Default(false) @JsonKey(name: 'checked_in_today') bool checkedInToday,
    @Default(0) @JsonKey(name: 'current_day') int currentDay,
    @Default([]) List<bool> cycle,
  }) = _CheckinStatus;

  factory CheckinStatus.fromJson(Map<String, dynamic> json) =>
      _$CheckinStatusFromJson(json);
}

@freezed
class CheckinResult with _$CheckinResult {
  const factory CheckinResult({
    @Default(0) int day,
    @Default(0) @JsonKey(name: 'coins_earned') int coinsEarned,
    @Default([]) List<bool> cycle,
  }) = _CheckinResult;

  factory CheckinResult.fromJson(Map<String, dynamic> json) =>
      _$CheckinResultFromJson(json);
}

@freezed
class Challenge with _$Challenge {
  const factory Challenge({
    required String id,
    required String slug,
    required String title,
    @Default('') String description,
    required String type,
    required int target,
    required String difficulty,
    @Default(0) @JsonKey(name: 'coin_reward') int coinReward,
    @Default(0) @JsonKey(name: 'xp_reward') int xpReward,
    @Default(0) int progress,
    @Default(false) bool completed,
  }) = _Challenge;

  factory Challenge.fromJson(Map<String, dynamic> json) =>
      _$ChallengeFromJson(json);
}

@freezed
class LeaderboardResult with _$LeaderboardResult {
  const factory LeaderboardResult({
    @Default('bronze') String tier,
    @Default('') @JsonKey(name: 'week_start') String weekStart,
    @Default([]) List<LeaderboardEntry> top,
    @Default(0) @JsonKey(name: 'your_rank') int yourRank,
    @Default(0) @JsonKey(name: 'your_xp') int yourXP,
    @Default(0) @JsonKey(name: 'your_reward') int yourReward,
  }) = _LeaderboardResult;

  factory LeaderboardResult.fromJson(Map<String, dynamic> json) =>
      _$LeaderboardResultFromJson(json);
}

@freezed
class LeaderboardEntry with _$LeaderboardEntry {
  const factory LeaderboardEntry({
    @Default(0) int rank,
    @Default('') @JsonKey(name: 'user_id') String userId,
    @Default('') String name,
    @Default('') @JsonKey(name: 'avatar_url') String avatarUrl,
    @Default(0) @JsonKey(name: 'xp_earned') int xpEarned,
    @Default(0) @JsonKey(name: 'reward_coins') int rewardCoins,
  }) = _LeaderboardEntry;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      _$LeaderboardEntryFromJson(json);
}

@freezed
class ReferralInfo with _$ReferralInfo {
  const factory ReferralInfo({
    @Default('') String code,
    @Default(0) @JsonKey(name: 'total_referrals') int totalReferrals,
    @Default(0) @JsonKey(name: 'total_coins_earned') int totalCoinsEarned,
  }) = _ReferralInfo;

  factory ReferralInfo.fromJson(Map<String, dynamic> json) =>
      _$ReferralInfoFromJson(json);
}
```

- [ ] **Step 2: Run build_runner**

Run: `dart run build_runner build --delete-conflicting-outputs`

Expected: generates `.freezed.dart` and `.g.dart` files with no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/data/models/gamification_models.dart lib/data/models/gamification_models.freezed.dart lib/data/models/gamification_models.g.dart
git commit -m "feat: add Flutter gamification freezed models"
```

---

## Task 7: Flutter Remote Source — Gamification API Client

**Files:**
- Create: `lib/data/sources/remote/gamification_remote_source.dart`

- [ ] **Step 1: Create the remote source**

```dart
import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../models/gamification_models.dart';
import 'dio_client.dart';

part 'gamification_remote_source.g.dart';

@riverpod
GamificationRemoteSource gamificationRemoteSource(GamificationRemoteSourceRef ref) =>
    GamificationRemoteSource(ref.watch(dioProvider));

class GamificationRemoteSource {
  GamificationRemoteSource(this._dio);
  final Dio _dio;

  Future<PlayerProfile> getProfile() async {
    final resp = await _dio.get('/profile');
    return PlayerProfile.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<int> getWalletBalance() async {
    final resp = await _dio.get('/wallet');
    return (resp.data['data']['balance'] as num).toInt();
  }

  Future<CheckinStatus> getCheckinStatus() async {
    final resp = await _dio.get('/checkin/status');
    return CheckinStatus.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<CheckinResult> checkin() async {
    final resp = await _dio.post('/checkin');
    return CheckinResult.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<List<Challenge>> getChallenges() async {
    final resp = await _dio.get('/challenges');
    final data = resp.data['data'] as List;
    return data.map((e) => Challenge.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<LeaderboardResult> getLeaderboard() async {
    final resp = await _dio.get('/leaderboard');
    return LeaderboardResult.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<LeaderboardResult> getPreviousLeaderboard() async {
    final resp = await _dio.get('/leaderboard/previous');
    return LeaderboardResult.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<ReferralInfo> getReferralInfo() async {
    final resp = await _dio.get('/referral');
    return ReferralInfo.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<void> applyReferralCode(String code) async {
    await _dio.post('/referral/apply', data: {'code': code});
  }

  Future<void> buyStreakFreeze() async {
    await _dio.post('/store/streak-freeze');
  }
}
```

- [ ] **Step 2: Run build_runner**

Run: `dart run build_runner build --delete-conflicting-outputs`

Expected: generates `.g.dart` for the provider.

- [ ] **Step 3: Commit**

```bash
git add lib/data/sources/remote/gamification_remote_source.dart lib/data/sources/remote/gamification_remote_source.g.dart
git commit -m "feat: add gamification remote source — profile, checkin, challenges, leaderboard, referral"
```

---

## Task 8: Flutter Providers — Gamification State

**Files:**
- Create: `lib/presentation/providers/gamification_provider.dart`

- [ ] **Step 1: Create providers**

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/gamification_models.dart';
import '../../data/sources/remote/gamification_remote_source.dart';

part 'gamification_provider.g.dart';

@riverpod
Future<PlayerProfile> playerProfile(PlayerProfileRef ref) async {
  return ref.watch(gamificationRemoteSourceProvider).getProfile();
}

@riverpod
Future<int> walletBalance(WalletBalanceRef ref) async {
  return ref.watch(gamificationRemoteSourceProvider).getWalletBalance();
}

@riverpod
Future<CheckinStatus> checkinStatus(CheckinStatusRef ref) async {
  return ref.watch(gamificationRemoteSourceProvider).getCheckinStatus();
}

@riverpod
Future<List<Challenge>> weeklyChallenges(WeeklyChallengesRef ref) async {
  return ref.watch(gamificationRemoteSourceProvider).getChallenges();
}

@riverpod
Future<LeaderboardResult> leaderboard(LeaderboardRef ref) async {
  return ref.watch(gamificationRemoteSourceProvider).getLeaderboard();
}

@riverpod
Future<ReferralInfo> referralInfo(ReferralInfoRef ref) async {
  return ref.watch(gamificationRemoteSourceProvider).getReferralInfo();
}

@riverpod
class CheckinNotifier extends _$CheckinNotifier {
  @override
  AsyncValue<CheckinResult?> build() => const AsyncData(null);

  Future<void> checkin() async {
    state = const AsyncLoading();
    try {
      final result = await ref.read(gamificationRemoteSourceProvider).checkin();
      state = AsyncData(result);
      // Refresh dependent providers
      ref.invalidate(checkinStatusProvider);
      ref.invalidate(playerProfileProvider);
      ref.invalidate(walletBalanceProvider);
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
    }
  }
}
```

- [ ] **Step 2: Run build_runner**

Run: `dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/providers/gamification_provider.dart lib/presentation/providers/gamification_provider.g.dart
git commit -m "feat: add gamification Riverpod providers"
```

---

## Task 9: Fix Home Screen — Replace Hardcoded Data

**Files:**
- Modify: `lib/presentation/screens/home/home_screen.dart`

- [ ] **Step 1: Add gamification imports and replace hardcoded wallet balance**

At top of file, add import:

```dart
import '../../providers/gamification_provider.dart';
```

In the `build` method, add provider watches:

```dart
final walletAsync = ref.watch(walletBalanceProvider);
final checkinAsync = ref.watch(checkinStatusProvider);
final challengesAsync = ref.watch(weeklyChallengesProvider);
final gameProfileAsync = ref.watch(playerProfileProvider);
```

Replace the hardcoded `'BashirulHana'` fallback (line 25):

```dart
final userName = profileAsync.valueOrNull?.name.isNotEmpty == true
    ? profileAsync.valueOrNull!.name
    : 'Player';
```

Replace the hardcoded `'5,000 BDT'` text (line 123) with:

```dart
Text(
  walletAsync.when(
    data: (b) => '${b.toStringAsFixed(0)} coins',
    loading: () => '...',
    error: (_, __) => '0 coins',
  ),
  style: GoogleFonts.dmSans(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  ),
),
```

Replace the subtitle `'Player'` (line 87-89) with the level title:

```dart
Text(
  gameProfileAsync.valueOrNull?.levelTitle ?? 'Player',
  style: GoogleFonts.dmSans(
    fontSize: 11,
    color: AppColors.textSecondary,
  ),
),
```

- [ ] **Step 2: Add check-in card before the "Weekend Cup Banner"**

Insert a new `SliverToBoxAdapter` after the top bar and before the Weekend Cup banner. This shows the 7-day check-in cycle:

```dart
// ── Daily Check-in Card ──
SliverToBoxAdapter(
  child: checkinAsync.when(
    loading: () => const SizedBox.shrink(),
    error: (_, __) => const SizedBox.shrink(),
    data: (status) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: GestureDetector(
        onTap: status.checkedInToday
            ? null
            : () async {
                await ref.read(checkinNotifierProvider.notifier).checkin();
              },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1F1A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primaryDeep.withOpacity(0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    status.checkedInToday ? 'Checked In' : 'Daily Check-in',
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (!status.checkedInToday)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Tap to collect',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.background,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(7, (i) {
                  final done = i < status.cycle.length && status.cycle[i];
                  return Column(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: done
                              ? AppColors.primary.withOpacity(0.2)
                              : const Color(0xFF0D2A22),
                          border: Border.all(
                            color: done ? AppColors.primary : AppColors.primaryDeep,
                            width: done ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: done
                              ? const Icon(Icons.check, size: 16, color: AppColors.primary)
                              : Text(
                                  '${i + 1}',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        i == 6 ? '50' : '10',
                        style: GoogleFonts.dmSans(
                          fontSize: 9,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
),
```

- [ ] **Step 3: Replace hardcoded milestones with weekly challenges**

Find the milestones section (around lines 220-238) and replace with:

```dart
// ── Weekly Challenges ──
SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Weekly Challenges',
            style: GoogleFonts.nunito(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        challengesAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (_, __) => Text('Could not load challenges',
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: AppColors.textSecondary)),
          data: (challenges) => Column(
            children: challenges.map((c) {
              final pct = c.target > 0 ? (c.progress / c.target).clamp(0.0, 1.0) : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1F1A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: c.completed
                          ? AppColors.primary.withOpacity(0.4)
                          : AppColors.primaryDeep.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.title,
                                style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: c.completed
                                        ? AppColors.primary
                                        : AppColors.textPrimary)),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: pct,
                                backgroundColor: const Color(0xFF0D2A22),
                                valueColor: AlwaysStoppedAnimation(
                                  c.completed
                                      ? AppColors.primary
                                      : AppColors.primaryMid,
                                ),
                                minHeight: 6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        c.completed ? 'Done' : '${c.progress}/${c.target}',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.completed
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    ),
  ),
),
```

- [ ] **Step 4: Add streak display next to "Your Next Match"**

In the "Your Next Match" section, add a streak flame if the user has a streak:

```dart
if ((gameProfileAsync.valueOrNull?.currentStreak ?? 0) > 0)
  Padding(
    padding: const EdgeInsets.only(left: 8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1A00),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department, size: 14, color: Color(0xFFFF9500)),
          const SizedBox(width: 3),
          Text(
            '${gameProfileAsync.valueOrNull!.currentStreak}w',
            style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFFFF9500)),
          ),
        ],
      ),
    ),
  ),
```

- [ ] **Step 5: Verify compilation**

Run: `flutter analyze`

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/screens/home/home_screen.dart
git commit -m "fix: replace hardcoded data on home screen — real wallet, checkin, challenges, streak"
```

---

## Task 10: Fix Profile Screen — Real Stats, Badges, XP, Referral

**Files:**
- Modify: `lib/presentation/screens/profile/profile_screen.dart`

- [ ] **Step 1: Replace profile provider and add gamification imports**

Add imports at top:

```dart
import '../../providers/gamification_provider.dart';
import '../../../data/models/gamification_models.dart';
```

In the `build` method, watch the player profile instead of the user profile:

```dart
final gameProfileAsync = ref.watch(playerProfileProvider);
```

Replace the `profileAsync.when` block to use `gameProfileAsync`:

```dart
body: SafeArea(
  child: gameProfileAsync.when(
    loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary)),
    error: (_, __) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Could not load profile',
              style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => ref.invalidate(playerProfileProvider),
            child: Text('Retry', style: GoogleFonts.dmSans(color: AppColors.primary)),
          ),
        ],
      ),
    ),
    data: (profile) => _buildContent(context, ref, profile),
  ),
),
```

- [ ] **Step 2: Update _buildContent to use PlayerProfile**

Change the method signature:

```dart
Widget _buildContent(BuildContext context, WidgetRef ref, PlayerProfile profile) {
```

Replace the hardcoded fallback name (line 33):

```dart
final name = profile.name.isNotEmpty ? profile.name : 'Player';
```

Replace `'Pro Player'` label with level title:

```dart
Text(
  'Level ${profile.level} — ${profile.levelTitle}',
  style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.primaryMid),
),
```

- [ ] **Step 3: Add XP progress bar under level title**

After the level title text widget:

```dart
const SizedBox(height: 8),
// XP Progress bar
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 40),
  child: Column(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: profile.xpToNextLevel > 0
              ? 1 - (profile.xpToNextLevel / (profile.xp + profile.xpToNextLevel))
              : 1.0,
          backgroundColor: const Color(0xFF0D2A22),
          valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          minHeight: 6,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        profile.level >= 10
            ? 'MAX LEVEL'
            : '${profile.xp} / ${profile.xp + profile.xpToNextLevel} XP',
        style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textSecondary),
      ),
    ],
  ),
),
```

- [ ] **Step 4: Replace hardcoded stats with real data**

Replace the stats section (lines 131-148) with:

```dart
Row(
  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
  children: [
    _StatItem(label: 'Bookings', value: '${profile.totalBookings}'),
    _StatItem(label: 'Streak', value: '${profile.currentStreak}w'),
    _StatItem(label: 'Coins', value: '${profile.coinsBalance}'),
    _StatItem(label: 'Level', value: '${profile.level}'),
  ],
),
```

- [ ] **Step 5: Add badges grid**

Replace any existing badges placeholder or add after the stats:

```dart
// ── Badges ──
if (profile.badges.isNotEmpty) ...[
  const SizedBox(height: 20),
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Badges',
            style: GoogleFonts.nunito(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: profile.badges.map((badge) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1F1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primaryDeep),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.emoji_events, color: AppColors.primary, size: 24),
                  const SizedBox(height: 4),
                  Text(badge.name,
                      style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    ),
  ),
],
```

- [ ] **Step 6: Add referral card**

After badges section:

```dart
// ── Invite Friends ──
const SizedBox(height: 20),
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 18),
  child: GestureDetector(
    onTap: () {
      Share.share(
        'Join me on Turfinn! Use code ${profile.referralCode} for 100 bonus coins.',
      );
    },
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF062E22), Color(0xFF051A14)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryDeep),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Invite Friends',
                    style: GoogleFonts.nunito(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text('Share code ${profile.referralCode} — both get coins!',
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const Icon(Icons.share, color: AppColors.primary, size: 22),
        ],
      ),
    ),
  ),
),
```

- [ ] **Step 7: Verify compilation**

Run: `flutter analyze`

Expected: no errors.

- [ ] **Step 8: Commit**

```bash
git add lib/presentation/screens/profile/profile_screen.dart
git commit -m "fix: profile screen — real stats, badges, XP bar, level, referral card"
```

---

## Task 11: Fix Feed Screen — Replace Hardcoded Posts with API

**Files:**
- Modify: `lib/presentation/screens/feed/feed_screen.dart`
- Verify: `lib/presentation/providers/feed_provider.dart` (create if missing)

- [ ] **Step 1: Create feed provider if it doesn't exist**

Check if `lib/presentation/providers/feed_provider.dart` exists. If not, create it:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/match_post_model.dart';
import '../../data/sources/remote/feed_remote_source.dart';

part 'feed_provider.g.dart';

@riverpod
Future<List<MatchPostModel>> feedPosts(FeedPostsRef ref) async {
  return ref.watch(feedRemoteSourceProvider).listPosts();
}
```

Run: `dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 2: Replace hardcoded feed data**

In `feed_screen.dart`, remove the static `_posts` list (lines 12-45) and the `_Post` class.

Add imports:

```dart
import '../../providers/gamification_provider.dart';
import '../../providers/feed_provider.dart';
```

In the `build` method, replace `_posts` usage with:

```dart
final feedAsync = ref.watch(feedPostsProvider);
```

Replace the hardcoded `'BashirulHana'` fallback (line 52):

```dart
final userName = profileAsync.valueOrNull?.name.isNotEmpty == true
    ? profileAsync.valueOrNull!.name
    : 'Player';
```

Replace the hardcoded `'5,000 BDT'` wallet chip with:

```dart
final walletAsync = ref.watch(walletBalanceProvider);
// ...
Text(
  walletAsync.when(
    data: (b) => '${b.toStringAsFixed(0)} coins',
    loading: () => '...',
    error: (_, __) => '0 coins',
  ),
  // ...
),
```

Replace the `SliverList` that renders `_posts` with a feed async handler:

```dart
feedAsync.when(
  loading: () => const SliverToBoxAdapter(
    child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
  ),
  error: (_, __) => SliverToBoxAdapter(
    child: Center(
      child: Text('Could not load feed',
          style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
    ),
  ),
  data: (posts) => posts.isEmpty
      ? SliverToBoxAdapter(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Text('No posts yet. Create one!',
                  style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
            ),
          ),
        )
      : SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final post = posts[index];
              // Render the post card using MatchPostModel fields
              // ... (adapt existing card layout to use post.authorName, post.content, etc.)
            },
            childCount: posts.length,
          ),
        ),
),
```

- [ ] **Step 3: Verify compilation**

Run: `flutter analyze`

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/feed/feed_screen.dart lib/presentation/providers/feed_provider.dart lib/presentation/providers/feed_provider.g.dart
git commit -m "fix: feed screen — replace hardcoded posts with real API data, fix wallet display"
```

---

## Task 12: Fix Booking Provider — Silent Error + Activity Screen

**Files:**
- Modify: `lib/presentation/providers/booking_provider.dart`
- Modify: `lib/presentation/screens/profile/activity_screen.dart`

- [ ] **Step 1: Fix silent catch in booking cancel**

In `booking_provider.dart`, replace the `cancel` method (lines 51-56):

```dart
Future<bool> cancel(String id) async {
  try {
    await ref.read(bookingRemoteSourceProvider).cancelBooking(id);
    ref.invalidate(myBookingsProvider);
    return true;
  } catch (e) {
    state = BookingError('Failed to cancel booking. Try again.');
    return false;
  }
}
```

- [ ] **Step 2: Fix hardcoded status in activity screen**

In `activity_screen.dart`, find the hardcoded `'Confirmed'` status display (around line 215) and replace with the actual booking status:

```dart
Text(
  booking.status[0].toUpperCase() + booking.status.substring(1),
  style: GoogleFonts.dmSans(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: booking.status == 'confirmed'
        ? AppColors.primary
        : booking.status == 'cancelled'
            ? const Color(0xFFFF4444)
            : AppColors.textSecondary,
  ),
),
```

- [ ] **Step 3: Add proper empty state in activity screen**

Find the empty state (around line 137) and replace:

```dart
Center(
  child: Padding(
    padding: const EdgeInsets.all(40),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.sports_soccer, size: 48, color: AppColors.primaryDeep),
        const SizedBox(height: 12),
        Text('No bookings yet',
            style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text('Book a pitch to see your activity here',
            style: GoogleFonts.dmSans(
                fontSize: 13, color: AppColors.textSecondary)),
      ],
    ),
  ),
),
```

- [ ] **Step 4: Add error retry in activity screen**

Replace the error state (around line 78-81):

```dart
Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Could not load bookings',
          style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => ref.invalidate(myBookingsProvider),
        child: Text('Retry', style: GoogleFonts.dmSans(color: AppColors.primary)),
      ),
    ],
  ),
),
```

- [ ] **Step 5: Invalidate gamification providers after booking**

In `booking_provider.dart`, after successful booking creation (line 45), add:

```dart
ref.invalidate(myBookingsProvider);
ref.invalidate(playerProfileProvider);
ref.invalidate(walletBalanceProvider);
ref.invalidate(weeklyChallengesProvider);
```

Add import at top:

```dart
import 'gamification_provider.dart';
```

- [ ] **Step 6: Verify compilation**

Run: `flutter analyze`

- [ ] **Step 7: Commit**

```bash
git add lib/presentation/providers/booking_provider.dart lib/presentation/screens/profile/activity_screen.dart
git commit -m "fix: booking cancel error handling, activity screen status display + empty/error states"
```

---

## Task 13: Add Leaderboard Screen + Route

**Files:**
- Create: `lib/presentation/screens/leaderboard/leaderboard_screen.dart`
- Modify: `lib/core/router/app_router.dart`

- [ ] **Step 1: Create leaderboard screen**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/gamification_models.dart';
import '../../providers/gamification_provider.dart';

class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lbAsync = ref.watch(leaderboardProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Leaderboard',
            style: GoogleFonts.nunito(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: lbAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not load leaderboard',
                  style: GoogleFonts.dmSans(
                      fontSize: 14, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(leaderboardProvider),
                child: Text('Retry',
                    style: GoogleFonts.dmSans(color: AppColors.primary)),
              ),
            ],
          ),
        ),
        data: (lb) => _buildContent(context, lb),
      ),
    );
  }

  Widget _buildContent(BuildContext context, LeaderboardResult lb) {
    return Column(
      children: [
        // Tier badge
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _tierColor(lb.tier).withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _tierColor(lb.tier).withOpacity(0.4)),
            ),
            child: Text(
              '${lb.tier[0].toUpperCase()}${lb.tier.substring(1)} Tier — Rank #${lb.yourRank}',
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _tierColor(lb.tier),
              ),
            ),
          ),
        ),

        // Top 10 list
        Expanded(
          child: lb.top.isEmpty
              ? Center(
                  child: Text('No entries yet this week',
                      style: GoogleFonts.dmSans(
                          fontSize: 14, color: AppColors.textSecondary)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: lb.top.length,
                  itemBuilder: (context, index) {
                    final entry = lb.top[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: index < 3
                            ? const Color(0xFF0A1F1A)
                            : const Color(0xFF071714),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: index < 3
                              ? AppColors.primaryDeep
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text(
                              '#${entry.rank}',
                              style: GoogleFonts.nunito(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: index < 3
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF0D2A22),
                            ),
                            child: Center(
                              child: Text(
                                entry.name.isNotEmpty
                                    ? entry.name[0].toUpperCase()
                                    : 'P',
                                style: GoogleFonts.nunito(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              entry.name.isNotEmpty ? entry.name : 'Player',
                              style: GoogleFonts.dmSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            '${entry.xpEarned} XP',
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryMid,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Color _tierColor(String tier) {
    switch (tier) {
      case 'gold':
        return const Color(0xFFFFD700);
      case 'silver':
        return const Color(0xFFC0C0C0);
      default:
        return const Color(0xFFCD7F32);
    }
  }
}
```

- [ ] **Step 2: Add route in app_router.dart**

Add import:

```dart
import '../../presentation/screens/leaderboard/leaderboard_screen.dart';
```

Add route constant in `AppRoutes`:

```dart
static const leaderboard = '/leaderboard';
```

Add GoRoute after the `activity` route:

```dart
GoRoute(
  path: AppRoutes.leaderboard,
  builder: (context, state) => const LeaderboardScreen(),
),
```

- [ ] **Step 3: Verify compilation**

Run: `flutter analyze`

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/leaderboard/leaderboard_screen.dart lib/core/router/app_router.dart
git commit -m "feat: add leaderboard screen with tiered weekly rankings"
```

---

## Task 14: Final Verification — Build Backend + Flutter Analyze

**Files:** None (verification only)

- [ ] **Step 1: Verify backend compiles**

Run: `cd backend && go build ./...`

Expected: no errors.

- [ ] **Step 2: Verify Flutter analyzes clean**

Run: `flutter analyze`

Expected: no errors.

- [ ] **Step 3: Run build_runner one final time**

Run: `dart run build_runner build --delete-conflicting-outputs`

Expected: no errors.

- [ ] **Step 4: Run backend tests**

Run: `cd backend && go test ./...`

Expected: existing tests still pass. New code doesn't have tests yet (would be a follow-up task).

- [ ] **Step 5: Final commit if any generated files changed**

```bash
git add -A && git status
# If there are generated files, commit them:
git commit -m "chore: regenerate build_runner outputs"
```
