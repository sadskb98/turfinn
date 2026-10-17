# Play Tab + Feed Redesign

**Date:** 2026-04-24
**Status:** Design

## Problem

Current "Match Feed" tab conflates two unrelated concerns:

1. **Teammate finding** — "I want to play right now, who's around?" — a transactional, location-first task.
2. **Football content** — news, World Cup updates, match recaps — a browse-when-bored engagement loop.

Forcing both into a social-scroll feed makes teammate finding hard to discover and makes content feel buried. Users have to hunt for the "I want to play" action, and the map view is hidden behind a toggle.

## Solution

Split them cleanly:

- **Play tab** (replaces Match Feed) — map-first teammate finding with a single prominent "I want to play" CTA.
- **Feed tab** (new, center slot) — football news, live scores, fixtures, curated content. Engagement hook for when users aren't actively booking. Search + filter.
- **Bell icon** in top bar → app-only notifications (join requests, booking confirmations, gamification badges). Separate from Feed.

The five bottom tabs become: **Pitches · Play · Feed · My Bookings · Profile** — Feed in the center slot for maximum thumb-reach and discoverability.

---

## Play Tab

### Layout

```
┌──────────────────────────────────────┐
│   [avatar]  Hello, Ishmam            │  ← Compact top bar
│                                      │
│                                      │
│         [  MapLibre map  ]           │
│         with post pins               │
│                                      │
│                                      │
│      ┌─────────────────────┐         │
│      │  ▶  I want to play  │         │  ← Primary CTA, floating
│      └─────────────────────┘         │
│                                      │
│  ═══════  nearby list peek  ═══════  │  ← Draggable sheet (20% peek)
│  • Aftab's open match · 2.3 km       │
│  • Need 2 teammates · 4.1 km         │
└──────────────────────────────────────┘
```

- **Default view:** map centered on user location, pins rendered for all nearby `match_posts` within the radius the user picked (reuse the preference pattern from `map_explore_screen.dart`).
- **Pin colors:** white pin = `open_match` (whole match looking for players), amber pin = `need_teammates` (team looking to fill roster). Same scheme already used in `feed_map_view.dart`.
- **Bottom sheet:** draggable (20% peek → 50% → full). Shows nearby posts as a scrollable list sorted by distance. Same pattern as the turf list sheet in `map_explore_screen.dart`.
- **Tap a pin or list item** → floating details card appears over the map with: author name + avatar, title, match date/time, format, spots filled/total, distance, **Join** button.
- **No more list/map toggle button** — the map *is* the feed; the sheet gives you the scrollable list when you want it.

### "I want to play" flow

Tapping the CTA opens a full-screen sheet with the following fields, in this order:

1. **Where** — pin dropped at current GPS, mini-map below with draggable pin, reverse-geocoded label above. Option to pick a specific pitch from the Turfinn roster (chips row).
2. **When** — date picker + start time + duration (defaults: today, +2 hours, 90 min).
3. **Format** — chip group: `5v5 · 6v6 · 7v7 · 11v11`.
4. **I'm looking for** — segmented: `Players (open match)` or `Teammates (my team needs N)`.
5. **Spots needed** — stepper.
6. **Title** (optional, single line).
7. **Note** (optional, 3-line textarea).

Submit → post created → appears as a pin immediately → nearby users get FCM push (existing `match:found` task).

### Component reuse

| New / changed | Reused |
|---|---|
| `play_screen.dart` (replaces `feed_screen.dart` role in home shell) | `MapLibre` setup + pin rendering from `feed_map_view.dart` |
| `play_map_view.dart` (lifted from `feed_map_view.dart`, extended with sheet) | Preference sheet / radius picker from `map_explore_screen.dart` |
| `i_want_to_play_sheet.dart` (replaces `_CreatePostSheet`) | Backend `/api/v1/feed` create + list + join endpoints |
| Details floating card (new, similar to explore pitch card) | `MatchPost` entity + FCM match:found task + match_post_repository geo filter |

### Backend

Almost no change. The existing `/api/v1/feed` endpoints already support:

- `post_type`, `latitude`, `longitude`, `lat/lng/radius` query params
- Distance-sorted response via haversine
- Fire-and-forget FCM push on create
- `POST /api/v1/feed/:id/join`

Two small additions:

- **Duration field** on `match_posts` (migration `032_match_post_duration.sql`): `INT NOT NULL DEFAULT 90` minutes. Surface in DTO + list response.
- **Format field** on `match_posts` (same migration): `VARCHAR(10)` e.g. `'5v5'`, `'11v11'`. Optional — null means unspecified. Surface in DTO.

Both fields are additive and defaulted — no breaking changes to the app.

---

## Feed (Sports News + Notifications)

Moves out of the bottom tab bar. Accessible via a **bell icon** in the top bar of the home screen (shown on Pitches and Play tabs).

### Layout

```
┌──────────────────────────────────────┐
│  Feed                     [🔍]  [🔔] │  ← Search + bell (notifs)
│                                      │
│  ┌──────────────────────────────┐    │
│  │ TODAY · scroll →             │    │  ← Hero strip (horizontal)
│  │ [🔴 Live] [⏰ 20:00] [⏰ ...] │    │
│  └──────────────────────────────┘    │
│                                      │
│  [All] [Live] [News] [Fixtures]      │  ← Filter chips (sticky)
│                                      │
│  ╔══════════════════════════════╗    │
│  ║  [hero image]                ║    │  ← Rich article card
│  ║  PREMIER LEAGUE              ║    │    (big edge-to-edge image)
│  ║  Arsenal stun City 3-1…      ║    │
│  ║  Daily Star · 3h             ║    │
│  ╚══════════════════════════════╝    │
│                                      │
│  ┌──── LIVE ────────────────────┐    │  ← Live score card
│  │  🔴 78'  CHAMPIONS LEAGUE     │    │    (team badges,
│  │  Bayern  [badge] 2 - 1 [badge]│    │     pulsing live dot)
│  │  Arsenal                      │    │
│  └───────────────────────────────┘    │
│                                      │
│  ╔══════════════════════════════╗    │
│  ║  ...more article cards       ║    │
│  ╚══════════════════════════════╝    │
└──────────────────────────────────────┘
```

### Visual design principles

Feed must feel premium — not a text list. The spec locks in these rules:

- **Hero "Today" strip** — horizontally scrolling carousel at the top, above filters. Cards: 🔴 live matches with pulsing dot + scores, upcoming fixtures in next 24h with kickoff countdown. Each card tappable to expand the match.
- **Rich article cards** — big edge-to-edge hero image (16:9), league chip overlaid top-left, source + time bottom-right, dark-mode typography (white headline, `#8FA3A3` meta).
- **Live score cards** — distinct from article cards. Team crests from TheSportsDB, large score counter, minute played with pulsing 🔴 dot, league logo watermark at low opacity.
- **Filter chips** — sticky below the hero strip, horizontally scrollable, active chip filled green (`#00DF82`).
- **Pull-to-refresh** at top; **infinite scroll** at bottom.
- **Image loading** — blur placeholders using `cached_network_image`, shimmer fallback.
- **No dead states** — if both APIs fail, show evergreen static content ("How football works in Bangladesh", "5 rules every futsal player should know") so the screen is never empty.

### Content sources

Two streams, merged chronologically within the main list (hero strip is its own row):

1. **Live matches + fixtures** — API-Football (api-sports.io) free tier: EPL, Champions League, World Cup, Bangladesh national team. Pulled every 15 min.
2. **News articles** — NewsAPI.org (primary) with query `(football OR cricket) AND (bangladesh OR "world cup" OR premier league OR champions league)`. GNews as fallback. Pulled every 30 min.

App notifications are **not** in Feed. They live behind the bell icon on a separate `/notifications` screen.

### Filter chips

- **All** (default, chronological merge of articles + live/upcoming matches)
- **Live** (live matches only)
- **News** (articles only)
- **Fixtures** (upcoming matches only)

### Search

Top-bar magnifier icon → full-text search across cached news titles + descriptions. Local filter, no new API call needed.

### Backend

- New table `news_items`: `id, source, category, title, summary, url, image_url, published_at, payload JSONB, created_at`. Migration `033_news_items.sql`.
- New table `match_events`: `id, source, source_id, league, home_team, away_team, home_score, away_score, kickoff_at, status (live/scheduled/finished), minute_played, payload JSONB, updated_at`. Dedupe on `(source, source_id)`. Migration `034_match_events.sql`.
- New Asynq cron jobs:
  - `news:fetch` every 30 min → NewsAPI + GNews, upsert into `news_items`.
  - `matches:fetch` every 15 min → API-Football, upsert into `match_events`.
- New endpoints:
  - `GET /api/v1/feed/news?category=&search=&page=&limit=` — paginated news articles.
  - `GET /api/v1/feed/matches?status=&page=&limit=` — live + scheduled + finished matches.
  - `GET /api/v1/feed?page=&limit=` — merged chronological feed (news + matches) for the "All" filter.
- **Notifications** (separate surface behind the bell): reuse existing events handler if present; otherwise add `GET /api/v1/notifications?page=&limit=`.

### Flutter

- `feed_tab_screen.dart` → new bottom-tab screen (replaces old feed_screen role).
- `notifications_screen.dart` → separate full-screen route for the bell icon.
- Shared remote source `content_remote_source.dart` → `listFeed`, `listNews`, `listMatches`.
- Type-aware cards: `_HeroStrip`, `_LiveMatchCard`, `_FixtureCard`, `_NewsCard`.
- Uses `cached_network_image` (new dependency) for hero images.

---

## Navigation

### Before

Bottom tabs (4): `Pitches · Match Feed · My Bookings · Profile`

### After

Bottom tabs (5): `Pitches · Play · Feed · My Bookings · Profile`

- **Index 0** — Pitches (unchanged)
- **Index 1** — Play (new map-first teammate finding; replaces the old Match Feed screen)
- **Index 2** — Feed (new; center slot, engagement hub for news + live scores)
- **Index 3** — My Bookings (unchanged, shifted right)
- **Index 4** — Profile (unchanged, shifted right)

Top bar (on Pitches, Play, Feed): `🔔 bell icon` → `/notifications` screen for app-only events.

Route changes in `app_router.dart`:

- `/feed` → repurposed to point to new Feed tab screen (deep-link compat preserved)
- `/play` → new `PlayScreen`
- `/notifications` → new `NotificationsScreen`

Home shell (`home_screen.dart`) updates: `IndexedStack` now has 5 children. Old `feed_screen.dart` + embedded `_CreatePostSheet` + `feed_map_view.dart` are lifted and refactored into the new Play screen; their old locations are deleted. `NavigationBar` gets a fifth destination with appropriate icon (`Icons.article_outlined` / `Icons.article` for Feed).

---

## Out of scope (deferred)

- Chat between users after join (the Join button for now triggers the existing push to post author; actual DM chat is a separate feature).
- Cricket coverage beyond news articles — no cricket fixtures API planned for v1.
- Personalized news ranking — v1 is chronological only.
- Offline news caching in Flutter — can come later with Hive or SharedPreferences.

## Success criteria

- Opening the Play tab shows a map with nearby pins within 2 seconds of location fix.
- Creating an "I want to play" post is ≤ 4 taps from Play tab open.
- Nearby users receive an FCM push within 5 seconds of post creation.
- Feed loads 20 mixed items (news + matches + app events) in one page request.
- Zero extra backend API calls on the per-user path — news is cached server-side.
