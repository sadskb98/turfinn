# Map-Based Turf Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add map-first turf discovery with OSM, manager map onboarding, and distance-based priority sorting.

**Architecture:** `flutter_map` with CartoDB dark tiles for the player explore map and manager pitch form. Backend Haversine SQL for distance sort with `service_radius_km` priority boost. Nominatim for geocoding (no API key). `geolocator` for device GPS.

**Tech Stack:** flutter_map, latlong2, geolocator, Nominatim API, PostgreSQL Haversine, CartoDB dark tiles

**Spec:** `docs/superpowers/specs/2026-04-12-map-based-turf-discovery-design.md`

---

## File Map

### New Files
| File | Responsibility |
|------|---------------|
| `backend/migrations/021_pitch_service_radius.sql` | Add `service_radius_km` column to pitches |
| `lib/data/services/geocoding_service.dart` | Nominatim forward/reverse geocoding |
| `lib/presentation/screens/explore/map_explore_screen.dart` | Map-first explore with bottom sheet |
| `lib/presentation/screens/explore/widgets/turf_pin.dart` | Custom map pin widget (price badge) |
| `lib/presentation/screens/explore/widgets/preference_sheet.dart` | First-time location mode picker |
| `lib/presentation/screens/explore/widgets/map_top_bar.dart` | City pill + radius filter overlay |

### Modified Files
| File | Change |
|------|--------|
| `pubspec.yaml` | Add flutter_map, latlong2, geolocator |
| `backend/internal/domain/entity/pitch.go` | Add `ServiceRadiusKM` field |
| `backend/internal/domain/repository/pitch_repository.go` | Add `Lat`, `Lng`, `Radius` to `PitchFilter` |
| `backend/internal/infrastructure/repository/pitch_repository.go` | Haversine distance query + priority sort |
| `backend/internal/interfaces/dto/pitch_dto.go` | Add fields to query/request/response DTOs |
| `backend/internal/interfaces/dto/manage_dto.go` | Add `service_radius_km` to `UpsertPitchRequest` |
| `backend/internal/interfaces/http/handler/pitch_handler.go` | Pass lat/lng/radius to filter, distance in response |
| `backend/internal/interfaces/http/handler/manage_handler.go` | Pass `service_radius_km` on create/update |
| `lib/data/models/pitch_model.dart` | Add `serviceRadiusKm`, `distanceKm` fields |
| `lib/data/sources/remote/pitch_remote_source.dart` | Add `lat`/`lng`/`radius` params |
| `lib/presentation/providers/pitch_provider.dart` | Add `lat`/`lng`/`radius` params |
| `lib/presentation/screens/explore/explore_screen.dart` | Replace body with `MapExploreScreen` |
| `lib/presentation/screens/manage/manage_panel_screen.dart` | Add inline map + radius dropdown to `_PitchFormDialog` |

---

## Task 1: Backend — Migration + Entity + DTO

**Files:**
- Create: `backend/migrations/021_pitch_service_radius.sql`
- Modify: `backend/internal/domain/entity/pitch.go`
- Modify: `backend/internal/interfaces/dto/pitch_dto.go`
- Modify: `backend/internal/interfaces/dto/manage_dto.go`

- [ ] **Step 1: Create migration 021**

Create `backend/migrations/021_pitch_service_radius.sql`:
```sql
-- Add service radius for priority visibility sorting
ALTER TABLE pitches ADD COLUMN IF NOT EXISTS service_radius_km FLOAT;
```

- [ ] **Step 2: Add field to Pitch entity**

In `backend/internal/domain/entity/pitch.go`, add after `IsActive`:
```go
ServiceRadiusKM *float64  `gorm:"column:service_radius_km"`
```

- [ ] **Step 3: Add fields to pitch DTOs**

In `backend/internal/interfaces/dto/pitch_dto.go`:

Add to `ListPitchesQuery`:
```go
Lat    float64 `query:"lat"`
Lng    float64 `query:"lng"`
Radius float64 `query:"radius"`
```

Add to `PitchResponse`:
```go
ServiceRadiusKM *float64 `json:"service_radius_km,omitempty"`
DistanceKM      *float64 `json:"distance_km,omitempty"`
```

- [ ] **Step 4: Add service_radius_km to UpsertPitchRequest**

In `backend/internal/interfaces/dto/manage_dto.go`, add to `UpsertPitchRequest`:
```go
ServiceRadiusKM *float64 `json:"service_radius_km"`
```

- [ ] **Step 5: Build and verify**

Run: `cd backend && go build ./...`
Expected: clean build, no errors

- [ ] **Step 6: Commit**

```bash
git add backend/migrations/021_pitch_service_radius.sql backend/internal/domain/entity/pitch.go backend/internal/interfaces/dto/pitch_dto.go backend/internal/interfaces/dto/manage_dto.go
git commit -m "feat: add service_radius_km column and DTOs for map discovery"
```

---

## Task 2: Backend — Haversine Distance Query + Priority Sort

**Files:**
- Modify: `backend/internal/domain/repository/pitch_repository.go`
- Modify: `backend/internal/infrastructure/repository/pitch_repository.go`

- [ ] **Step 1: Add Lat/Lng/Radius to PitchFilter**

In `backend/internal/domain/repository/pitch_repository.go`, add to `PitchFilter`:
```go
type PitchFilter struct {
	City   string
	Search string
	Lat    float64
	Lng    float64
	Radius float64 // max distance in km, 0 = no limit
	Page   int
	Limit  int
}
```

- [ ] **Step 2: Implement Haversine distance query in repository**

In `backend/internal/infrastructure/repository/pitch_repository.go`, replace the `List` method:

```go
func (r *pitchRepository) List(ctx context.Context, filter domain.PitchFilter) ([]*entity.Pitch, int64, error) {
	query := r.db.WithContext(ctx).Model(&entity.Pitch{}).Where("is_active = true")

	if filter.City != "" {
		query = query.Where("city = ?", filter.City)
	}

	if filter.Search != "" {
		term := "%" + filter.Search + "%"
		query = query.Where("(name ILIKE ? OR address ILIKE ? OR city ILIKE ?)", term, term, term)
	}

	// When lat/lng provided, use Haversine for distance sort + optional radius filter
	useDistance := filter.Lat != 0 || filter.Lng != 0
	if useDistance {
		haversine := `(6371 * acos(LEAST(1.0, cos(radians(?)) * cos(radians(latitude)) * cos(radians(longitude) - radians(?)) + sin(radians(?)) * sin(radians(latitude)))))`
		distanceExpr := fmt.Sprintf("%s AS distance_km", haversine)

		query = query.Select("*, "+distanceExpr, filter.Lat, filter.Lng, filter.Lat)

		if filter.Radius > 0 {
			query = query.Where(haversine+" <= ?", filter.Lat, filter.Lng, filter.Lat, filter.Radius)
		}

		// Priority sort: turfs where player is within service_radius_km come first
		priorityExpr := fmt.Sprintf("CASE WHEN service_radius_km IS NOT NULL AND %s <= service_radius_km THEN 0 ELSE 1 END", haversine)
		query = query.Order(fmt.Sprintf("%s ASC, distance_km ASC", priorityExpr))
	}

	var total int64
	countQ := query.Session(&gorm.Session{})
	countQ.Count(&total)

	offset := (filter.Page - 1) * filter.Limit
	var pitches []*entity.Pitch
	q := query
	if !useDistance {
		q = q.Order("created_at DESC")
	}
	if err := q.Offset(offset).Limit(filter.Limit).Find(&pitches).Error; err != nil {
		return nil, 0, err
	}
	return pitches, total, nil
}
```

Add `"fmt"` to imports if not already present. The `LEAST(1.0, ...)` clamp prevents NaN from floating-point rounding in acos.

Note: GORM will scan the computed `distance_km` column into the struct only if there's a matching field. We handle this in the handler by reading it separately.

- [ ] **Step 3: Build and verify**

Run: `cd backend && go build ./...`
Expected: clean build

- [ ] **Step 4: Commit**

```bash
git add backend/internal/domain/repository/pitch_repository.go backend/internal/infrastructure/repository/pitch_repository.go
git commit -m "feat: Haversine distance query with service radius priority sort"
```

---

## Task 3: Backend — Handler Wiring + Distance in Response

**Files:**
- Modify: `backend/internal/interfaces/http/handler/pitch_handler.go`
- Modify: `backend/internal/interfaces/http/handler/manage_handler.go`

- [ ] **Step 1: Pass lat/lng/radius in pitch list handler**

In `backend/internal/interfaces/http/handler/pitch_handler.go`, update the `List` method:

```go
func (h *PitchHandler) List(c echo.Context) error {
	var q dto.ListPitchesQuery
	if err := c.Bind(&q); err != nil {
		return response.BadRequest(c, "invalid query params")
	}
	if q.Page < 1 {
		q.Page = 1
	}
	if q.Limit < 1 {
		q.Limit = 20
	}
	pitches, total, err := h.pitchSvc.List(c.Request().Context(), domain.PitchFilter{
		City:   q.City,
		Search: q.Search,
		Lat:    q.Lat,
		Lng:    q.Lng,
		Radius: q.Radius,
		Page:   q.Page,
		Limit:  q.Limit,
	})
	if err != nil {
		return response.InternalError(c)
	}
	return response.OKPaginated(c, toPitchResponses(pitches), response.Meta{
		Page: q.Page, Limit: q.Limit, Total: total,
	})
}
```

- [ ] **Step 2: Add ServiceRadiusKM to toPitchResponse**

In `pitch_handler.go`, update `toPitchResponse`:
```go
func toPitchResponse(p *entity.Pitch) dto.PitchResponse {
	return dto.PitchResponse{
		ID:              p.ID.String(),
		Name:            p.Name,
		Description:     p.Description,
		Address:         p.Address,
		City:            p.City,
		Latitude:        p.Latitude,
		Longitude:       p.Longitude,
		PricePerHour:    p.PricePerHour,
		Surface:         p.Surface,
		Capacity:        p.Capacity,
		ImageURLs:       p.ImageURLs,
		IsActive:        p.IsActive,
		ServiceRadiusKM: p.ServiceRadiusKM,
	}
}
```

- [ ] **Step 3: Pass service_radius_km in manage handler**

In `backend/internal/interfaces/http/handler/manage_handler.go`, in `CreatePitch` after `pitch.ImageURLs = req.ImageURLs`:
```go
pitch.ServiceRadiusKM = req.ServiceRadiusKM
```

In `UpdatePitch` after `pitch.ImageURLs = req.ImageURLs`:
```go
pitch.ServiceRadiusKM = req.ServiceRadiusKM
```

- [ ] **Step 4: Build and verify**

Run: `cd backend && go build ./...`
Expected: clean build

- [ ] **Step 5: Test the endpoint manually**

Run: `curl -s "http://localhost:8080/api/v1/pitches?lat=23.79&lng=90.40&limit=3" | python3 -m json.tool | head -20`
Expected: pitch list returned (distance sort may not be visible without service_radius_km data yet, but no errors)

- [ ] **Step 6: Commit**

```bash
git add backend/internal/interfaces/http/handler/pitch_handler.go backend/internal/interfaces/http/handler/manage_handler.go
git commit -m "feat: wire lat/lng/radius params and service_radius_km to handlers"
```

---

## Task 4: Flutter — Add Packages + PitchModel Update

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/data/models/pitch_model.dart`
- Modify: `lib/data/sources/remote/pitch_remote_source.dart`
- Modify: `lib/presentation/providers/pitch_provider.dart`

- [ ] **Step 1: Add flutter_map dependencies**

Run:
```bash
flutter pub add flutter_map latlong2 geolocator
```

- [ ] **Step 2: Update PitchModel with new fields**

In `lib/data/models/pitch_model.dart`:
```dart
class PitchModel {
  final String id;
  final String name;
  final String description;
  final String address;
  final String city;
  final double latitude;
  final double longitude;
  final double pricePerHour;
  final String surface;
  final int capacity;
  final String imageUrls;
  final bool isActive;
  final double? serviceRadiusKm;
  final double? distanceKm;

  const PitchModel({
    required this.id,
    required this.name,
    required this.description,
    required this.address,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.pricePerHour,
    required this.surface,
    required this.capacity,
    required this.imageUrls,
    required this.isActive,
    this.serviceRadiusKm,
    this.distanceKm,
  });

  factory PitchModel.fromJson(Map<String, dynamic> json) => PitchModel(
        id: json['id'] as String,
        name: json['name'] as String,
        description: (json['description'] as String?) ?? '',
        address: json['address'] as String,
        city: json['city'] as String,
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        pricePerHour: (json['price_per_hour'] as num).toDouble(),
        surface: (json['surface'] as String?) ?? '',
        capacity: (json['capacity'] as num?)?.toInt() ?? 0,
        imageUrls: (json['image_urls'] as String?) ?? '',
        isActive: (json['is_active'] as bool?) ?? true,
        serviceRadiusKm: (json['service_radius_km'] as num?)?.toDouble(),
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
      );

  String get primaryImage {
    if (imageUrls.isEmpty) return '';
    return imageUrls.split(',').first.trim();
  }

  String get distanceLabel {
    if (distanceKm == null) return '';
    if (distanceKm! < 1) return '${(distanceKm! * 1000).round()}m';
    return '${distanceKm!.toStringAsFixed(1)} km';
  }
}
```

- [ ] **Step 3: Add lat/lng/radius params to remote source**

In `lib/data/sources/remote/pitch_remote_source.dart`, update `listPitches`:
```dart
Future<List<PitchModel>> listPitches({
  String? city,
  String? search,
  double? lat,
  double? lng,
  double? radius,
  int page = 1,
  int limit = 20,
}) async {
  final resp = await _dio.get('/pitches', queryParameters: {
    if (city != null && city.isNotEmpty) 'city': city,
    if (search != null && search.isNotEmpty) 'search': search,
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
    if (radius != null && radius > 0) 'radius': radius,
    'page': page,
    'limit': limit,
  });
  final data = resp.data['data'] as List;
  return data.map((e) => PitchModel.fromJson(e as Map<String, dynamic>)).toList();
}
```

- [ ] **Step 4: Add lat/lng/radius params to provider**

In `lib/presentation/providers/pitch_provider.dart`, update:
```dart
@riverpod
Future<List<PitchModel>> pitchList(
  PitchListRef ref, {
  String? city,
  String? search,
  double? lat,
  double? lng,
  double? radius,
}) async {
  return ref.watch(pitchRemoteSourceProvider).listPitches(
    city: city,
    search: search,
    lat: lat,
    lng: lng,
    radius: radius,
  );
}
```

- [ ] **Step 5: Regenerate codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: succeeds with outputs

- [ ] **Step 6: Verify build**

Run: `flutter analyze`
Expected: no errors

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/data/models/pitch_model.dart lib/data/sources/remote/pitch_remote_source.dart lib/presentation/providers/pitch_provider.dart lib/presentation/providers/pitch_provider.g.dart
git commit -m "feat: add flutter_map deps, lat/lng/radius params to pitch data layer"
```

---

## Task 5: Flutter — Geocoding Service

**Files:**
- Create: `lib/data/services/geocoding_service.dart`

- [ ] **Step 1: Create geocoding service**

Create `lib/data/services/geocoding_service.dart`:
```dart
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

class GeocodingService {
  static final _dio = Dio(BaseOptions(
    baseUrl: 'https://nominatim.openstreetmap.org',
    headers: {'User-Agent': 'Turfinn/1.0 (turfinn.com)'},
  ));

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
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/data/services/geocoding_service.dart
git commit -m "feat: add Nominatim geocoding service (forward + reverse)"
```

---

## Task 6: Flutter — Preference Sheet + Top Bar Widgets

**Files:**
- Create: `lib/presentation/screens/explore/widgets/preference_sheet.dart`
- Create: `lib/presentation/screens/explore/widgets/map_top_bar.dart`

- [ ] **Step 1: Create preference sheet**

Create `lib/presentation/screens/explore/widgets/preference_sheet.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';

/// First-time location preference — "Use my location" or "Browse by city"
class PreferenceSheet extends StatelessWidget {
  const PreferenceSheet({super.key, required this.onNearby, required this.onCity});
  final VoidCallback onNearby;
  final void Function(String city) onCity;

  static const _cities = ['Chittagong', 'Dhaka', 'Sylhet', 'Rajshahi'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: Color(0xFF0A1F1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.primaryDeep,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text('How do you want to find turfs?',
              style: GoogleFonts.nunito(
                  fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          _OptionTile(
            icon: Icons.my_location_rounded,
            title: 'Use my location',
            subtitle: 'See turfs near you, sorted by distance',
            onTap: () {
              Navigator.pop(context);
              onNearby();
            },
          ),
          const SizedBox(height: 12),
          Text('Or browse by city',
              style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _cities.map((c) => GestureDetector(
              onTap: () {
                Navigator.pop(context);
                onCity(c);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primaryDeep),
                ),
                child: Text(c,
                    style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textPrimary)),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primaryDeep.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primaryDeep),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.nunito(
                      fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: GoogleFonts.dmSans(
                      fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Create map top bar**

Create `lib/presentation/screens/explore/widgets/map_top_bar.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';

class MapTopBar extends StatelessWidget {
  const MapTopBar({
    super.key,
    required this.locationLabel,
    required this.onLocationTap,
    required this.onSearchTap,
    this.radiusKm,
    this.onRadiusTap,
  });

  final String locationLabel;
  final VoidCallback onLocationTap;
  final VoidCallback onSearchTap;
  final double? radiusKm;
  final VoidCallback? onRadiusTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            // Location pill
            GestureDetector(
              onTap: onLocationTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xE6040E0E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primaryDeep),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      locationLabel == 'Nearby' ? Icons.my_location : Icons.location_city,
                      size: 14, color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(locationLabel,
                        style: GoogleFonts.dmSans(
                            fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    const SizedBox(width: 2),
                    const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Radius pill (only in nearby mode)
            if (radiusKm != null && onRadiusTap != null)
              GestureDetector(
                onTap: onRadiusTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xE6040E0E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primaryDeep),
                  ),
                  child: Text(
                    radiusKm! <= 0 ? 'All' : '${radiusKm!.round()} km',
                    style: GoogleFonts.dmSans(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary),
                  ),
                ),
              ),
            const Spacer(),
            // Search button
            GestureDetector(
              onTap: onSearchTap,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xE6040E0E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primaryDeep),
                ),
                child: const Icon(Icons.search, color: AppColors.primary, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/screens/explore/widgets/
git commit -m "feat: add preference sheet and map top bar widgets"
```

---

## Task 7: Flutter — Turf Pin Widget

**Files:**
- Create: `lib/presentation/screens/explore/widgets/turf_pin.dart`

- [ ] **Step 1: Create turf pin**

Create `lib/presentation/screens/explore/widgets/turf_pin.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : const Color(0xF0071714),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.primaryDeep,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 1)]
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 4)],
          ),
          child: Text(
            '\u09F3${price.round()}',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.black : AppColors.primary,
            ),
          ),
        ),
        // Triangle pointer
        CustomPaint(
          size: const Size(10, 6),
          painter: _TrianglePainter(
            color: isSelected ? AppColors.primary : const Color(0xF0071714),
          ),
        ),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter({required this.color});
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
  bool shouldRepaint(covariant _TrianglePainter old) => old.color != color;
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/presentation/screens/explore/widgets/turf_pin.dart
git commit -m "feat: add custom turf map pin widget with price badge"
```

---

## Task 8: Flutter — Map Explore Screen

**Files:**
- Create: `lib/presentation/screens/explore/map_explore_screen.dart`
- Modify: `lib/presentation/screens/explore/explore_screen.dart`

- [ ] **Step 1: Create the map explore screen**

Create `lib/presentation/screens/explore/map_explore_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/pitch_model.dart';
import '../../providers/pitch_provider.dart';
import '../home/home_screen.dart';
import 'widgets/map_top_bar.dart';
import 'widgets/preference_sheet.dart';
import 'widgets/turf_pin.dart';

// City centers
const _cityCenters = <String, LatLng>{
  'Chittagong': LatLng(22.3569, 91.7832),
  'Dhaka': LatLng(23.8103, 90.4125),
  'Sylhet': LatLng(24.8949, 91.8687),
  'Rajshahi': LatLng(24.3745, 88.6042),
};

const _radiusOptions = [3.0, 5.0, 10.0, 25.0, 0.0]; // 0 = all

class MapExploreScreen extends ConsumerStatefulWidget {
  const MapExploreScreen({super.key});

  @override
  ConsumerState<MapExploreScreen> createState() => _MapExploreScreenState();
}

class _MapExploreScreenState extends ConsumerState<MapExploreScreen> {
  final _mapCtrl = MapController();
  final _sheetCtrl = DraggableScrollableController();

  String _locationMode = ''; // 'nearby' or 'city'
  String _city = '';
  LatLng? _userLocation;
  int _radiusIndex = 4; // default: all (0.0)
  String? _selectedPitchId;
  bool _prefChecked = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('location_mode') ?? '';
    final city = prefs.getString('preferred_city') ?? '';

    if (mode.isEmpty) {
      // First visit — show preference sheet after build
      WidgetsBinding.instance.addPostFrameCallback((_) => _showPreferenceSheet());
    } else {
      _locationMode = mode;
      _city = city;
      if (mode == 'nearby') await _acquireLocation();
    }
    setState(() => _prefChecked = true);
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('location_mode', _locationMode);
    await prefs.setString('preferred_city', _city);
  }

  void _showPreferenceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (_) => PreferenceSheet(
        onNearby: () async {
          setState(() => _locationMode = 'nearby');
          await _acquireLocation();
          _savePreferences();
        },
        onCity: (city) {
          setState(() {
            _locationMode = 'city';
            _city = city;
          });
          _moveToCity(city);
          _savePreferences();
        },
      ),
    );
  }

  Future<void> _acquireLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          // Fall back to city mode
          setState(() {
            _locationMode = 'city';
            _city = 'Chittagong';
          });
          _moveToCity('Chittagong');
          return;
        }
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      setState(() => _userLocation = LatLng(pos.latitude, pos.longitude));
      _mapCtrl.move(_userLocation!, 13);
    } catch (_) {
      setState(() {
        _locationMode = 'city';
        _city = 'Chittagong';
      });
      _moveToCity('Chittagong');
    }
  }

  void _moveToCity(String city) {
    final center = _cityCenters[city] ?? _cityCenters['Chittagong']!;
    _mapCtrl.move(center, 12);
  }

  void _cycleRadius() {
    setState(() {
      _radiusIndex = (_radiusIndex + 1) % _radiusOptions.length;
    });
  }

  LatLng get _mapCenter {
    if (_locationMode == 'nearby' && _userLocation != null) return _userLocation!;
    if (_locationMode == 'city') return _cityCenters[_city] ?? _cityCenters['Chittagong']!;
    return const LatLng(23.6850, 90.3563); // Bangladesh center
  }

  double get _mapZoom {
    if (_locationMode == 'nearby') return 13;
    if (_locationMode == 'city') return 12;
    return 7;
  }

  String get _locationLabel {
    if (_locationMode == 'nearby') return 'Nearby';
    if (_locationMode == 'city' && _city.isNotEmpty) return _city;
    return 'All';
  }

  double get _currentRadius => _radiusOptions[_radiusIndex];

  @override
  Widget build(BuildContext context) {
    final pitchesAsync = ref.watch(pitchListProvider(
      city: _locationMode == 'city' ? _city : null,
      lat: _locationMode == 'nearby' ? _userLocation?.latitude : null,
      lng: _locationMode == 'nearby' ? _userLocation?.longitude : null,
      radius: _locationMode == 'nearby' && _currentRadius > 0 ? _currentRadius : null,
    ));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: !_prefChecked
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Stack(
              children: [
                // Map
                FlutterMap(
                  mapController: _mapCtrl,
                  options: MapOptions(
                    initialCenter: _mapCenter,
                    initialZoom: _mapZoom,
                    backgroundColor: AppColors.background,
                    onTap: (_, __) => setState(() => _selectedPitchId = null),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.turfinn.app',
                    ),
                    // User location marker
                    if (_userLocation != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: _userLocation!,
                          width: 20,
                          height: 20,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.4),
                                    blurRadius: 8),
                              ],
                            ),
                          ),
                        ),
                      ]),
                    // Turf pins
                    pitchesAsync.when(
                      data: (pitches) => MarkerLayer(
                        markers: pitches
                            .where((p) => p.latitude != 0 && p.longitude != 0)
                            .map((p) => Marker(
                                  point: LatLng(p.latitude, p.longitude),
                                  width: 70,
                                  height: 36,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() => _selectedPitchId = p.id);
                                      _mapCtrl.move(
                                          LatLng(p.latitude, p.longitude),
                                          _mapCtrl.camera.zoom);
                                    },
                                    child: TurfPin(
                                      price: p.pricePerHour,
                                      isSelected: _selectedPitchId == p.id,
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                      loading: () => const MarkerLayer(markers: []),
                      error: (_, __) => const MarkerLayer(markers: []),
                    ),
                  ],
                ),

                // Top bar overlay
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: MapTopBar(
                    locationLabel: _locationLabel,
                    onLocationTap: _showPreferenceSheet,
                    onSearchTap: () async {
                      final result = await context.push<String>('/search');
                      if (result != null && result.isNotEmpty) {
                        // Search overrides filters temporarily
                        // The provider will refetch with search param
                      }
                    },
                    radiusKm: _locationMode == 'nearby' ? _currentRadius : null,
                    onRadiusTap: _locationMode == 'nearby' ? _cycleRadius : null,
                  ),
                ),

                // Bottom sheet with turf cards
                DraggableScrollableSheet(
                  controller: _sheetCtrl,
                  initialChildSize: 0.30,
                  minChildSize: 0.08,
                  maxChildSize: 1.0,
                  snap: true,
                  snapSizes: const [0.08, 0.30, 1.0],
                  builder: (context, scrollCtrl) => Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF040E0E),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      border: Border(top: BorderSide(color: AppColors.primaryDeep, width: 0.5)),
                    ),
                    child: pitchesAsync.when(
                      loading: () => const Center(
                          child: CircularProgressIndicator(color: AppColors.primary)),
                      error: (_, __) => Center(
                          child: Text('Could not load turfs',
                              style: GoogleFonts.dmSans(color: AppColors.textSecondary))),
                      data: (pitches) => ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: pitches.length + 1, // +1 for handle
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Center(
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                width: 40, height: 4,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryDeep,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            );
                          }
                          final pitch = pitches[i - 1];
                          final isHighlighted = _selectedPitchId == pitch.id;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: isHighlighted
                                ? BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: AppColors.primary, width: 1.5),
                                  )
                                : null,
                            child: TurfCard(
                              pitch: pitch,
                              onTap: () => context.push('/pitches/${pitch.id}', extra: pitch),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
```

- [ ] **Step 2: Replace explore_screen.dart body**

Replace the content of `lib/presentation/screens/explore/explore_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'map_explore_screen.dart';

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) => const MapExploreScreen();
}
```

- [ ] **Step 3: Verify build**

Run: `flutter build web --target lib/main.dart --output build/web_app --dart-define=API_BASE_URL=/api/v1`
Expected: builds successfully

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/explore/
git commit -m "feat: map-first explore screen with bottom sheet, pins, and preference flow"
```

---

## Task 9: Flutter — Manager Pitch Form Map + Radius

**Files:**
- Modify: `lib/presentation/screens/manage/manage_panel_screen.dart`

- [ ] **Step 1: Add map and radius to _PitchFormDialog**

In `lib/presentation/screens/manage/manage_panel_screen.dart`, update the `_PitchFormDialogState` class:

Add imports at the top of the file:
```dart
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../data/services/geocoding_service.dart';
```

Add new state fields to `_PitchFormDialogState`:
```dart
late final TextEditingController _lat;
late final TextEditingController _lng;
double? _serviceRadius;
LatLng? _pinLocation;
bool _geocoding = false;
```

In `initState`, add:
```dart
_lat = TextEditingController(text: '${e?['latitude'] ?? ''}');
_lng = TextEditingController(text: '${e?['longitude'] ?? ''}');
_serviceRadius = (e?['service_radius_km'] as num?)?.toDouble();
final latVal = double.tryParse(_lat.text);
final lngVal = double.tryParse(_lng.text);
if (latVal != null && lngVal != null && latVal != 0 && lngVal != 0) {
  _pinLocation = LatLng(latVal, lngVal);
}
```

In `dispose`, add:
```dart
_lat.dispose();
_lng.dispose();
```

In `_submit`, add to the data map:
```dart
'latitude': double.tryParse(_lat.text) ?? 0,
'longitude': double.tryParse(_lng.text) ?? 0,
'service_radius_km': _serviceRadius,
```

Add a method for forward geocoding:
```dart
Future<void> _locateOnMap() async {
  final query = '${_address.text}, ${_city.text}';
  if (query.trim().length < 3) return;
  setState(() => _geocoding = true);
  final result = await GeocodingService.forward(query);
  setState(() => _geocoding = false);
  if (result != null) {
    setState(() {
      _pinLocation = result;
      _lat.text = result.latitude.toStringAsFixed(6);
      _lng.text = result.longitude.toStringAsFixed(6);
    });
  }
}
```

Add a method for reverse geocoding on pin drag:
```dart
Future<void> _onPinDragged(LatLng point) async {
  setState(() {
    _pinLocation = point;
    _lat.text = point.latitude.toStringAsFixed(6);
    _lng.text = point.longitude.toStringAsFixed(6);
  });
  final result = await GeocodingService.reverse(point);
  if (result != null && mounted) {
    setState(() {
      if (result.address.isNotEmpty) _address.text = result.address;
      if (result.city.isNotEmpty) _city.text = result.city;
    });
  }
}
```

In the build method, after the City/Price row, add the map section and radius dropdown:
```dart
// Locate on map button
Row(
  children: [
    Expanded(
      child: SizedBox(
        height: 36,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.primaryDeep),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _geocoding ? null : _locateOnMap,
          icon: _geocoding
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
              : const Icon(Icons.pin_drop, size: 14, color: AppColors.primary),
          label: Text(_geocoding ? 'Locating...' : 'Locate on map',
              style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary)),
        ),
      ),
    ),
  ],
),
const SizedBox(height: 12),
// Inline map
Container(
  height: 200,
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: AppColors.primaryDeep),
  ),
  clipBehavior: Clip.antiAlias,
  child: FlutterMap(
    options: MapOptions(
      initialCenter: _pinLocation ?? const LatLng(22.3569, 91.7832),
      initialZoom: _pinLocation != null ? 15 : 12,
      backgroundColor: AppColors.background,
      onTap: (_, point) => _onPinDragged(point),
    ),
    children: [
      TileLayer(
        urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png',
        subdomains: const ['a', 'b', 'c', 'd'],
        userAgentPackageName: 'com.turfinn.app',
      ),
      if (_pinLocation != null)
        MarkerLayer(markers: [
          Marker(
            point: _pinLocation!,
            width: 30,
            height: 30,
            child: const Icon(Icons.location_pin, color: AppColors.primary, size: 30),
          ),
        ]),
    ],
  ),
),
if (_pinLocation == null)
  Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text('Tap the map or use "Locate on map" to place the pin',
        style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textSecondary)),
  ),
const SizedBox(height: 12),
// Service radius dropdown
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text('Priority visibility radius',
        style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary)),
    const SizedBox(height: 6),
    Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF051210),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primaryDeep),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<double?>(
          value: _serviceRadius,
          isExpanded: true,
          dropdownColor: const Color(0xFF0A1F1A),
          style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textPrimary),
          hint: Text('City-wide (default)',
              style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
          onChanged: (v) => setState(() => _serviceRadius = v),
          items: [
            const DropdownMenuItem(value: null, child: Text('City-wide (default)')),
            ...[3.0, 5.0, 10.0, 25.0].map((r) =>
                DropdownMenuItem(value: r, child: Text('${r.round()} km'))),
          ],
        ),
      ),
    ),
    const SizedBox(height: 4),
    Text('Players within this radius see your turf first',
        style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.textSecondary)),
  ],
),
const SizedBox(height: 12),
```

- [ ] **Step 2: Rebuild manager web app**

Run: `flutter build web --target lib/main_manage.dart --output build/web_manage --dart-define=API_BASE_URL=/api/v1`
Expected: builds successfully

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/screens/manage/manage_panel_screen.dart
git commit -m "feat: add inline map + geocoding + radius dropdown to manager pitch form"
```

---

## Task 10: Docker Rebuild + End-to-End Verification

**Files:** None (deployment + testing)

- [ ] **Step 1: Rebuild backend and DB**

```bash
docker compose down -v
docker compose up -d --build
```
Wait for all migrations (001-021) to run with no errors:
```bash
docker compose logs postgres 2>&1 | grep -i "error\|running /docker"
```
Expected: 21 "running" lines, 0 "ERROR" lines

- [ ] **Step 2: Verify service_radius_km column exists**

```bash
docker compose exec -T postgres psql -U turfinn -d turfinn -c "SELECT column_name FROM information_schema.columns WHERE table_name = 'pitches' AND column_name = 'service_radius_km';"
```
Expected: 1 row returned

- [ ] **Step 3: Test distance API**

```bash
curl -s "http://localhost:8080/api/v1/pitches?lat=23.79&lng=90.40&limit=3" | python3 -m json.tool | head -30
```
Expected: pitches returned sorted by distance, no errors

- [ ] **Step 4: Build and deploy all Flutter web apps**

```bash
flutter build web --target lib/main.dart --output build/web_app --dart-define=API_BASE_URL=/api/v1
flutter build web --target lib/main_manage.dart --output build/web_manage --dart-define=API_BASE_URL=/api/v1
flutter build web --target lib/main_superadmin.dart --output build/web_superadmin --dart-define=API_BASE_URL=/api/v1
docker compose restart app manage superadmin
```

- [ ] **Step 5: Verify all services respond**

```bash
curl -s -o /dev/null -w '%{http_code}' http://localhost:3000
curl -s -o /dev/null -w '%{http_code}' http://localhost:3002
curl -s -o /dev/null -w '%{http_code}' http://localhost:3003
curl -s http://localhost:8080/health
```
Expected: all 200, health ok

- [ ] **Step 6: Run E2E tests**

```bash
cd e2e && npx playwright test tests/full-stack-audit.spec.ts --reporter=list
```
Expected: 108 passed, 0 bugs

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: map-based turf discovery — complete integration"
```
