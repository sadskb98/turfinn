# Turfinn — Claude Code Master Instructions

## Project Overview

**Turfinn** is a two-sided sports booking platform for Bangladesh's futsal industry. Three frontends, one Go backend.

| App | Entry Point | Target | Port |
|---|---|---|---|
| Player Mobile App | `lib/main.dart` | Football players | `flutter run` or `:3000` (web) |
| Turf Manager Web | `lib/main_manage.dart` | Turf owners | `:3002` |
| Super Admin Web | `lib/main_superadmin.dart` | Platform owner (Turfinn team) | `:3003` |
| Go Backend | `backend/cmd/api/main.go` | API for all apps | `:8080` |

**PRD:** `.claude/PRD.md` — full product requirements document
**Progress:** `PROGRESS.md` — what's built, what's not, all endpoints, build commands
**Figma:** https://www.figma.com/design/tBgNvMBnrDc1d7vH1ELut6/Turfinn?node-id=0-1

> **Before building any UI:** Fetch the Figma file, analyze screens, extract design tokens.
> **Before building any feature:** Read `PROGRESS.md` to know what exists.

---

## Architecture — Three Apps, One Backend

```
Player (Flutter Mobile)          Turf Manager (Flutter Web)       Super Admin (Flutter Web)
       |                                  |                               |
       |          ┌───────────────────────┘                               |
       |          |                                                       |
       └────────> Go API (:8080) <────────────────────────────────────────┘
                    |
            ┌───────┼───────┐
         Postgres  Redis   MinIO
```

**Player app** = mobile-first (iOS/Android/web). 4-tab bottom nav: Pitches, Match Feed, My Bookings, Profile.

**Turf Manager** = web dashboard for turf owners. 7 sidebar items: Dashboard, My Pitches, Bookings, My Analytics, My Bookings (with walk-in), My Financials, Smart Pricing.

**Super Admin** = web dashboard for Turfinn team. 15 sidebar items covering operations, BI, finance, system control, zones, turf onboarding.

---

## Go Backend — 128 Endpoints

All routes in `backend/internal/interfaces/http/router.go`. Key route groups:

| Prefix | Auth | Handler | Purpose |
|---|---|---|---|
| `/api/v1/auth` | None | auth_handler.go | OTP + Google Sign-In |
| `/api/v1/pitches` | Public/Auth | pitch_handler.go | List, get, slots, create |
| `/api/v1/bookings` | Auth | booking_handler.go | Create, list mine, cancel |
| `/api/v1/feed` | Auth | match_post_handler.go | Match feed CRUD + join |
| `/api/v1/wallet` | Auth | wallet_handler.go | Balance, top-up, transactions |
| `/api/v1/profile` | Auth | wallet_handler.go | Player profile + badges |
| `/api/v1/teams` | Auth | team_handler.go | Teams + matchmaking |
| `/api/v1/manager` | Auth + RequireManager | manager_handler.go | Analytics, bookings, financials |
| `/api/v1/manage` | Auth + RequireRole(manager,admin) | manage_handler.go | Turf owner CRUD |
| `/api/v1/admin` | Auth + RequireRole(admin) | admin_handler.go | Admin operations |
| `/api/v1/admin/platform` | Auth + RequireRole(admin,super_admin) | platform_handler.go | Config, pricing, flags |
| `/api/v1/admin/marketing` | Auth + RequireRole(admin,super_admin) | marketing_handler.go | Promo, campaigns, banners |
| `/api/v1/admin/disputes,tickets,reviews,kyc` | Auth + RequireRole(admin,super_admin) | dispute_handler.go | Support + moderation |
| `/api/v1/super-admin` | Auth + RequireRole(super_admin) | superadmin_handler.go | BI, finance, system |

### Business Rules Implemented

- **Booking conflicts** — time overlap check before creation
- **Cancellation** — 6+ hours = full wallet refund, <6 hours = no refund, past = rejected
- **Booking validation** — no past, 30min-4hr duration, 08:00-00:00 hours, max 30 days ahead
- **Smart pricing** — pricing_rules checked during booking, applies multiplier/fixed by day+time
- **Gamification** — 5 badges auto-awarded via fire-and-forget goroutines after bookings/feed actions
- **Rate limiting** — 5/min OTP, 100/min global
- **Input sanitization** — html.EscapeString on user content

### Database — 41 Tables

Migrations: `backend/migrations/001_initial.sql` through `014_match_post_joins.sql`
Docker Compose mounts these into Postgres init directory — runs on first DB creation.

**If you add a migration:** Number it `015_xxx.sql`. Use `IF NOT EXISTS` / `IF EXISTS` guards. Never use `-- +migrate Down` in the same file (Postgres runs the whole file including drops).

---

## Flutter — Shared Rules

### Stack
| Concern | Package |
|---|---|
| State | `flutter_riverpod` + `riverpod_annotation` |
| Navigation | `go_router` |
| HTTP | `dio` with auth interceptor |
| Models | `freezed` + `json_serializable` |
| Fonts | `google_fonts` (Nunito for headers, DM Sans for body) |

### Rules
- Use `const` constructors everywhere possible
- Never use `setState` for business logic — Riverpod only (local UI state like filters is OK)
- Never hardcode colors — use `AppColors` from `lib/core/theme/app_colors.dart`
- All models must be `freezed` with `fromJson`/`toJson`
- After adding/changing models or providers, run: `dart run build_runner build --delete-conflicting-outputs`
- Handle **loading**, **error**, and **empty** states on every async widget

### Theme Constants
- Primary: `#00DF82` (bright green)
- Background: `#030F0F` (near-black)
- Primary Dark: `#061512`
- Primary Deep: `#02463A`
- Text Primary: white
- Text Secondary: `#8FA3A3`

### Dio Client
`lib/data/sources/remote/dio_client.dart` — base URL from `--dart-define=API_BASE_URL`:
- Docker: `--dart-define=API_BASE_URL=/api/v1` (nginx proxies)
- Local dev: defaults to `http://localhost:8081/api/v1`
- JWT token attached from SharedPreferences via interceptor

---

## Mobile App (main.dart)

### Routes (app_router.dart)
| Route | Screen | Auth |
|---|---|---|
| `/` | Splash | No |
| `/welcome` | Welcome | No |
| `/sign-up` | Sign Up (phone input) | No |
| `/otp` | OTP verify | No |
| `/home` | Home shell (4 tabs) | Yes |
| `/pitch/:id` | Pitch detail + booking | Yes |
| `/my-bookings` | My bookings list | Yes |
| `/feed` | Match feed | Yes |
| `/profile` | Player profile | Yes |
| `/settings` | Settings + logout | Yes |
| `/teams` | Teams | Yes |
| `/manager` | Manager shell (for manager role) | Yes + manager |

### Home Screen Structure
4-tab `IndexedStack` with `NavigationBar`:
1. Pitches — search bar + pitch cards with images
2. Match Feed — create/join posts
3. My Bookings — status badges, cancel pending
4. Profile — avatar, coins, badges, transactions, top-up

---

## Web Panels — Shared Pattern

Both web panels use `PanelScaffold` (collapsible sidebar + body) with `IndexedStack` for views.

Each view is a `ConsumerStatefulWidget` with:
```dart
_load() in initState → setState(_loading = true) → API call → if (mounted) setState(_loading = false)
```

Shared widgets in `lib/presentation/screens/panel/widgets/`:
- `PanelScaffold` — sidebar layout
- `StatCard` — metric card with icon
- `DataTableCard` — table with columns, rows, refresh button

Remote sources:
- Turf Manager: `manage_remote_source.dart` → `/manage/*` + `/manager/*`
- Super Admin: `admin_remote_source.dart` + `superadmin_remote_source.dart`

---

## Feature Build Order

For any new feature:

1. Check `PROGRESS.md` — does it already exist?
2. SQL migration → `backend/migrations/0XX_name.sql`
3. Entity → `backend/internal/domain/entity/`
4. Repository interface → `backend/internal/domain/repository/`
5. GORM implementation → `backend/internal/infrastructure/repository/`
6. Service → `backend/internal/application/service/`
7. DTOs → `backend/internal/interfaces/dto/`
8. Handler → `backend/internal/interfaces/http/handler/`
9. Register route in `router.go`
10. Wire in `main.go`
11. Verify: `go build ./...`
12. Flutter freezed model → `lib/data/models/`
13. Remote source → `lib/data/sources/remote/`
14. Provider → `lib/presentation/providers/`
15. Screen → `lib/presentation/screens/`
16. Run `dart run build_runner build --delete-conflicting-outputs`
17. Verify: `flutter analyze`

---

## What's NOT Done (needs building)

| Feature | Complexity | Notes |
|---|---|---|
| **bKash payment integration** | High | Needs API keys, payment gateway SDK |
| **SMS OTP delivery** | Medium | Wire Twilio/SSL Wireless into Asynq worker |
| **Push notifications** | Medium | FCM token stored, need to send via Firebase |
| **Google Sign-In (mobile)** | Medium | OAuth client ID needed |
| **Deep linking** | Low | GoRouter supports it, just needs config |
| **Offline caching** | Medium | SharedPreferences or Hive for pitches/bookings |

---

## Docker Commands

```bash
# Full stack
docker compose up -d --build

# Rebuild Flutter web apps
flutter build web --target lib/main.dart --output build/web_app --dart-define=API_BASE_URL=/api/v1
flutter build web --target lib/main_manage.dart --output build/web_manage --dart-define=API_BASE_URL=/api/v1
flutter build web --target lib/main_superadmin.dart --output build/web_superadmin --dart-define=API_BASE_URL=/api/v1
docker compose restart app manage superadmin

# Fresh DB (wipes everything)
docker compose down -v && docker compose up -d --build

# Logs
docker compose logs api --tail 50 -f

# Backend tests
cd backend && go test ./...
```

## Non-Negotiables
- Never skip error handling
- Never use `interface{}` — typed structs only
- Never expose DB models in API responses — always use DTOs
- Never store secrets in code — `.env` / docker-compose env only
- Always paginate list endpoints
- Redis TTL always explicit
- Cache always invalidated on mutation
- SQL migrations: always use `IF NOT EXISTS` guards, never include `-- +migrate Down` sections
- GORM Count queries: always clone with `q.Session(&gorm.Session{})` before Count
- Badge/gamification checks: always fire-and-forget (goroutine), never block the main operation
