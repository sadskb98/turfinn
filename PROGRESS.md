# Turfinn — Progress Report

Last updated: 2026-04-12

## Architecture

```
├── Flutter Mobile App (main.dart)        → Players only
├── Flutter Web — Turf Manager (main_manage.dart)  → Turf owners
├── Flutter Web — Super Admin (main_superadmin.dart) → Platform owner
├── Go Backend (backend/)                 → Echo + GORM + Redis + MinIO
└── Docker Compose                        → All services orchestrated
```

### Ports (Docker Compose)

| Service | Port | Description |
|---|---|---|
| Player App | 3000 | Flutter web — player-facing |
| Turf Manager | 3002 | Flutter web — turf owner dashboard |
| Super Admin | 3003 | Flutter web — platform owner |
| Go API | 8080 | Backend API (128+ endpoints) |
| MinIO | 9000 (API), 9001 (Console) | S3-compatible object storage |
| Postgres | 5432 (internal only) | Database |
| Redis | 6379 (internal only) | Cache + OTP storage + Asynq |

### Key Files

| File | What it does |
|---|---|
| `docker-compose.yml` | Orchestrates all services |
| `backend/cmd/api/main.go` | Go API entry point — wires all repos, services, handlers |
| `backend/internal/interfaces/http/router.go` | All routes registered here |
| `backend/migrations/` | 21 SQL migration files (001-021), run on DB init |
| `lib/main.dart` | Player mobile app entry (with desktop web shell wrapper) |
| `lib/main_manage.dart` | Turf Manager web entry |
| `lib/main_superadmin.dart` | Super Admin web entry |
| `lib/core/router/app_router.dart` | Mobile app routing (GoRouter) |
| `lib/data/sources/remote/dio_client.dart` | Dio HTTP client — base URL from `--dart-define=API_BASE_URL` |

---

## Backend (Go)

### 128+ API Endpoints — ALL implemented with handlers

| Group | Route Prefix | Auth | Endpoints | Handler File |
|---|---|---|---|---|
| Health | `/health` | None | 1 | inline in router.go |
| WebSocket | `/ws` | Query param | 1 | ws_handler.go |
| Auth | `/api/v1/auth` | None | 3 (send-otp, verify-otp, google) | auth_handler.go |
| Pitches | `/api/v1/pitches` | Public (list/get/slots), Auth (create) | 4 | pitch_handler.go |
| Reviews | `/api/v1/pitches/:id/reviews` | Public (list), Auth (create) | 2 | review_handler.go |
| Bookings | `/api/v1/bookings` | Auth | 3 (create, list mine, cancel) | booking_handler.go |
| Upload | `/api/v1/upload` | Auth | 1 (presign) | upload_handler.go |
| Events | `/api/v1/events` | Optional Auth | 1 | events_handler.go |
| Users | `/api/v1/users` | Auth | 3 (get me, update me, FCM token) | user_handler.go |
| Teams | `/api/v1/teams` | Auth | 5 (create, list my, get, join, formation) | team_handler.go |
| Matchmaking | `/api/v1/matchmaking` | Auth | 2 (find, get match) | team_handler.go |
| Manager | `/api/v1/manager` | Auth + RequireManager | 7 (analytics, bookings, financials) | manager_handler.go |
| Manager Promos | `/api/v1/manager/promos` | Auth + RequireManager | 3 (list, create, deactivate) | manager_campaigns_handler.go |
| Match Feed | `/api/v1/feed` | Auth | 3 (create, list, join) | match_post_handler.go |
| Wallet | `/api/v1/wallet` | Auth | 3 (balance, topup, transactions) | wallet_handler.go |
| Profile | `/api/v1/profile` | Auth | 1 | wallet_handler.go |
| Gamification | `/api/v1/checkin,challenges,leaderboard,referral,store` | Auth | 7 | gamification_handler.go |
| Tournaments | `/api/v1/tournaments` | Auth | 6 (CRUD, join, start, cancel) | tournament_handler.go |
| Admin | `/api/v1/admin` | Auth + RequireRole(admin) | 9 | admin_handler.go |
| Manage | `/api/v1/manage` | Auth + RequireRole(manager, admin) | 8 | manage_handler.go |
| Platform Config | `/api/v1/admin/platform` | Auth + RequireRole(admin, super_admin) | 12 | platform_handler.go |
| Marketing | `/api/v1/admin/marketing` | Auth + RequireRole(admin, super_admin) | 14 | marketing_handler.go |
| Disputes/KYC | `/api/v1/admin/disputes,tickets,reviews,kyc` | Auth + RequireRole(admin, super_admin) | 13 | dispute_handler.go |
| User Actions | `/api/v1/admin/user-actions` | Auth + RequireRole(admin, super_admin) | 3 (warn, ban, unban) | dispute_handler.go |
| Super Admin | `/api/v1/super-admin` | Auth + RequireRole(super_admin) | 17 | superadmin_handler.go |
| Public Config | `/api/v1/config` | None | 1 | platform_handler.go |
| Public Banners | `/api/v1/banners` | None | 1 | marketing_handler.go |

### Database — 41+ Tables

All created via 21 migrations in `backend/migrations/` (001 through 021). Docker Compose mounts these into Postgres init directory.

Key tables: `users`, `pitches`, `bookings`, `reviews`, `teams`, `team_members`, `matches`, `match_posts`, `match_post_joins`, `wallets`, `wallet_transactions`, `badges`, `user_badges`, `pricing_rules`, `disputes`, `support_tickets`, `manager_kyc`, `promo_codes`, `campaigns`, `banners`, `zones`, `organizations`, `resellers`, `ledger_entries`, `audit_log`, `fraud_flags`, `api_keys`, `rate_limit_config`, `feature_flags`, `platform_settings`, `booking_events`, `tournaments`, `tournament_teams`, `tournament_matches`, `xp_events`, `user_streaks`, `daily_checkins`, `challenge_templates`, `weekly_challenges`, `user_challenge_progress`, `leaderboard_entries`, `referral_codes`

### Business Logic Implemented

- **Booking conflict detection** — checks time overlap before creating
- **Cancellation policy** — 6+ hours before = full wallet refund, <6 hours = no refund, past bookings = rejected
- **Booking validation** — no past bookings, 30min-4hr duration, 08:00-00:00 operating hours, max 30 days ahead
- **Smart pricing** — pricing_rules table checked during booking, applies multiplier/fixed amount based on day + time
- **Matchmaking** — simple queue: search for opponent with same format, match or create waiting entry
- **Gamification V2** — XP, levels, weekly streaks, daily check-ins, weekly challenges, leaderboards (bronze/silver/gold tiers), referral codes, streak freeze store
- **Badges** — 9 badges auto-awarded (first_booking, early_bird, regular_player, team_captain, social_butterfly, streak_3, streak_5, streak_10, streak_20)
- **Badge triggers** — fire-and-forget goroutines after booking creation and feed post creation/join
- **Wallet** — coins system (1 coin = 1 BDT), top-up, transaction history, badge reward credits
- **Tournaments** — create, join with team, start, cancel, format normalization ("5v5" == "5 vs 5")
- **Rate limiting** — 20/min on OTP, 200/min global
- **Input sanitization** — html.EscapeString on user-generated content
- **Role-based access** — RequireRole middleware checks live DB role (not stale JWT claim)
- **Haversine distance sort** — `GET /pitches?lat=&lng=&radius=` sorts by distance with service radius priority boost
- **Service radius** — per-pitch `service_radius_km` boosts sort priority for nearby players (not a visibility filter)
- **Text search** — `GET /pitches?search=mirpur` filters by name/address/city (ILIKE)

### Migrations Summary

| Migration | What it does |
|---|---|
| 001 | Initial schema (users, pitches, bookings) |
| 002 | Profile fields + seed data (admin user + 6 pitches + badges) |
| 002_seed | Seed data |
| 003 | Teams schema |
| 004 | Admin/superadmin tables (reviews, disputes, platform settings, promo codes, etc.) |
| 005 | Google OAuth fields |
| 006 | Reviews table (alternate schema, no-op if 004 ran first) |
| 007 | FCM tokens |
| 008 | Teams (additional columns) |
| 009 | Chat messages |
| 010 | Booking source field |
| 011 | Match posts |
| 012 | Wallets + gamification (badges, wallet_transactions) + schema compat fixes |
| 013 | Admin/superadmin (idempotent re-application of 004) |
| 014 | Match post joins |
| 015 | Manager promo codes (owner_id on promo_codes) |
| 016 | Gamification V2 (XP, streaks, check-ins, challenges, leaderboards, referrals) |
| 017 | Tournaments |
| 018 | Tournament min_coins |
| 019 | Fix wallet_transactions schema (add wallet_id/amount/reference, drop user_id NOT NULL) |
| 020 | Fix reviews.booking_id, promo_codes.owner_id, pricing_rules columns, seed super_admin |
| 021 | Add service_radius_km to pitches |

### Infrastructure

- **MinIO** — S3-compatible storage with 3 buckets: `avatars`, `pitch-images`, `kyc-documents`
- **Redis** — OTP caching (5min TTL), pitch caching (15min TTL), Asynq task queue
- **Asynq workers** — email/notification worker scaffolded but not connected to actual provider

### Seed Data

Migration `002_seed.sql` creates:
- 1 admin user (phone: +8801000000000, role: admin)
- 6 pitches in Dhaka (GreenField Arena, Urban Arena, Dhanmondi Sports Complex, Mirpur Turf Zone, Bashundhara Arena, Uttara Sports Hub)
- 5 base badges

Migration `020_fix_remaining_schema.sql` creates:
- 1 super_admin user (phone: +8801000000001, role: super_admin)

Migration `016_gamification_v2.sql` seeds:
- 4 streak badges (streak_3, streak_5, streak_10, streak_20)
- 8 challenge templates

---

## Flutter Mobile App (Player)

### Screens

| Screen | File | Status |
|---|---|---|
| Splash | `screens/splash/splash_screen.dart` | Done |
| Welcome | `screens/welcome/welcome_screen.dart` | Done |
| Sign Up | `screens/sign_up/sign_up_screen.dart` | Done — phone OTP + Google/Apple buttons |
| OTP Verify | `screens/otp/otp_screen.dart` | Done |
| Home | `screens/home/home_screen.dart` | Done — daily check-in, tournaments banner, leaderboard link, challenges, turf cards with working filters (Price Low/High/Budget) |
| Explore (Map) | `screens/explore/map_explore_screen.dart` | **NEW** — full-screen OSM map with turf price pins, draggable bottom sheet with cards, GPS/city preference, radius filter |
| Search | `screens/search/search_screen.dart` | Done — text search with popular chips + history, results passed back to explore/home |
| Turf Detail | `screens/booking/turf_detail_screen.dart` | Done — info, date picker, time slots, Book Now |
| My Bookings | `screens/bookings/my_bookings_screen.dart` | Done — status badges, cancel for pending |
| Match Feed | `screens/feed/match_feed_screen.dart` | Done — create/join posts |
| Profile | `screens/profile/profile_screen.dart` | Done — avatar, XP/level, coins, badges, referral card (redesigned with Copy+Share), transactions |
| Leaderboard | `screens/leaderboard/leaderboard_screen.dart` | Done — tier badge, top 10 list |
| Teams | `screens/teams/teams_screen.dart` | Done — create team, join team |
| Tournaments | `screens/tournament/` | Done — list, detail, join, create |
| Settings | `screens/settings/settings_screen.dart` | Done |

### Map Feature (NEW)

| Component | File | Purpose |
|---|---|---|
| Map Explore Screen | `screens/explore/map_explore_screen.dart` | Full-screen FlutterMap + bottom sheet + GPS |
| Preference Sheet | `screens/explore/widgets/preference_sheet.dart` | First-time "GPS or City?" picker |
| Map Top Bar | `screens/explore/widgets/map_top_bar.dart` | Location pill + radius filter + search |
| Turf Pin | `screens/explore/widgets/turf_pin.dart` | Custom price badge map marker |
| Geocoding Service | `data/services/geocoding_service.dart` | Nominatim forward/reverse geocoding |

**Map tiles:** CartoDB dark (`dark_all`) — free, no API key, matches Turfinn theme
**GPS:** `geolocator` package — permission handling, fallback to city mode
**Geocoding:** Nominatim (OpenStreetMap) — free, no key, 1 req/sec

### Desktop Web Shell

`lib/main.dart` wraps the mobile app in a desktop-friendly shell when viewed on web (>600px):
- Phone-like frame with rounded corners and green glow
- Left panel: Turfinn branding + feature pills
- Right panel: "Best on mobile" + store download buttons
- Narrow viewports (<600px): full-width, no frame

### Data Layer

| Model | File |
|---|---|
| Pitch | `data/models/pitch_model.dart` — includes serviceRadiusKm, distanceKm, distanceLabel |
| Booking | `data/models/booking_model.dart` |
| MatchPost | `data/models/match_post_model.dart` |
| Gamification | `data/models/gamification_models.dart` — PlayerProfile, badges, challenges, leaderboard, referral |
| Slot | `data/models/slot_model.dart` — accepts both `start`/`end` and `starts_at`/`ends_at` |
| Review | `data/models/review_model.dart` |
| Manager models | `data/models/manager_models.dart` |
| Tournament | `data/models/tournament_model.dart` |

### Remote Sources

`pitch_remote_source.dart` (supports lat/lng/radius/search params), `booking_remote_source.dart`, `feed_remote_source.dart`, `wallet_remote_source.dart`, `auth_remote_source.dart`, `review_remote_source.dart`, `upload_remote_source.dart`, `manager_remote_source.dart`, `manage_remote_source.dart`, `admin_remote_source.dart`, `superadmin_remote_source.dart`, `dio_client.dart`

### Providers (Riverpod + riverpod_annotation)

`pitch_provider.dart` (supports lat/lng/radius/search), `booking_provider.dart`, `feed_provider.dart`, `wallet_provider.dart`, `auth_provider.dart`, `review_provider.dart`, `upload_provider.dart`, `chat_provider.dart`, `gamification_provider.dart`, `profile_provider.dart`, `tournament_provider.dart`

---

## Turf Manager Web Panel (main_manage.dart)

7 sidebar items + campaigns, all functional:

| View | What it does |
|---|---|
| Dashboard | Stat cards: pitches, bookings, revenue, today's bookings, upcoming |
| My Pitches | Full CRUD — create/edit with **inline map + geocoding + service radius dropdown** |
| Bookings | Basic booking list with confirm/cancel |
| My Analytics | Period selector, summary stats, revenue chart, pitch breakdown, heatmap, peak hours, customer insights |
| My Bookings | Status + source filters, confirm/cancel, Add Walk-in dialog (with payment_method + payment_amount) |
| My Financials | Revenue split, daily ledger, pitch P&L |
| Smart Pricing | Create/toggle/delete pricing rules |
| Campaigns | Manager promo codes — create (with discount_type/value/dates), list, deactivate |

### Pitch Onboarding Map (NEW)

The pitch create/edit dialog now includes:
- "Locate on map" button — forward geocodes address via Nominatim
- 200px inline FlutterMap — tap to place pin, reverse geocodes to fill address/city
- Service radius dropdown: 3km / 5km / 10km / 25km / City-wide (default)
- Lat/lng automatically set from pin position

Remote source: `manage_remote_source.dart` — calls `/manage/*` and `/manager/*` endpoints.

---

## Super Admin Web Panel (main_superadmin.dart)

15 sidebar items, all functional:

| View | Source |
|---|---|
| Dashboard | admin — platform overview stats |
| Users | admin — list/search/filter, role management |
| Pitches | admin — list all, activate/deactivate |
| Bookings | admin — list all, status management |
| Teams | admin — list all teams |
| Matches | admin — list all matchmaking results |
| Platform Config | admin — settings, pricing rules, feature flags, notification templates |
| Marketing | admin — promo codes, campaigns, featured pitches, banners, referral stats |
| KYC / Verification | admin — approve/reject manager applications |
| Disputes & Support | admin — disputes, tickets, flagged reviews, user actions (warn/ban) |
| Business Intelligence | superadmin — GMV, net revenue, active turfs/players, booking funnel, revenue time series |
| Finance & Audit | superadmin — trial balance, VAT report, fraud flags, audit log |
| System Control | superadmin — rate limits, API keys |
| Zones & Partners | superadmin — geographic zones, corporate partners, resellers |
| Turf Onboarding | superadmin — create turfs, assign managers, activate/deactivate |

Remote sources: `admin_remote_source.dart` + `superadmin_remote_source.dart`

---

## E2E Testing

**Test file:** `e2e/tests/full-stack-audit.spec.ts` (Playwright)
**Result:** 108/108 tests pass, 0 bugs found

Coverage:
- 4 user roles tested (player, manager, admin, super_admin)
- All major API flows: auth, pitches, bookings, feed, teams, tournaments, gamification, wallet
- Manager: dashboard, analytics, bookings (with walk-in), financials, promos
- Admin: all 6 sections (dashboard, users, pitches, bookings, platform, marketing, disputes)
- Super Admin: all 17 BI/finance/system endpoints
- Cross-app role enforcement: player blocked from manager/admin, manager blocked from admin
- All 3 Flutter web apps verified loading

---

## What is NOT done

### Payment (deferred by user request)
- bKash integration — no payment gateway connected
- Wallet top-up is backend-only (API works, no actual money flow)
- Booking creation doesn't deduct coins — bookings are free right now

### SMS/OTP Delivery
- OTP is generated and stored in Redis but NOT sent via SMS
- In dev mode, OTP is returned in the API response (`otp_dev` field)
- Need to wire up an SMS provider (Twilio, SSL Wireless, BulkSMSBD)

### Push Notifications
- FCM token storage works (users can update their token)
- No actual push notifications sent
- Firebase worker exists but needs `FIREBASE_SERVICE_ACCOUNT_JSON` env var

### Mobile-specific
- Google Sign-In button exists but OAuth flow isn't connected
- Apple Sign-In button is a placeholder
- No deep linking configured
- No offline mode / local caching

---

## Build Commands

```bash
# Start everything
docker compose up -d --build

# Fresh DB (wipes everything, re-runs all 21 migrations)
docker compose down -v && docker compose up -d --build

# Rebuild Flutter web apps (from project root)
flutter build web --target lib/main.dart --output build/web_app --dart-define=API_BASE_URL=/api/v1
flutter build web --target lib/main_manage.dart --output build/web_manage --dart-define=API_BASE_URL=/api/v1
flutter build web --target lib/main_superadmin.dart --output build/web_superadmin --dart-define=API_BASE_URL=/api/v1

# Restart web containers after rebuild
docker compose restart app manage superadmin

# Run mobile app locally
flutter run

# Backend only (local dev)
cd backend && go run cmd/api/main.go

# Run Go tests
cd backend && go test ./...

# Run Flutter analyze
flutter analyze

# Run build_runner (after model/provider changes)
dart run build_runner build --delete-conflicting-outputs

# Run E2E tests
cd e2e && npx playwright test tests/full-stack-audit.spec.ts --reporter=list
```

## Environment Variables

Backend needs these (set in docker-compose.yml for Docker, or .env for local):

```
APP_PORT=8080
DB_HOST=postgres (Docker) / localhost (local)
DB_USER=turfinn
DB_PASSWORD=turfinn
DB_NAME=turfinn
DB_PORT=5432
REDIS_ADDR=redis:6379 (Docker) / localhost:6379 (local)
ASYNQ_REDIS_ADDR=redis:6379
JWT_SECRET=change-me-in-production
MINIO_ENDPOINT=minio:9000 (Docker) / localhost:9000 (local)
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=minioadmin
MINIO_USE_SSL=false
FIREBASE_SERVICE_ACCOUNT_JSON= (optional, for push notifications)
```

Flutter web apps need `--dart-define=API_BASE_URL=/api/v1` when building for Docker.

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile | Flutter + Riverpod + GoRouter + Dio + Freezed |
| Web panels | Flutter Web (same codebase, different entry points) |
| Maps | flutter_map + OpenStreetMap (CartoDB dark tiles) + Nominatim geocoding |
| Backend | Go + Echo + GORM + Redis + Asynq |
| Database | PostgreSQL 16 (21 migrations) |
| Cache | Redis 7 |
| Storage | MinIO (S3-compatible) |
| Containers | Docker Compose |
| E2E Testing | Playwright (108 tests) |
