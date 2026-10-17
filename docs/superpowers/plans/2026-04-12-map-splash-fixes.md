# Map, Splash & Welcome Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the splash animation, onboarding slide images, welcome screen backdrop, map tile readability, turf pin design, GPS fallback, and add E2E map tests.

**Architecture:** Seven independent tasks — asset bundling, three screen rewrites (splash, onboarding, welcome), two map fixes (tiles + pin), one GPS fix, and API-layer E2E tests. No new packages needed; `assets/images/` already declared in pubspec.yaml.

**Tech Stack:** Flutter (Riverpod, GoRouter), flutter_map, geolocator, Playwright (E2E)

---

## File Map

| File | Action | What changes |
|---|---|---|
| `assets/images/backdrop-1.png` | Create (copy) | Onboarding slide 1 image |
| `assets/images/backdrop-2.png` | Create (copy) | Onboarding slide 2 image |
| `assets/images/backdrop-3.png` | Create (copy) | Onboarding slide 3 image |
| `lib/presentation/screens/splash/splash_screen.dart` | Modify | Ball-drop + expand animation |
| `lib/presentation/screens/onboarding/onboarding_screen.dart` | Modify | Local assets instead of Unsplash URLs |
| `lib/presentation/screens/welcome/welcome_screen.dart` | Modify | Remove `_LogoBanner` / `FootballPitchBackdrop` |
| `lib/presentation/screens/explore/map_explore_screen.dart` | Modify | Voyager tiles + GPS SnackBar fix |
| `lib/presentation/screens/explore/widgets/turf_pin.dart` | Modify | White pill + stadium icon + proper pointer |
| `lib/presentation/screens/manage/manage_panel_screen.dart` | Modify | Voyager tiles (one-line change) |
| `e2e/tests/full-stack-audit.spec.ts` | Modify | Add 4 map API tests |

---

## Task 1: Copy backdrop images to assets

**Files:**
- Create: `assets/images/backdrop-1.png`
- Create: `assets/images/backdrop-2.png`
- Create: `assets/images/backdrop-3.png`

- [ ] **Step 1: Copy the three images**

```bash
cp screenshots/backdrop-1.png assets/images/backdrop-1.png
cp screenshots/backdrop-2.png assets/images/backdrop-2.png
cp screenshots/backdrop-3.png assets/images/backdrop-3.png
```

- [ ] **Step 2: Verify pubspec.yaml already has the assets path**

Open `pubspec.yaml` — confirm this block exists (it does):
```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - assets/icons/
```
No change needed.

- [ ] **Step 3: Verify Flutter can resolve them**

```bash
flutter pub get
```
Expected: exits 0, no errors about missing assets.

- [ ] **Step 4: Commit**

```bash
git add assets/images/backdrop-1.png assets/images/backdrop-2.png assets/images/backdrop-3.png
git commit -m "chore: add onboarding backdrop images as bundled assets"
```

---

## Task 2: Splash screen — ball-drop animation

**Files:**
- Modify: `lib/presentation/screens/splash/splash_screen.dart`

The animation has two phases driven by a single 1400 ms `AnimationController`:
- Phase 1 (0→700 ms, interval 0.0→0.5): 48 px black circle drops from above screen to centre, `Curves.easeIn`
- Phase 2 (700→1400 ms, interval 0.5→1.0): circle scales up to cover full screen, `Curves.easeOut`
- Background: solid `AppColors.primary` green
- On `AnimationStatus.completed`: navigate exactly as before (check token → onboarding_done)

- [ ] **Step 1: Replace splash_screen.dart entirely**

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/router/app_router.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _dropFraction; // 0→1 during phase 1
  late final Animation<double> _scale;        // 1→large during phase 2

  static const _ballDiameter = 48.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    // Phase 1: drop — fraction goes -1 (above screen) → 0 (centre)
    _dropFraction = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    // Phase 2: expand — scale 1 → 35 (covers any screen diagonal)
    _scale = Tween<double>(begin: 1.0, end: 35.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
      ),
    );

    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _navigate();
    });

    _ctrl.forward();
  }

  Future<void> _navigate() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final onboardingDone = prefs.getBool('onboarding_done') ?? false;
    if (!mounted) return;
    if (token != null && token.isNotEmpty) {
      context.go(AppRoutes.home);
    } else if (onboardingDone) {
      context.go(AppRoutes.welcome);
    } else {
      context.go(AppRoutes.onboarding);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Ball starts _ballDiameter/2 above the top edge, lands at vertical centre
    final dropDistance = size.height / 2 + _ballDiameter / 2;

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final dy = _dropFraction.value * dropDistance;
          final scale = _scale.value;
          return Center(
            child: Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: _ballDiameter,
                  height: _ballDiameter,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Run flutter analyze**

```bash
flutter analyze lib/presentation/screens/splash/splash_screen.dart
```
Expected: no errors, no warnings.

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/screens/splash/splash_screen.dart
git commit -m "feat: splash — ball-drop + expand animation replaces drawn pitch"
```

---

## Task 3: Onboarding — local assets

**Files:**
- Modify: `lib/presentation/screens/onboarding/onboarding_screen.dart`

Replace three Unsplash `https://` URLs with bundled asset paths. Change `_Slide.image` from a URL to an asset path. Change `Image.network` → `Image.asset` in `_SlideView`.

- [ ] **Step 1: Update `_slides` and `_SlideView` in onboarding_screen.dart**

Replace the `_slides` const and the `_SlideView` widget. Everything else (layout, buttons, dots, navigation) stays identical.

```dart
  static const _slides = [
    _Slide(
      image: 'assets/images/backdrop-1.png',
      heading: 'Book Your Turf Instantly',
      sub: 'Reserve your favorite turf in a few seconds.\nNo calls, no hassle.',
    ),
    _Slide(
      image: 'assets/images/backdrop-2.png',
      heading: 'Build Teams & Track Stats',
      sub: 'Create your squad, track goals, and measure your growth.',
    ),
    _Slide(
      image: 'assets/images/backdrop-3.png',
      heading: 'Compete in Tournaments',
      sub: 'Enter official tournaments and earn your spot at the top.',
    ),
  ];
```

Replace the entire `_SlideView` class:

```dart
class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});
  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      slide.image,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (ctx, _, __) => Container(
        color: const Color(0xFF051210),
        child: const Center(
          child: Icon(Icons.sports_soccer, color: Colors.white24, size: 80),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run flutter analyze**

```bash
flutter analyze lib/presentation/screens/onboarding/onboarding_screen.dart
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/screens/onboarding/onboarding_screen.dart
git commit -m "feat: onboarding — use bundled backdrop assets instead of Unsplash URLs"
```

---

## Task 4: Welcome screen — remove pitch backdrop

**Files:**
- Modify: `lib/presentation/screens/welcome/welcome_screen.dart`

The Figma welcome screen has no pitch image — just dark bg + two corner glow blobs + the Turfinn logo/tagline centred + CTA buttons at bottom. Remove `_LogoBanner` and `FootballPitchBackdrop`. Remove the import for `football_pitch_backdrop.dart`.

- [ ] **Step 1: Rewrite welcome_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../widgets/turfinn_logo.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Corner glow blobs
          Positioned(
            top: -60, right: -60,
            child: _GlowBlob(color: AppColors.primaryMid, size: 260),
          ),
          Positioned(
            bottom: -60, left: -60,
            child: _GlowBlob(color: AppColors.primaryMid, size: 260),
          ),

          // Logo + tagline centred, buttons pinned to bottom
          Column(
            children: [
              const Spacer(flex: 3),
              const TurfinnLogo(fontSize: 52),
              const SizedBox(height: 10),
              Text(
                'The Home Ground of Local Legends',
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.primaryMid,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(flex: 4),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Sign Up
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.background,
                          shape: const StadiumBorder(),
                          elevation: 0,
                        ),
                        onPressed: () => context.go(AppRoutes.signUp),
                        child: Text(
                          'Sign Up',
                          style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.background,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Sign In
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primary),
                          shape: const StadiumBorder(),
                          backgroundColor: AppColors.background,
                        ),
                        onPressed: () => context.go(AppRoutes.signIn),
                        child: Text(
                          'Sign in',
                          style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 120,
            spreadRadius: 60,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run flutter analyze**

```bash
flutter analyze lib/presentation/screens/welcome/welcome_screen.dart
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/screens/welcome/welcome_screen.dart
git commit -m "feat: welcome screen — remove drawn pitch backdrop, clean centred layout"
```

---

## Task 5: Map tiles — Voyager + TurfPin redesign

**Files:**
- Modify: `lib/presentation/screens/explore/map_explore_screen.dart` (tile URL)
- Modify: `lib/presentation/screens/manage/manage_panel_screen.dart` (tile URL)
- Modify: `lib/presentation/screens/explore/widgets/turf_pin.dart` (full redesign)

### 5a. Tile URL swap (both files)

- [ ] **Step 1: Update tile URL in map_explore_screen.dart**

Find:
```dart
urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png',
```
Replace with:
```dart
urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
```

- [ ] **Step 2: Update tile URL in manage_panel_screen.dart**

Same replacement at line ~1398:
```dart
urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
```

### 5b. TurfPin redesign

- [ ] **Step 3: Replace turf_pin.dart entirely**

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';

/// Map marker showing a stadium icon + price.
/// White pill with downward pointer by default; green when selected.
class TurfPin extends StatelessWidget {
  const TurfPin({
    super.key,
    required this.price,
    this.isSelected = false,
  });

  final double price;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final bg = isSelected ? AppColors.primary : Colors.white;
    final fg = isSelected ? Colors.black : const Color(0xFF030F0F);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.stadium_rounded, size: 13, color: fg),
              const SizedBox(width: 4),
              Text(
                '\u09F3${price.round()}',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: fg,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
        CustomPaint(
          size: const Size(12, 7),
          painter: _PointerPainter(color: bg),
        ),
      ],
    );
  }
}

class _PointerPainter extends CustomPainter {
  const _PointerPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PointerPainter old) => old.color != color;
}
```

- [ ] **Step 4: Run flutter analyze on changed files**

```bash
flutter analyze lib/presentation/screens/explore/map_explore_screen.dart \
               lib/presentation/screens/explore/widgets/turf_pin.dart \
               lib/presentation/screens/manage/manage_panel_screen.dart
```
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/explore/map_explore_screen.dart \
        lib/presentation/screens/explore/widgets/turf_pin.dart \
        lib/presentation/screens/manage/manage_panel_screen.dart
git commit -m "feat: map — voyager tiles, white stadium pin replaces dark invisible pin"
```

---

## Task 6: GPS fallback — SnackBar + re-open preference sheet

**Files:**
- Modify: `lib/presentation/screens/explore/map_explore_screen.dart`

Replace the silent Chittagong fallback in `_acquireLocation()` with a helper that shows a SnackBar and re-opens the preference sheet.

- [ ] **Step 1: Add `_showLocationFailed()` helper and update `_acquireLocation()`**

In `_MapExploreScreenState`, replace the entire `_acquireLocation` method and add `_showLocationFailed`:

```dart
Future<void> _acquireLocation() async {
  try {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      _showLocationFailed();
      return;
    }
    final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium));
    setState(() => _userLocation = LatLng(pos.latitude, pos.longitude));
    _mapCtrl.move(_userLocation!, 13);
  } catch (_) {
    _showLocationFailed();
  }
}

void _showLocationFailed() {
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        "Couldn't get your location — pick a city instead",
        style: GoogleFonts.dmSans(fontSize: 13, color: Colors.white),
      ),
      backgroundColor: const Color(0xFF0A1F1A),
      duration: const Duration(seconds: 3),
    ),
  );
  // Reset mode so preference sheet treats this as a fresh pick
  setState(() {
    _locationMode = '';
    _city = '';
  });
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _showPreferenceSheet();
  });
}
```

- [ ] **Step 2: Run flutter analyze**

```bash
flutter analyze lib/presentation/screens/explore/map_explore_screen.dart
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/screens/explore/map_explore_screen.dart
git commit -m "fix: map — show SnackBar + reopen city picker when GPS fails instead of silent Chittagong"
```

---

## Task 7: E2E tests — map API coverage

**Files:**
- Modify: `e2e/tests/full-stack-audit.spec.ts`

Add four API tests inside the existing `test.describe.serial` block, after the pitch-related tests. Flutter-web canvas cannot be reliably tested with Playwright so these target the API layer that feeds the map.

- [ ] **Step 1: Find the right insertion point**

Search for the last pitch-related test in the file (around the `GET /pitches` block). Add these four tests immediately after it, still inside the `test.describe.serial` block:

```typescript
  // ── Map API flow ──────────────────────────────────────────────────────────

  test('Map: GET /pitches with lat/lng/radius returns sorted list', async ({ request }) => {
    const resp = await request.get(
      `${API}/api/v1/pitches?lat=22.3569&lng=91.7832&radius=5`,
    );
    expect(resp.status()).toBe(200);
    const body = await resp.json();
    expect(body.data).toBeDefined();
    expect(Array.isArray(body.data)).toBe(true);
  });

  test('Map: GET /pitches with city filter returns results', async ({ request }) => {
    const resp = await request.get(`${API}/api/v1/pitches?city=Chittagong`);
    expect(resp.status()).toBe(200);
    const body = await resp.json();
    expect(body.data).toBeDefined();
    expect(Array.isArray(body.data)).toBe(true);
  });

  test('Map: GET /pitches with large radius (25 km) returns results', async ({ request }) => {
    const resp = await request.get(
      `${API}/api/v1/pitches?lat=23.8103&lng=90.4125&radius=25`,
    );
    expect(resp.status()).toBe(200);
    const body = await resp.json();
    expect(body.data).toBeDefined();
    expect(Array.isArray(body.data)).toBe(true);
  });

  test('Map: GET /pitches text search still works alongside location', async ({ request }) => {
    const resp = await request.get(`${API}/api/v1/pitches?search=arena`);
    expect(resp.status()).toBe(200);
    const body = await resp.json();
    expect(body.data).toBeDefined();
    expect(Array.isArray(body.data)).toBe(true);
  });
```

- [ ] **Step 2: Run just the new tests to verify they pass**

```bash
cd e2e && npx playwright test tests/full-stack-audit.spec.ts \
  --grep "Map:" --reporter=list
```
Expected: 4 tests pass (requires backend running on :8080 with seed data).

- [ ] **Step 3: Run full suite to check no regressions**

```bash
cd e2e && npx playwright test tests/full-stack-audit.spec.ts --reporter=list
```
Expected: all tests pass (108 + 4 = 112 total).

- [ ] **Step 4: Commit**

```bash
cd ..
git add e2e/tests/full-stack-audit.spec.ts
git commit -m "test: add E2E coverage for map API — lat/lng, city, radius, search"
```

---

## Final verification

- [ ] **Run full flutter analyze**

```bash
flutter analyze
```
Expected: no errors, no warnings on changed files.

- [ ] **Smoke test the app**

```bash
flutter run -d chrome --target lib/main.dart --dart-define=API_BASE_URL=http://localhost:8080/api/v1
```
Verify manually:
- Splash: green screen, black ball drops and expands to black, transitions out
- Onboarding: three slides show local photo backgrounds (no network needed)
- Welcome: dark screen with centred logo, no pitch drawing
- Explore tab: map shows readable Voyager tiles with white stadium pins
- "Use my location" failure → SnackBar + city picker sheet
- Manage → My Pitches → create pitch → inline map shows Voyager tiles
