# Map-Based Turf Discovery — Design Spec

**Date:** 2026-04-12
**Status:** Approved
**Scope:** Player explore map, manager pitch onboarding with map, service radius priority sort

---

## Overview

Add a map-first discovery experience to Turfinn using OpenStreetMap via `flutter_map`. Players see turfs as pins on a dark-themed map with a draggable bottom sheet for card details. Turf managers set pitch location via address + interactive map during onboarding and configure a priority visibility radius. The backend sorts turfs by distance when the player shares their location, boosting turfs whose service radius covers the player.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Map library | `flutter_map` + OSM | Free forever, no API key, no usage limits |
| Tiles | CartoDB dark (`dark_all`) | Matches Turfinn's #030F0F theme |
| Geocoding | Nominatim (OSM) | Free, no key, 1 req/sec rate limit |
| GPS | `geolocator` package | Cross-platform, permission handling built-in |
| Player layout | Map-first + bottom sheet | Spatial discovery for spread-out suburban turfs |
| Manager onboarding | Address + map bidirectional | Type address to place pin, or drag pin to fill address |
| Service radius | Priority sort boost, not visibility filter | No turf ever hidden — radius means "show first" |
| Scope | Single spec, ship together | Player map, manager onboarding, backend radius — all one feature |

---

## Part 1: Player Explore Map

### First-Time Preference Sheet

On first visit to Explore (no `location_mode` in SharedPreferences), a modal bottom sheet appears:

- **Title:** "How do you want to find turfs?"
- **Option 1:** "Use my location" — icon: GPS pin — requests `geolocator` permission, saves `location_mode: nearby` + last known lat/lng
- **Option 2:** "Browse by city" — shows city pills: Chittagong, Dhaka, Sylhet, Rajshahi — saves `location_mode: city` + `preferred_city`
- Sheet is dismissible (defaults to "all turfs" if dismissed)
- Preference stored in `SharedPreferences`, persists across sessions

### Map View

Full-screen `FlutterMap` widget replacing the current `ExploreScreen` body:

- **Tile layer:** `https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png`
- **Initial center:** 
  - Nearby mode: player's GPS coordinates
  - City mode: city center (CTG: 22.3569/91.7832, Dhaka: 23.8103/90.4125, etc.)
  - No preference: Bangladesh center (23.6850/90.3563), zoom 7
- **Initial zoom:** 13 (nearby), 12 (city), 7 (no preference)
- **Turf pins:** Custom `MarkerLayer` with `Marker` widgets — each pin is a small container showing `"৳{price}"` in Turfinn green on dark background, rounded corners. Active/tapped pin gets a green glow border.
- **Pin clustering:** Not needed for MVP (10-50 turfs per city). Add later if density grows.

### Top Bar Overlay

Positioned over the map, semi-transparent dark background:

- **Left:** City/location pill — shows "Nearby" (with GPS icon) or city name. Tap opens preference sheet to switch.
- **Right:** Radius filter pill — only visible in nearby mode. Tap cycles: 3km → 5km → 10km → 25km → All (no radius filter, shows every turf sorted by distance). Filters the visible pins on the map and the cards in the bottom sheet. Default is "All".

### Bottom Sheet

`DraggableScrollableSheet` layered over the map:

- **Collapsed (30% height):** Handle bar + horizontal `ListView` of 2-3 nearest `TurfCard` widgets. Cards are the existing `TurfCard` from `home_screen.dart`, reused.
- **Expanded (100%):** Vertical scrollable list of all turf cards, with search bar at top (reuses existing search flow). City filter chips shown in city mode.
- **Minimized (~8%):** Just the handle bar, full map visible.
- **Pin ↔ Sheet interaction:** Tapping a map pin scrolls the bottom sheet to that turf's card and highlights it. Tapping a card in the sheet centers the map on that turf's pin.

### Navigation

- Tapping a turf card (in sheet) → navigates to `/pitches/:id` (existing turf detail/booking screen)
- Explore tab in bottom nav → shows the map screen
- Search icon in top bar → pushes `/search` screen, returns search term, filters pins + cards

### Data Flow

```
ExploreScreen (StatefulWidget)
  ├── reads location_mode from SharedPreferences
  ├── if nearby: gets GPS via geolocator → passes lat/lng to provider
  ├── ref.watch(pitchListProvider(lat:, lng:, radius:, city:, search:))
  │     └── PitchRemoteSource.listPitches() → GET /pitches?lat=&lng=&radius=&city=&search=
  ├── FlutterMap (tile layer + marker layer from pitch list)
  ├── TopBarOverlay (city pill + radius pill)
  └── DraggableScrollableSheet (TurfCard list)
```

---

## Part 2: Manager Pitch Onboarding

### Enhanced `_PitchFormDialog`

The existing pitch create/edit dialog in `manage_panel_screen.dart` gets a map section between the address row and the price row:

**Address + City row (existing):** Text fields remain. City defaults to manager's city or "Chittagong".

**New: "Locate on map" button** — next to address field. On tap:
1. Geocodes the address+city text via Nominatim → gets lat/lng
2. Drops pin on the mini-map below
3. If geocoding fails, shows inline error "Could not find this address — place the pin manually"

**New: Inline map widget** — 200px tall `FlutterMap` embedded in the form:
- Same dark tiles as player map
- Single draggable `Marker` pin (green Turfinn pin)
- On pin drag end → reverse geocode via Nominatim → auto-update address + city fields
- On address field "Locate" tap → forward geocode → move pin
- Shows crosshair hint text "Drag pin to exact location" until pin is placed

**New: Service radius dropdown** — below the map:
- Label: "Priority visibility radius"
- Options: 3 km, 5 km, 10 km, 25 km, City-wide (default)
- Helper text: "Players within this radius see your turf first"
- Stored as `service_radius_km` on the pitch

**Lat/lng fields** — hidden from UI, populated by the map pin. Sent in `UpsertPitchRequest` as existing `latitude`/`longitude` fields.

### Geocoding Service

New file: `lib/data/services/geocoding_service.dart`

```dart
class GeocodingService {
  // Forward: address string → LatLng
  Future<LatLng?> forward(String address);
  
  // Reverse: LatLng → address components (address, city)
  Future<({String address, String city})?> reverse(LatLng point);
}
```

- Uses Nominatim API via Dio
- 1 request/sec rate limit enforced with debounce
- User-Agent header set to `Turfinn/1.0` (Nominatim requires this)

---

## Part 3: Backend — Nearby Sort + Radius Priority

### New Migration (021)

```sql
ALTER TABLE pitches ADD COLUMN IF NOT EXISTS service_radius_km FLOAT;
```

### Entity Change

`backend/internal/domain/entity/pitch.go` — add:
```go
ServiceRadiusKM *float64 `gorm:"column:service_radius_km"`
```

### DTO Change

`backend/internal/interfaces/dto/pitch_dto.go`:
- `UpsertPitchRequest`: add `ServiceRadiusKM *float64 json:"service_radius_km"`
- `ListPitchesQuery`: add `Lat float64 query:"lat"` and `Lng float64 query:"lng"` and `Radius float64 query:"radius"`
- `PitchResponse`: add `ServiceRadiusKM *float64 json:"service_radius_km"` and `DistanceKM *float64 json:"distance_km,omitempty"`

### Repository Change

`backend/internal/infrastructure/repository/pitch_repository.go` — `List` method:

When `filter.Lat != 0 && filter.Lng != 0`:
- Use Haversine SQL to compute `distance_km` as a computed column
- If `filter.Radius > 0`, add `WHERE distance_km <= ?` clause
- Sort by: turfs where `distance_km <= service_radius_km` first (boost), then by `distance_km ASC`

When lat/lng not provided:
- Current behavior unchanged — filter by city, default sort

**Haversine SQL (no extensions needed):**
```sql
(6371 * acos(
  cos(radians(?)) * cos(radians(latitude)) 
  * cos(radians(longitude) - radians(?)) 
  + sin(radians(?)) * sin(radians(latitude))
)) AS distance_km
```

### Handler Change

`pitch_handler.go` `List` method — pass `Lat`, `Lng`, `Radius` from query to `PitchFilter`.

### Manage Handler Change

`manage_handler.go` — pass `ServiceRadiusKM` from `UpsertPitchRequest` to pitch entity on create/update.

---

## Part 4: Packages

Add to `pubspec.yaml`:
```yaml
flutter_map: ^7.0.0
latlong2: ^0.9.0
geolocator: ^12.0.0
```

No new backend dependencies.

### Tile URL (no API key)
```
https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png
```

### Nominatim URLs (no API key)
```
Forward: https://nominatim.openstreetmap.org/search?q={query}&format=json&countrycodes=bd
Reverse: https://nominatim.openstreetmap.org/reverse?lat={lat}&lon={lng}&format=json
```

---

## Files Changed

### New Files
| File | Purpose |
|------|---------|
| `lib/data/services/geocoding_service.dart` | Nominatim forward/reverse geocoding |
| `lib/presentation/screens/explore/map_explore_screen.dart` | Map-first explore with bottom sheet |
| `lib/presentation/screens/explore/widgets/turf_pin.dart` | Custom map pin widget |
| `lib/presentation/screens/explore/widgets/preference_sheet.dart` | First-time location preference |
| `lib/presentation/screens/explore/widgets/map_top_bar.dart` | City pill + radius filter overlay |
| `backend/migrations/021_pitch_service_radius.sql` | Add service_radius_km column |

### Modified Files
| File | Change |
|------|--------|
| `pubspec.yaml` | Add flutter_map, latlong2, geolocator |
| `lib/presentation/screens/explore/explore_screen.dart` | Replace with map-based layout |
| `lib/data/sources/remote/pitch_remote_source.dart` | Add lat/lng/radius params to listPitches |
| `lib/presentation/providers/pitch_provider.dart` | Add lat/lng/radius params to pitchListProvider |
| `lib/presentation/screens/manage/manage_panel_screen.dart` | Add map + radius to _PitchFormDialog |
| `backend/internal/domain/entity/pitch.go` | Add ServiceRadiusKM field |
| `backend/internal/domain/repository/pitch_repository.go` | Add Lat/Lng/Radius to PitchFilter |
| `backend/internal/infrastructure/repository/pitch_repository.go` | Haversine distance query |
| `backend/internal/interfaces/dto/pitch_dto.go` | Add fields to query/request/response DTOs |
| `backend/internal/interfaces/http/handler/pitch_handler.go` | Pass lat/lng/radius to filter |
| `backend/internal/interfaces/http/handler/manage_handler.go` | Pass service_radius_km on create/update |

---

## Out of Scope

- Pin clustering (not needed at current scale)
- Offline tile caching (future optimization)
- Turn-by-turn navigation to turf
- Satellite/terrain map styles
- Manager analytics on radius performance
