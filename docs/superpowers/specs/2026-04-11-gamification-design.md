# Turfinn Gamification & Data Fix Spec

## Overview

Wire up existing backend gamification (badges/coins/wallet) to mobile app, add 6 new gamification systems (XP/levels, streaks, daily check-in, weekly challenges, tiered leaderboards, referrals), and fix all hardcoded data / silent errors in the mobile app.

## Economy

- Coin model: low value, high volume. Players earn 50-100/day if active.
- 1 coin ≠ 1 BDT. Conversion rate is a platform setting (e.g., 10 coins = 1 BDT discount).
- Coin sinks: streak freezes (200 coins), future cosmetics, booking discounts.

---

## Part 1: Wire Up Existing + Fix Data Mismatches

### Problem

Backend has badges, coins, wallet, profile, feed endpoints. Mobile shows hardcoded demo data everywhere.

### Fixes Required

| What | File | Fix |
|---|---|---|
| Wallet balance `'5,000 BDT'` | `home_screen.dart:123`, `feed_screen.dart:141` | Read from wallet provider |
| Profile stats `'47'`, `'50 Matches'`, `'68%'` | `profile_screen.dart:131-148` | Read from `/api/v1/profile` |
| No badges shown | `profile_screen.dart` | Add badges grid from profile endpoint |
| Feed posts hardcoded list | `feed_screen.dart:12-45` | Call `/api/v1/feed` endpoint |
| Fallback names `'Brooklyn Simmons'`, `'BashirulHana'` | `profile_screen.dart:33`, `home_screen.dart:25`, `feed_screen.dart:52` | Use `'Player'` fallback |
| Silent `catch (_) {}` | `booking_provider.dart:54` | Show error snackbar |
| Hardcoded status `'Confirmed'` | `activity_screen.dart:215` | Use actual booking status |
| No loading/error/empty states | Multiple screens | Add per CLAUDE.md rules |
| Milestones hardcoded | `home_screen.dart:220-238` | Wire to challenge/streak progress |
| Profile provider wrong endpoint | `profile_provider.dart` | Call `/api/v1/profile` not `/users/me` |

### New Flutter Models

```dart
// wallet_model.dart (freezed)
PlayerProfile: id, name, phone, avatarUrl, role, level, levelTitle, xp, xpToNextLevel, coinsBalance, totalBookings, currentStreak, badges[]
PlayerBadge: id, slug, name, description, iconUrl, earnedAt, coinReward
WalletBalance: balance (int)
WalletTransaction: id, type, amount, description, createdAt
```

### New Providers

- `walletProvider` — fetches `/api/v1/wallet` (balance)
- `playerProfileProvider` — fetches `/api/v1/profile` (full profile with badges, xp, level)
- `walletTransactionsProvider` — fetches `/api/v1/wallet/transactions` (paginated)
- `feedProvider` — fetches `/api/v1/feed` (replaces hardcoded list)

---

## Part 2: XP & Levels

### Database

```sql
-- in existing users table, add columns:
ALTER TABLE users ADD COLUMN xp INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN level INTEGER DEFAULT 1;

-- XP event log
CREATE TABLE xp_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    source VARCHAR(50) NOT NULL,      -- 'booking', 'review', 'match_post', 'checkin', 'referral', 'challenge'
    source_id UUID,                    -- optional FK to the triggering record
    amount INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_xp_events_user ON xp_events(user_id);
CREATE INDEX idx_xp_events_created ON xp_events(created_at);
```

### XP Amounts

| Action | XP |
|---|---|
| Complete a booking | 100 |
| Early bird booking (start ≤ 09:00) | +50 bonus |
| Write a review | 30 |
| Create match post | 40 |
| Join match post | 25 |
| Daily check-in | 15 |
| Referral (friend's first booking) | 200 |
| Complete weekly challenge | 75-150 (per challenge difficulty) |

### Level Curve

| Level | Title | Total XP Required | Coin Reward on Level-Up |
|---|---|---|---|
| 1 | Rookie | 0 | — |
| 2 | Beginner | 200 | 50 |
| 3 | Regular | 500 | 75 |
| 4 | Enthusiast | 1,000 | 100 |
| 5 | Veteran | 2,000 | 150 |
| 6 | Pro | 4,000 | 200 |
| 7 | Elite | 7,500 | 300 |
| 8 | Champion | 12,000 | 500 |
| 9 | Legend | 20,000 | 750 |
| 10 | GOAT | 35,000 | 1,000 |

### Backend

- `GamificationService.AwardXP(userID, source, sourceID, amount)` — inserts xp_event, updates user.xp, checks level-up, awards coins if leveled.
- Called fire-and-forget (goroutine) from booking, review, feed, checkin, referral services.
- `GET /api/v1/profile` response includes: `xp`, `level`, `level_title`, `xp_to_next_level`.

### Frontend

- Profile screen: XP progress bar under level title, "Level 4 — Enthusiast" with `1,000/2,000 XP`.
- Level-up celebration: confetti animation + toast when XP crosses threshold (detected on profile refresh).

---

## Part 3: Booking Streaks

### Database

```sql
CREATE TABLE user_streaks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) UNIQUE,
    current_streak INTEGER DEFAULT 0,
    longest_streak INTEGER DEFAULT 0,
    last_booking_week INTEGER NOT NULL,  -- ISO week number
    last_booking_year INTEGER NOT NULL,
    streak_freezes_remaining INTEGER DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Logic

- After each booking creation, check if user booked this ISO week. If new week = previous week + 1, increment streak. If gap > 1 and no freeze, reset to 1.
- Streak freeze: purchasable via `POST /api/v1/store/streak-freeze` for 200 coins. Max 1 per month. Protects 1 missed week.

### Milestones & Rewards

| Streak | Coins | XP | Badge |
|---|---|---|---|
| 3 weeks | 100 | 150 | `streak_3` |
| 5 weeks | 200 | 300 | `streak_5` |
| 10 weeks | 500 | 600 | `streak_10` |
| 20 weeks | 1,000 | 1,200 | `streak_20` |

### API

- `GET /api/v1/profile` includes `current_streak`, `longest_streak`, `streak_freezes_remaining`.
- `POST /api/v1/store/streak-freeze` — deduct 200 coins, increment freezes (max 1/month).

### Frontend

- Home screen "Your Next Match" section shows streak flame icon + count.
- Profile screen shows current streak + longest streak.
- Streak milestone toast when hitting 3/5/10/20.

---

## Part 4: Daily Check-in

### Database

```sql
CREATE TABLE daily_checkins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    checked_in_at DATE NOT NULL DEFAULT CURRENT_DATE,
    day_in_cycle INTEGER NOT NULL,  -- 1-7
    coins_earned INTEGER NOT NULL,
    UNIQUE(user_id, checked_in_at)
);
```

### Logic

- `POST /api/v1/checkin` — one per calendar day per user.
- 7-day repeating cycle. Days 1-6: 10 coins + 15 XP. Day 7: 50 coins + 15 XP.
- Missing a day resets cycle to day 1.
- Response: `{ day: 3, coins_earned: 10, cycle: [true, true, true, false, false, false, false] }`.

### API

- `POST /api/v1/checkin` — perform check-in, returns result.
- `GET /api/v1/checkin/status` — returns current cycle state without checking in.

### Frontend

- Home screen: check-in card at top if not checked in today. 7 circles showing cycle progress. Tap to check in.
- After check-in: coin rain animation + "Day 3 — 10 coins earned!" toast.
- Card disappears (or shows "Checked in ✓") after daily check-in done.

---

## Part 5: Weekly Challenges

### Database

```sql
CREATE TABLE challenge_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug VARCHAR(50) UNIQUE NOT NULL,
    title VARCHAR(100) NOT NULL,
    description TEXT NOT NULL,
    type VARCHAR(30) NOT NULL,        -- 'booking_count', 'unique_pitches', 'match_posts', 'reviews', 'referrals'
    target INTEGER NOT NULL,           -- e.g. 2 for "Book 2 times"
    difficulty VARCHAR(10) NOT NULL,   -- 'easy', 'medium', 'hard'
    coin_reward INTEGER NOT NULL,
    xp_reward INTEGER NOT NULL,
    active BOOLEAN DEFAULT true
);

CREATE TABLE weekly_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    week_start DATE NOT NULL,          -- Monday of the week
    challenge_template_id UUID NOT NULL REFERENCES challenge_templates(id),
    UNIQUE(week_start, challenge_template_id)
);

CREATE TABLE user_challenge_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    weekly_challenge_id UUID NOT NULL REFERENCES weekly_challenges(id),
    progress INTEGER DEFAULT 0,
    completed BOOLEAN DEFAULT false,
    completed_at TIMESTAMPTZ,
    UNIQUE(user_id, weekly_challenge_id)
);
```

### Challenge Pool (seeded)

| Slug | Title | Type | Target | Difficulty | Coins | XP |
|---|---|---|---|---|---|---|
| `book_2` | Book 2 Times | booking_count | 2 | easy | 50 | 75 |
| `book_4` | Book 4 Times | booking_count | 4 | hard | 150 | 150 |
| `new_pitch` | Try a New Pitch | unique_pitches | 1 | medium | 75 | 100 |
| `two_pitches` | Visit 2 Different Pitches | unique_pitches | 2 | medium | 100 | 125 |
| `create_post` | Create a Match Post | match_posts | 1 | easy | 50 | 75 |
| `join_2_posts` | Join 2 Match Posts | match_posts | 2 | medium | 75 | 100 |
| `write_review` | Write a Review | reviews | 1 | easy | 50 | 75 |
| `refer_1` | Refer a Friend | referrals | 1 | medium | 100 | 125 |

### Logic

- Cron job (or on first Monday request): select 4 challenges for the week (1 easy, 2 medium, 1 hard).
- Progress updated via event hooks in booking/feed/review/referral services.
- Completing all 4: "Perfect Week" bonus — 200 coins + 300 XP.
- `GET /api/v1/challenges` — returns this week's 4 challenges with user progress.

### Frontend

- Challenges card on home screen showing 4 items with progress bars.
- Tap to expand details. Completed ones show checkmark + reward collected.
- "Perfect Week" banner if all 4 done.

---

## Part 6: Tiered Weekly Leaderboards

### Database

```sql
CREATE TABLE leaderboard_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    week_start DATE NOT NULL,
    tier VARCHAR(10) NOT NULL,         -- 'bronze', 'silver', 'gold'
    xp_earned INTEGER DEFAULT 0,
    rank INTEGER,                       -- set by cron at week end
    reward_coins INTEGER DEFAULT 0,     -- set by cron at week end
    UNIQUE(user_id, week_start)
);
CREATE INDEX idx_leaderboard_week_tier ON leaderboard_entries(week_start, tier, xp_earned DESC);
```

### Tiers

| Tier | Player Levels | Top 3 Rewards (coins) |
|---|---|---|
| Bronze | 1-3 | 300 / 200 / 100 |
| Silver | 4-6 | 500 / 350 / 200 |
| Gold | 7-10 | 800 / 500 / 300 |

### Logic

- XP earned during the week (from xp_events table, filtered by week) determines ranking.
- Entry created/updated whenever XP is awarded (upsert on user_id + week_start).
- Cron job Monday 00:05: finalize previous week's ranks, award coins to top 3 per tier.
- Tier assigned based on user's level at start of week (prevents gaming by leveling mid-week).

### API

- `GET /api/v1/leaderboard` — returns current week's leaderboard for user's tier. Top 10 + user's position.
- `GET /api/v1/leaderboard/previous` — last week's results + rewards.

### Frontend

- Leaderboard accessible from profile or home screen.
- Shows tier badge, rank, top 10 with avatars/names/XP.
- "Your Position: #7" highlight if outside top 10.
- Previous week results with "You earned 200 coins!" if placed.

---

## Part 7: Referral System

### Database

```sql
CREATE TABLE referral_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) UNIQUE,
    code VARCHAR(10) UNIQUE NOT NULL,
    total_referrals INTEGER DEFAULT 0,
    total_coins_earned INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE referrals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id UUID NOT NULL REFERENCES users(id),
    referred_id UUID NOT NULL REFERENCES users(id) UNIQUE,
    status VARCHAR(20) DEFAULT 'pending',  -- 'pending', 'completed' (after first booking)
    referrer_coins INTEGER DEFAULT 0,
    referred_coins INTEGER DEFAULT 0,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Logic

- Referral code auto-generated on user creation (6 alphanumeric chars).
- New user enters referral code during/after signup: `POST /api/v1/referral/apply` with `{ code: "ABC123" }`.
- When referred user makes first booking: both get coins (referrer: 200, friend: 100) + referrer gets 200 XP.
- Max 50 completed referrals per user.
- Cannot self-refer (checked by user_id).

### API

- `GET /api/v1/referral` — returns user's referral code, total referrals, coins earned.
- `POST /api/v1/referral/apply` — apply a referral code (during onboarding).
- Referral completion triggered automatically by booking service on first booking.

### Frontend

- Profile screen: "Invite Friends" card with referral code + share button (native share sheet).
- Share text: "Join me on Turfinn! Use code ABC123 for 100 bonus coins. [deep link]"
- Referral stats: X friends invited, Y coins earned.

---

## Part 8: Backend Architecture

### New Service: `GamificationService`

Central service that other services call fire-and-forget:

```
BookingService.Create() → go gamificationSvc.OnBookingCreated(userID, bookingID)
FeedService.CreatePost() → go gamificationSvc.OnMatchPostCreated(userID, postID)
FeedService.JoinPost() → go gamificationSvc.OnMatchPostJoined(userID, postID)
ReviewService.Create() → go gamificationSvc.OnReviewCreated(userID, reviewID)
```

Each `On*` method:
1. Awards XP (inserts xp_event, updates user.xp, checks level-up)
2. Updates challenge progress
3. Updates leaderboard entry (upsert weekly XP)
4. Checks/updates streak (on booking only)
5. Awards relevant badges

### New Service: `ChallengeService`

- `GetWeeklyChallenges(userID)` — returns 4 challenges with progress
- `RotateChallenges()` — called by cron, picks 4 for the new week
- `UpdateProgress(userID, type, delta)` — called by GamificationService

### New Service: `LeaderboardService`

- `GetLeaderboard(userID)` — current week, user's tier
- `FinalizeWeek()` — cron job, ranks + awards
- `UpsertEntry(userID, xpDelta)` — called when XP awarded

### New Service: `ReferralService`

- `GetReferralInfo(userID)`
- `ApplyCode(userID, code)`
- `CompleteReferral(referredUserID)` — called by booking service on first booking

### New Service: `CheckinService`

- `Checkin(userID)` — daily check-in
- `GetStatus(userID)` — current cycle state

### Updated Endpoints

Existing `/api/v1/profile` response expands to include:
```json
{
  "id": "...",
  "name": "...",
  "phone": "...",
  "avatar_url": "...",
  "role": "player",
  "xp": 1250,
  "level": 4,
  "level_title": "Enthusiast",
  "xp_to_next_level": 750,
  "coins_balance": 430,
  "total_bookings": 12,
  "current_streak": 3,
  "longest_streak": 5,
  "streak_freezes": 1,
  "badges": [...],
  "referral_code": "ABC123"
}
```

### New Endpoints

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/v1/checkin` | Daily check-in |
| GET | `/api/v1/checkin/status` | Check-in cycle state |
| GET | `/api/v1/challenges` | This week's challenges + progress |
| GET | `/api/v1/leaderboard` | Current week leaderboard (user's tier) |
| GET | `/api/v1/leaderboard/previous` | Last week's results |
| GET | `/api/v1/referral` | User's referral info |
| POST | `/api/v1/referral/apply` | Apply referral code |
| POST | `/api/v1/store/streak-freeze` | Buy streak freeze (200 coins) |

### New Migration

Single migration `015_gamification_v2.sql` covering:
- `xp_events`, `user_streaks`, `daily_checkins`, `challenge_templates`, `weekly_challenges`, `user_challenge_progress`, `leaderboard_entries`, `referral_codes`, `referrals` tables
- ALTER users ADD xp, level columns
- Seed challenge_templates
- Seed 4 new streak badges
- All with `IF NOT EXISTS` guards

---

## Part 9: Mobile App Changes Summary

### New Screens

- Leaderboard screen (accessible from home/profile)
- Referral screen (from profile)

### Updated Screens

- **Home**: Real wallet balance, check-in card, challenges card, streak display, milestones wired to real data
- **Profile**: Real stats from API, badges grid, XP bar, level title, streak, referral card
- **Feed**: Real posts from API, not hardcoded
- **Activity**: Real booking statuses, proper error/empty states
- **All screens**: Loading/error/empty states, no hardcoded fallback data

### New Providers

- `playerProfileProvider` — `/api/v1/profile`
- `checkinProvider` — `/api/v1/checkin/status`
- `challengesProvider` — `/api/v1/challenges`
- `leaderboardProvider` — `/api/v1/leaderboard`
- `referralProvider` — `/api/v1/referral`

### New Models (freezed)

- `PlayerProfile` (expanded with XP, level, streak, referral)
- `CheckinStatus`, `CheckinResult`
- `Challenge`, `ChallengeProgress`
- `LeaderboardEntry`, `LeaderboardResult`
- `ReferralInfo`
