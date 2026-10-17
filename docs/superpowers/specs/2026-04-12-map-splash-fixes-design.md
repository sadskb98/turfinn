# Map, Splash & Welcome Screen Fixes — Design Spec
_Date: 2026-04-12_

## Overview

Five independent fixes across the player app and turf manager panel:
1. Splash screen — replace drawn pitch with circle-zoom animation
2. Onboarding slides — swap Unsplash URLs for bundled local assets
3. Welcome screen — remove broken pitch backdrop
4. Map view (explore + manage) — tile swap, pin redesign, GPS fix
5. E2E tests — add map flow coverage

---

## 1. Splash Screen Animation

**Current state:** Green glow blobs + `FootballPitchBackdrop` (drawn pitch) + fading Turfinn logo. Looks wrong.

**Target (from gif.png + user direction):**
Two-phase animation, ~1.4 s total on a solid `AppColors.primary` (`#00DF82`) green background:

**Phase 1 — Ball drop (0 → 700 ms)**
- Black circle (~48 px diameter) starts positioned at the top of the screen (y = -60)
- Falls to the vertical centre with `Curves.easeIn` (gravity acceleration)
- Slight horizontal squeeze at landing (optional: scale x 1.3, y 0.7 for squash, 80 ms)

**Phase 2 — Impact expand (700 → 1400 ms)**
- From the landing position the circle scales up from ~48 px to cover the full screen (scale factor ~30×)
- Curve: `Curves.easeOut` (fast start, decelerates as it fills)
- When circle fully covers screen (black) → navigate

**Implementation approach:**
- `TickerProviderStateMixin` with a single `AnimationController` (1400 ms)
- `Tween<Offset>` for drop: `Offset(0, -screenH / 2)` → `Offset(0, 0)`, interval 0.0→0.5
- `Tween<double>` for scale: `1.0` → `largeScale`, interval 0.5→1.0, curve `Curves.easeOut`
- Position ball using `AnimatedBuilder` + `Transform.translate` + `Transform.scale`
- Navigate in `addStatusListener` when `AnimationStatus.completed`
- No glow blobs, no `FootballPitchBackdrop`, no logo on this screen

---

## 2. Onboarding Slides — Local Assets

**Current state:** Uses 3 Unsplash network URLs. Fails offline, loads slowly, wrong photos.

**Target:** Use the 3 exported Figma images that precisely match the design.

**Assets to bundle:**
| File | Slide |
|---|---|
| `assets/images/backdrop-1.png` | "Book Your Turf Instantly" |
| `assets/images/backdrop-2.png` | "Build Teams & Track Stats" |
| `assets/images/backdrop-3.png` | "Compete in Tournaments" |

**pubspec.yaml:** Add `assets: [assets/images/]` section.

**Implementation:** Copy PNGs from `screenshots/` → `assets/images/`. Change `_Slide.image` to an asset path. Change `Image.network` → `Image.asset` in `_SlideView`. Remove `loadingBuilder`. Keep `errorBuilder`.

---

## 3. Welcome Screen — Remove Pitch Backdrop

**Current state:** Top 38% is `_LogoBanner` containing `FootballPitchBackdrop` (drawn pitch). Looks like a broken sketch.

**Target (from Figma "Sign In/Sign Up" node):** No pitch. Dark background + corner glow blobs only. Turfinn logo (`TurfinnLogo`) + tagline centred, then CTA buttons below. Clean and matches the sign-in/sign-up screens.

**Implementation:**
- Remove `_LogoBanner` widget and `FootballPitchBackdrop` entirely from `welcome_screen.dart`
- Centre the logo + tagline vertically using `Column` with `Spacer` above and below
- Keep glow blobs at corners (already there)
- The `FootballPitchBackdrop` widget file can remain (used nowhere else but keep for safety)

---

## 4. Map Fixes

### 4a. Tile Layer — Voyager

**Both files:**
- `lib/presentation/screens/explore/map_explore_screen.dart`
- `lib/presentation/screens/manage/manage_panel_screen.dart`

**Change:**
```
FROM: https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png
TO:   https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png
```

### 4b. TurfPin Redesign

**Current:** Near-black badge (`#071714`) + green price text + 10×6 px triangle. Invisible on dark map.

**Target:** Proper map pin shape:
- White rounded rect label: `Icons.stadium` (14 px, `AppColors.primaryDark`) + price text (13 px bold, dark)
- Downward-pointing triangle below the label in white
- Selected state: fill entire badge with `AppColors.primary` (green), icons/text go dark
- Size: badge ~80 × 36 px, triangle 10 × 7 px
- `BoxShadow` for lift: `Colors.black.withValues(alpha: 0.3), blurRadius: 6`

### 4c. GPS Fallback

**Current:** On location failure, silently sets `_locationMode = 'city'`, `_city = 'Chittagong'`, moves map — user has no idea.

**Target:**
1. Catch fails in `_acquireLocation()`
2. Show `SnackBar`: "Couldn't get your location — pick a city"
3. Re-open `PreferenceSheet` so user consciously picks
4. Remove the hardcoded Chittagong fallback in the catch block

---

## 5. E2E Tests

**File:** `e2e/tests/full-stack-audit.spec.ts`

**New tests to add:**

| Test | What it covers |
|---|---|
| `GET /pitches?lat=22.35&lng=91.78&radius=5` | Nearby pitches with location params |
| `GET /pitches?city=Chittagong` | City-filtered pitch list |
| `GET /pitches?lat=&lng=&radius=25` | Large radius filter |
| `GET /pitches?search=green` | Text search still works |
| Player app loads at `:3000` | Smoke test |
| Manage app loads at `:3002` | Smoke test |

Flutter web map UI (canvas-rendered) cannot be meaningfully tested with Playwright — tests focus on the API layer that feeds the map.

---

## Files Changed

| File | Change |
|---|---|
| `pubspec.yaml` | Add `assets/images/` |
| `assets/images/backdrop-1.png` | New — copy from screenshots |
| `assets/images/backdrop-2.png` | New — copy from screenshots |
| `assets/images/backdrop-3.png` | New — copy from screenshots |
| `lib/presentation/screens/splash/splash_screen.dart` | Circle-zoom animation |
| `lib/presentation/screens/onboarding/onboarding_screen.dart` | Local assets |
| `lib/presentation/screens/welcome/welcome_screen.dart` | Remove pitch backdrop |
| `lib/presentation/screens/explore/map_explore_screen.dart` | Voyager tiles + GPS fix |
| `lib/presentation/screens/explore/widgets/turf_pin.dart` | Full redesign |
| `lib/presentation/screens/manage/manage_panel_screen.dart` | Voyager tiles |
| `e2e/tests/full-stack-audit.spec.ts` | Map flow tests |

---

## Non-Goals

- Do not touch any backend code
- Do not modify routing logic
- Do not change font families or color tokens
- Do not add new packages
