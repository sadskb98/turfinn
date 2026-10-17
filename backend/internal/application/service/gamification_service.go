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

func (s *GamificationService) DB() *gorm.DB { return s.db }

// AwardXP inserts an XP event, updates user.xp, checks level-up, awards coins if leveled.
func (s *GamificationService) AwardXP(ctx context.Context, userID uuid.UUID, source string, sourceID *uuid.UUID, amount int) error {
	if amount <= 0 {
		return nil
	}

	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		evt := entity.XPEvent{UserID: userID, Source: source, SourceID: sourceID, Amount: amount}
		if err := tx.Create(&evt).Error; err != nil {
			return err
		}

		var user entity.User
		if err := tx.First(&user, "id = ?", userID).Error; err != nil {
			return err
		}

		oldLevel := user.Level
		user.XP += amount

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

		if newLevel > oldLevel {
			reward := entity.LevelThresholds[newLevel-1].CoinReward
			if reward > 0 {
				s.walletSvc.CreditCoins(ctx, userID, reward, "level_up", fmt.Sprintf("level:%d", newLevel))
			}
		}

		s.upsertLeaderboardXP(ctx, userID, user.Level, amount)

		return nil
	})
}

func LevelTitle(level int) string {
	if level < 1 || level > len(entity.LevelThresholds) {
		return "Rookie"
	}
	return entity.LevelThresholds[level-1].Title
}

func XPToNextLevel(currentXP, currentLevel int) int {
	if currentLevel >= len(entity.LevelThresholds) {
		return 0
	}
	return entity.LevelThresholds[currentLevel].XPRequired - currentXP
}

// -- Event hooks -- called fire-and-forget from other services --

func (s *GamificationService) OnBookingCreated(ctx context.Context, userID uuid.UUID, bookingID uuid.UUID, startsAt time.Time) {
	xp := 100
	if startsAt.Hour() < 10 {
		xp += 50
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

// -- Streak logic --

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

	if streak.LastBookingYear == isoYear && streak.LastBookingWeek == isoWeek {
		return
	}

	prevWeekAbs := streak.LastBookingYear*52 + streak.LastBookingWeek
	currWeekAbs := isoYear*52 + isoWeek
	gap := currWeekAbs - prevWeekAbs

	if gap == 1 {
		streak.CurrentStreak++
	} else if gap == 2 && streak.StreakFreezesRemaining > 0 {
		streak.CurrentStreak++
		streak.StreakFreezesRemaining--
	} else {
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

	if streak.StreakFreezesRemaining > 0 {
		return fmt.Errorf("you already have a streak freeze active")
	}

	if err := s.walletSvc.DebitCoins(ctx, userID, cost, "streak_freeze", "streak_freeze"); err != nil {
		return err
	}

	streak.StreakFreezesRemaining = 1
	return s.db.WithContext(ctx).Save(&streak).Error
}

// -- Check-in logic --

func (s *GamificationService) Checkin(ctx context.Context, userID uuid.UUID) (map[string]interface{}, error) {
	today := time.Now().Truncate(24 * time.Hour)

	var existing entity.DailyCheckin
	err := s.db.WithContext(ctx).Where("user_id = ? AND checked_in_at = ?", userID, today).First(&existing).Error
	if err == nil {
		return nil, fmt.Errorf("already checked in today")
	}

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

	s.walletSvc.CreditCoins(ctx, userID, coins, "checkin", fmt.Sprintf("day:%d", dayInCycle))
	s.AwardXP(ctx, userID, "checkin", nil, 15)

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

	var recent entity.DailyCheckin
	err := s.db.WithContext(ctx).Where("user_id = ?", userID).
		Order("checked_in_at DESC").First(&recent).Error
	if err != nil {
		return cycle
	}

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

// -- Challenge logic --

func (s *GamificationService) GetWeeklyChallenges(ctx context.Context, userID uuid.UUID) ([]map[string]interface{}, error) {
	weekStart := currentWeekStart()
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

		if progress.Progress >= wc.Template.Target && !progress.Completed {
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

func (s *GamificationService) updateUniquePitchChallenge(ctx context.Context, userID uuid.UUID, bookingID uuid.UUID) {
	weekStart := currentWeekStart()

	var count int64
	s.db.WithContext(ctx).Model(&entity.Booking{}).
		Where("user_id = ? AND created_at >= ? AND status IN ('pending','confirmed','completed')", userID, weekStart).
		Distinct("pitch_id").Count(&count)

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

// -- Leaderboard logic --

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

	var user entity.User
	if err := s.db.WithContext(ctx).First(&user, "id = ?", userID).Error; err != nil {
		return nil, err
	}
	tier := levelToTier(user.Level)

	var entries []entity.LeaderboardEntry
	s.db.WithContext(ctx).Where("week_start = ? AND tier = ?", weekStart, tier).
		Order("xp_earned DESC").Limit(10).Find(&entries)

	top := make([]map[string]interface{}, 0, len(entries))
	for i, e := range entries {
		var u entity.User
		s.db.WithContext(ctx).First(&u, "id = ?", e.UserID)
		top = append(top, map[string]interface{}{
			"rank":       i + 1,
			"user_id":    e.UserID,
			"name":       u.Name,
			"avatar_url": u.AvatarURL,
			"xp_earned":  e.XPEarned,
		})
	}

	var userEntry entity.LeaderboardEntry
	var userRank int64
	if s.db.WithContext(ctx).Where("user_id = ? AND week_start = ?", userID, weekStart).First(&userEntry).Error == nil {
		s.db.WithContext(ctx).Model(&entity.LeaderboardEntry{}).
			Where("week_start = ? AND tier = ? AND xp_earned > ?", weekStart, tier, userEntry.XPEarned).
			Count(&userRank)
		userRank++
	}

	return map[string]interface{}{
		"tier":       tier,
		"week_start": weekStart.Format("2006-01-02"),
		"top":        top,
		"your_rank":  userRank,
		"your_xp":   userEntry.XPEarned,
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
			"rank":         i + 1,
			"user_id":      e.UserID,
			"name":         u.Name,
			"avatar_url":   u.AvatarURL,
			"xp_earned":    e.XPEarned,
			"reward_coins": e.RewardCoins,
		})
	}

	var userEntry entity.LeaderboardEntry
	s.db.WithContext(ctx).Where("user_id = ? AND week_start = ?", userID, prevWeekStart).First(&userEntry)

	return map[string]interface{}{
		"tier":        tier,
		"week_start":  prevWeekStart.Format("2006-01-02"),
		"top":         top,
		"your_rank":   userEntry.Rank,
		"your_xp":    userEntry.XPEarned,
		"your_reward": userEntry.RewardCoins,
	}, nil
}

func (s *GamificationService) FinalizeWeek(ctx context.Context) error {
	prevWeekStart := currentWeekStart().Add(-7 * 24 * time.Hour)

	tiers := []string{"bronze", "silver", "gold"}
	rewards := []int{300, 200, 100}

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

// -- Referral logic --

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

	var existing entity.GamificationReferral
	if s.db.WithContext(ctx).Where("referred_id = ?", userID).First(&existing).Error == nil {
		return fmt.Errorf("you have already used a referral code")
	}

	referral := entity.GamificationReferral{
		ReferrerID: rc.UserID,
		ReferredID: userID,
		Status:     "pending",
	}
	return s.db.WithContext(ctx).Create(&referral).Error
}

func (s *GamificationService) completeReferralIfFirst(ctx context.Context, userID uuid.UUID) {
	var bookingCount int64
	s.db.WithContext(ctx).Model(&entity.Booking{}).
		Where("user_id = ? AND status IN ('pending','confirmed','completed')", userID).
		Count(&bookingCount)
	if bookingCount != 1 {
		return
	}

	var referral entity.GamificationReferral
	if err := s.db.WithContext(ctx).Where("referred_id = ? AND status = 'pending'", userID).First(&referral).Error; err != nil {
		return
	}

	referral.Status = "completed"
	now := time.Now()
	referral.CompletedAt = &now
	referral.ReferrerCoins = 200
	referral.ReferredCoins = 100
	s.db.WithContext(ctx).Save(&referral)

	s.walletSvc.CreditCoins(ctx, referral.ReferrerID, 200, "referral", userID.String())
	s.walletSvc.CreditCoins(ctx, userID, 100, "referral", referral.ReferrerID.String())

	s.db.WithContext(ctx).Model(&entity.ReferralCode{}).
		Where("user_id = ?", referral.ReferrerID).
		Updates(map[string]interface{}{
			"total_referrals":    gorm.Expr("total_referrals + 1"),
			"total_coins_earned": gorm.Expr("total_coins_earned + 200"),
		})

	s.OnReferralCompleted(ctx, referral.ReferrerID)
}

func (s *GamificationService) GetReferralInfo(ctx context.Context, userID uuid.UUID) (map[string]interface{}, error) {
	rc, err := s.GetOrCreateReferralCode(ctx, userID)
	if err != nil {
		return nil, err
	}

	return map[string]interface{}{
		"code":               rc.Code,
		"total_referrals":    rc.TotalReferrals,
		"total_coins_earned": rc.TotalCoinsEarned,
	}, nil
}

// -- Helpers --

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
	const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	b := make([]byte, 6)
	for i := range b {
		b[i] = chars[rand.Intn(len(chars))]
	}
	return string(b)
}
