# Address Search Autocomplete — Design Spec
_Date: 2026-04-12_

## Overview

The pitch creation/edit form in the turf manager panel has a plain address text field and a "Locate on map" button. To find their pitch location, a manager must type a complete address, then click the button. This spec adds live autocomplete suggestions as the manager types — a dropdown appears below the field with up to 5 matching places, and tapping one fills the address and moves the map pin.

---

## 1. `GeocodingService` Changes

File: `lib/data/services/geocoding_service.dart`

Add a new method and a new data type:

```dart
/// Address suggestion returned by autocomplete
typedef AddressSuggestion = ({String displayName, LatLng latLng});

/// Returns up to 5 address suggestions for the given query.
/// Worldwide (no countrycodes restriction).
/// Returns empty list on error or query < 3 chars.
static Future<List<AddressSuggestion>> suggest(String query) async {
  if (query.trim().length < 3) return [];
  try {
    final resp = await _dio.get('/search', queryParameters: {
      'q': query,
      'format': 'json',
      'limit': 5,
      'addressdetails': 0,
    });
    final results = resp.data as List;
    return results.map((r) => (
      displayName: r['display_name'] as String,
      latLng: LatLng(
        double.parse(r['lat'] as String),
        double.parse(r['lon'] as String),
      ),
    )).toList();
  } catch (_) {
    return [];
  }
}
```

No changes to `forward()` or `reverse()`.

---

## 2. `_AddressSearchField` Widget

Replace the existing `_FormField(label: 'Address *', controller: _address)` in `_PitchFormDialogState.build()` with a new stateful widget `_AddressSearchField`.

File: inline in `manage_panel_screen.dart` (not a separate file — it's only used once).

### State

```dart
List<AddressSuggestion> _suggestions = [];
Timer? _debounce;
final OverlayPortalController _overlayCtrl = OverlayPortalController();
```

### Behaviour

- `TextEditingController` listener fires on every change
- Cancels and restarts a 400ms `Timer` on each keystroke (debounce)
- When timer fires: calls `GeocodingService.suggest(value)`, stores results, shows overlay if non-empty
- Minimum 3 characters before any network call
- On suggestion tap:
  1. Set `_address.text = suggestion.displayName`
  2. Call `_onPinPlaced(suggestion.latLng)` (already exists — moves pin + reverse-geocodes city)
  3. Clear `_suggestions`, dismiss overlay
- Overlay dismissed also when: field loses focus, text is cleared (< 3 chars), or a suggestion is selected

### Overlay

Use `OverlayPortal` (available in Flutter 3.7+) anchored below the address field. The overlay is a `Material` card:

```
┌─────────────────────────────────────┐
│ 📍 Agrabad Commercial Area, Chitt…  │
│ 📍 Agrabad, Chittagong Division…    │
│ 📍 Agrabad C/A Road, Bangladesh     │
└─────────────────────────────────────┘
```

Styling:
- Background: `Color(0xFF0A1F1A)` (same as the dialog)
- Border: `AppColors.primaryDeep`
- Border radius: 8px
- Each row: `Icons.location_on` (13px, `AppColors.primary`) + `displayName` text in `GoogleFonts.dmSans` 13px `AppColors.textPrimary`, truncated with ellipsis
- Row height: 40px, `InkWell` highlight color `AppColors.primaryDeep` at 30% opacity
- Max visible rows: 5 (no scroll needed)

### Loading state

While `suggest()` is in-flight, show a single row with a `SizedBox(width:14, height:14, child: CircularProgressIndicator(strokeWidth:1.5, color: AppColors.primary))` centred. Replace with results when they arrive.

---

## 3. What Stays the Same

- "Locate on map" button remains — useful when the manager wants to type a full address and geocode it in one shot rather than using the dropdown
- `_onPinPlaced(LatLng)` — unchanged, handles reverse geocode to fill city field
- Map tap-to-pin — unchanged
- All other form fields — unchanged

---

## Files Changed

| File | Change |
|---|---|
| `lib/data/services/geocoding_service.dart` | Add `suggest()` method and `AddressSuggestion` typedef |
| `lib/presentation/screens/manage/manage_panel_screen.dart` | Replace address `_FormField` with `_AddressSearchField` widget |

---

## Non-Goals

- No Google Places integration
- No autocomplete on the city field (plain text, city list is small)
- No autocomplete in the player app map explore screen
- No caching of suggestions
