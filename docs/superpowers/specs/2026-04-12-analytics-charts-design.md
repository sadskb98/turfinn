# Analytics Charts — Design Spec
_Date: 2026-04-12_

## Overview

The turf manager panel has two analytics views (`_MyAnalyticsView` and `_AnalyticsProView`) that fetch rich data from the backend but display everything as data tables. This spec adds visual charts above the existing tables using `fl_chart`. No backend changes needed — all data is already returned by existing endpoints.

---

## 1. Package

Add to `pubspec.yaml`:
```yaml
fl_chart: ^0.69.0
```

---

## 2. Chart Widgets

Four new widgets in `lib/presentation/widgets/charts/`:

### `RevenueLineChart`
File: `lib/presentation/widgets/charts/revenue_line_chart.dart`

Input: `List<Map<String, dynamic>>` — each map has `date` (String) and `amount` (num).

Renders a `LineChart` from fl_chart:
- Line color: `AppColors.primary`
- Fill gradient: `AppColors.primary` at 30% opacity → transparent at bottom
- X axis: date labels (show every Nth label to avoid crowding, based on data length)
- Y axis: BDT amounts, formatted as `K` suffix above 1000
- Grid lines: `AppColors.primaryDeep` at 30% opacity, horizontal only
- Touch tooltip: shows date + `৳amount` on tap
- Height: 200px

### `PeakHoursBarChart`
File: `lib/presentation/widgets/charts/peak_hours_bar_chart.dart`

Input: `List<Map<String, dynamic>>` — each map has `hour` (int, 0–23) and `count` (num).

Renders a `BarChart`:
- Bars color: `AppColors.primary`
- X axis: hour labels formatted as `8am`, `9am`, etc. — show every 3rd hour to avoid crowding
- Y axis: booking count
- Highlight the tallest bar with `AppColors.primaryMid` to make peak hour obvious
- Touch tooltip: shows `HH:00 — N bookings`
- Height: 180px

### `PitchRevenueBarChart`
File: `lib/presentation/widgets/charts/pitch_revenue_bar_chart.dart`

Input: `List<Map<String, dynamic>>` — each map has `pitch_name` (String) and `revenue` (num).

Renders a horizontal `BarChart`:
- Bars color: `AppColors.primary`
- Left axis: truncated pitch names (max 14 chars)
- Right values: formatted revenue
- Touch tooltip: full pitch name + `৳revenue`
- Height: 48px per pitch (dynamic height based on pitch count)

### `OccupancyHeatmap`
File: `lib/presentation/widgets/charts/occupancy_heatmap.dart`

Input: `List<dynamic>` — the `data` array from the backend `HeatmapResponse`. Each element is `{day_of_week: int (0=Sun–6=Sat), hour: int (0–23), count: int, revenue: double}`. This is a sparse list — only slots with bookings appear.

Renders a custom `GridView` (not fl_chart — no native heatmap widget):
- 7 rows (Sun–Sat, matching `day_of_week` 0–6) × 24 columns (hours 0–23)
- Cell color: linearly interpolated between `AppColors.background` (count = 0) and `AppColors.primary` (count = max in dataset)
- Sparse data → build a `Map<int, Map<int, int>>` (day → hour → count) for O(1) lookup, then render the full 7×24 grid
- Row labels: Sun–Sat on the left, 12px `AppColors.textSecondary`
- Column labels: every 4th hour (0, 4, 8, 12, 16, 20) at the top
- Cell size: flexible, fills available width
- No tap interaction needed

---

## 3. Integration into Existing Views

### `_MyAnalyticsView`
- After the stat cards row, before the "Daily Revenue" `DataTableCard`: insert `RevenueLineChart` with `_revenueChart` data
- After "Per-Pitch Breakdown" `DataTableCard` heading, before rows: insert `PitchRevenueBarChart` with `_pitchBreakdown` data
- Both charts wrapped in a `Card`-style container with `AppColors.background` fill, `AppColors.primaryDeep` border, `BorderRadius.circular(12)`, 16px padding

### `_AnalyticsProView` — Overview tab (`_tab == 0`)
- Before the existing pitch breakdown table: insert `RevenueLineChart` + `PitchRevenueBarChart`

### `_AnalyticsProView` — Heatmap tab (`_tab == 1`)
- At the top of the tab: insert `OccupancyHeatmap` with `_heatmap` data
- Below heatmap: insert `PeakHoursBarChart` with `_peaks['busiest']` data (the top 5 busiest hours from `PeakHoursResponse`)
- Existing heatmap/peak tables remain below the charts

### `_AnalyticsProView` — Customers tab (`_tab == 2`)
- No charts — repeat bookings %, top customers list are numbers-only, data doesn't suit visualisation

---

## 4. Shared Chart Card Container

All charts wrapped in:
```dart
Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: AppColors.background,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: AppColors.primaryDeep, width: 0.5),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      const SizedBox(height: 12),
      chart,
    ],
  ),
)
```

---

## 5. Style Rules

- All colors through `AppColors` — no `Colors.*` literals
- All labels use `GoogleFonts.dmSans`, size 11–13px, `AppColors.textSecondary`
- Charts show a `Text('No data', ...)` fallback when the input list is empty
- `fl_chart` touch handlers must not call `setState` from within the chart widget — use a callback pattern

---

## Files Changed

| File | Change |
|---|---|
| `pubspec.yaml` | Add `fl_chart: ^0.69.0` |
| `lib/presentation/widgets/charts/revenue_line_chart.dart` | New |
| `lib/presentation/widgets/charts/peak_hours_bar_chart.dart` | New |
| `lib/presentation/widgets/charts/pitch_revenue_bar_chart.dart` | New |
| `lib/presentation/widgets/charts/occupancy_heatmap.dart` | New |
| `lib/presentation/screens/manage/manage_panel_screen.dart` | Insert charts into `_MyAnalyticsView` and `_AnalyticsProView` |

---

## Non-Goals

- No new backend endpoints — all data already returned by existing analytics endpoints
- No export to PNG/PDF
- No date range picker (existing period dropdown stays)
- No real-time/live updates
