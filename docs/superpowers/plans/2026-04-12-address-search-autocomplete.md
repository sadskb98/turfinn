# Address Search Autocomplete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add live address autocomplete dropdown to the pitch creation/edit form so managers can find their pitch location by typing partial addresses rather than entering a complete address first.

**Architecture:** Add a `suggest()` static method to the existing `GeocodingService`. Replace the `_FormField(label: 'Address *', ...)` in `_PitchFormDialogState` with a new inline stateful widget `_AddressSearchField` that debounces keystrokes, calls `suggest()`, and shows suggestions via `OverlayPortal`. The "Locate on map" button and `_onPinPlaced` are unchanged.

**Tech Stack:** Nominatim API (already in `GeocodingService`), `OverlayPortal` (Flutter 3.7+), `dart:async` Timer for debounce, `latlong2` LatLng (already in use).

---

### Task 1: Add `suggest()` method to `GeocodingService`

**Files:**
- Modify: `lib/data/services/geocoding_service.dart`

- [ ] **Step 1: Add `AddressSuggestion` typedef and `suggest()` method**

Open `lib/data/services/geocoding_service.dart`. The current file ends at line 52. Add after the closing brace of the `reverse()` method and before the final `}` of the class:

```dart
  /// Address suggestion returned by autocomplete.
  static const _minQueryLength = 3;

  /// Returns up to 5 address suggestions for the given query.
  /// Worldwide — no country restriction. Returns empty list on error
  /// or when query is fewer than 3 characters.
  static Future<List<({String displayName, LatLng latLng})>> suggest(
      String query) async {
    if (query.trim().length < _minQueryLength) return [];
    try {
      final resp = await _dio.get('/search', queryParameters: {
        'q': query,
        'format': 'json',
        'limit': 5,
        'addressdetails': 0,
      });
      final results = resp.data as List;
      return results.map((r) {
        final map = r as Map<String, dynamic>;
        return (
          displayName: map['display_name'] as String,
          latLng: LatLng(
            double.parse(map['lat'] as String),
            double.parse(map['lon'] as String),
          ),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
```

The full updated file looks like this:

```dart
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

class GeocodingService {
  static final _dio = Dio(BaseOptions(
    baseUrl: 'https://nominatim.openstreetmap.org',
    headers: {'User-Agent': 'Turfinn/1.0 (turfinn.com)'},
  ));

  static const _minQueryLength = 3;

  /// Forward geocode: address string → LatLng
  static Future<LatLng?> forward(String address) async {
    try {
      final resp = await _dio.get('/search', queryParameters: {
        'q': address,
        'format': 'json',
        'countrycodes': 'bd',
        'limit': 1,
      });
      final results = resp.data as List;
      if (results.isEmpty) return null;
      final r = results.first;
      return LatLng(
        double.parse(r['lat'] as String),
        double.parse(r['lon'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  /// Reverse geocode: LatLng → address components
  static Future<({String address, String city})?> reverse(LatLng point) async {
    try {
      final resp = await _dio.get('/reverse', queryParameters: {
        'lat': point.latitude,
        'lon': point.longitude,
        'format': 'json',
      });
      final data = resp.data as Map<String, dynamic>;
      final addr = data['address'] as Map<String, dynamic>? ?? {};
      final road = addr['road'] ?? addr['neighbourhood'] ?? '';
      final area = addr['suburb'] ?? addr['county'] ?? '';
      final city = addr['city'] ?? addr['town'] ?? addr['state_district'] ?? '';
      return (
        address: [road, area].where((s) => s.toString().isNotEmpty).join(', '),
        city: city.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns up to 5 address suggestions for the given query.
  /// Worldwide — no country restriction. Returns empty list on error
  /// or when query is fewer than 3 characters.
  static Future<List<({String displayName, LatLng latLng})>> suggest(
      String query) async {
    if (query.trim().length < _minQueryLength) return [];
    try {
      final resp = await _dio.get('/search', queryParameters: {
        'q': query,
        'format': 'json',
        'limit': 5,
        'addressdetails': 0,
      });
      final results = resp.data as List;
      return results.map((r) {
        final map = r as Map<String, dynamic>;
        return (
          displayName: map['display_name'] as String,
          latLng: LatLng(
            double.parse(map['lat'] as String),
            double.parse(map['lon'] as String),
          ),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn && flutter analyze lib/data/services/geocoding_service.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/data/services/geocoding_service.dart
git commit -m "feat: add GeocodingService.suggest() for address autocomplete"
```

---

### Task 2: Replace address field with `_AddressSearchField` in `_PitchFormDialogState`

**Files:**
- Modify: `lib/presentation/screens/manage/manage_panel_screen.dart`

The current pitch form (around line 1349) has:
```dart
_FormField(label: 'Address *', controller: _address),
```

We replace this with a new inline stateful widget `_AddressSearchField` that wraps `_address` and shows an autocomplete overlay.

- [ ] **Step 1: Add `dart:async` import if not already present**

Check the top of `manage_panel_screen.dart` for `dart:async`. If absent, add it:
```dart
import 'dart:async';
```

- [ ] **Step 2: Add `_AddressSearchField` widget class**

At the bottom of `manage_panel_screen.dart` (after the `_ChartCard` class or the last class in the file, before EOF), add:

```dart
// ─────────────────────────────────────────────────────────────────────────────
// Address autocomplete field for pitch form
// ─────────────────────────────────────────────────────────────────────────────
class _AddressSearchField extends StatefulWidget {
  const _AddressSearchField({
    required this.controller,
    required this.onSuggestionSelected,
  });

  final TextEditingController controller;
  /// Called with the chosen LatLng when user taps a suggestion.
  final void Function(LatLng latLng) onSuggestionSelected;

  @override
  State<_AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends State<_AddressSearchField> {
  List<({String displayName, LatLng latLng})> _suggestions = [];
  bool _loading = false;
  Timer? _debounce;
  final OverlayPortalController _overlayCtrl = OverlayPortalController();
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final text = widget.controller.text;
    _debounce?.cancel();
    if (text.trim().length < 3) {
      if (_overlayCtrl.isShowing) _overlayCtrl.hide();
      if (mounted) setState(() { _suggestions = []; _loading = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _fetchSuggestions(text));
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted) return;
    setState(() => _loading = true);
    if (!_overlayCtrl.isShowing) _overlayCtrl.show();
    final results = await GeocodingService.suggest(query);
    if (!mounted) return;
    setState(() {
      _suggestions = results;
      _loading = false;
    });
    if (results.isEmpty && _overlayCtrl.isShowing) _overlayCtrl.hide();
  }

  void _selectSuggestion(({String displayName, LatLng latLng}) suggestion) {
    widget.controller.removeListener(_onChanged);
    widget.controller.text = suggestion.displayName;
    widget.controller.addListener(_onChanged);
    _overlayCtrl.hide();
    setState(() { _suggestions = []; _loading = false; });
    widget.onSuggestionSelected(suggestion.latLng);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _overlayCtrl,
        overlayChildBuilder: (ctx) => CompositedTransformFollower(
          link: _layerLink,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 452),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1F1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primaryDeep),
              ),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _suggestions.map((s) {
                        return InkWell(
                          onTap: () => _selectSuggestion(s),
                          highlightColor: AppColors.primaryDeep.withValues(alpha: 0.3),
                          child: SizedBox(
                            height: 40,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    size: 13,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      s.displayName,
                                      style: GoogleFonts.dmSans(
                                        fontSize: 13,
                                        color: AppColors.textPrimary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ),
        ),
        child: Focus(
          onFocusChange: (hasFocus) {
            if (!hasFocus && _overlayCtrl.isShowing) _overlayCtrl.hide();
          },
          child: TextFormField(
            controller: widget.controller,
            style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Address *',
              labelStyle: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.inputStroke),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.inputStroke),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Replace the address `_FormField` in `_PitchFormDialogState.build()`**

Find this line (around line 1349):
```dart
              _FormField(label: 'Address *', controller: _address),
```

Replace with:
```dart
              _AddressSearchField(
                controller: _address,
                onSuggestionSelected: _onPinPlaced,
              ),
```

- [ ] **Step 4: Verify**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn && flutter analyze lib/presentation/screens/manage/manage_panel_screen.dart
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/manage/manage_panel_screen.dart
git commit -m "feat: add address autocomplete to pitch form (_AddressSearchField)"
```

---

### Task 3: Build and smoke-test

- [ ] **Step 1: Full analyze pass**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn && flutter analyze
```

Expected: no errors.

- [ ] **Step 2: Build manage web app**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn && flutter build web --target lib/main_manage.dart --output build/web_manage --dart-define=API_BASE_URL=/api/v1
```

Expected: `✓ Built build/web_manage` with no errors.

- [ ] **Step 3: Manual smoke-test checklist**

Open the pitch create/edit dialog and verify:
- [ ] Typing fewer than 3 characters shows no overlay
- [ ] Typing 3+ characters waits ~400ms then shows a loading spinner
- [ ] Results appear as a dropdown list with location pin icons
- [ ] Tapping a suggestion fills the address field and moves the map pin
- [ ] Overlay dismisses on focus loss
- [ ] "Locate on map" button still works (geocodes the typed address)
- [ ] Tapping the map directly still places a pin and reverse-geocodes the address

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: address search autocomplete complete — GeocodingService.suggest + _AddressSearchField"
```
