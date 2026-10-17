# Analytics Charts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add visual charts (line chart, bar charts, heatmap) above existing data tables in the turf manager analytics views.

**Architecture:** Four new chart widgets in `lib/presentation/widgets/charts/` receive plain `List<Map>` data from the existing state variables and render via `fl_chart`. No new API calls — all data already fetched. `OccupancyHeatmap` uses Flutter primitives (fl_chart has no heatmap widget). `PitchRevenueBarChart` also uses Flutter primitives (fl_chart has no horizontal bar widget). Both are wrapped in a shared chart card container.

**Tech Stack:** `fl_chart: ^0.69.0`, `google_fonts`, `AppColors` tokens, existing `manage_panel_screen.dart` state.

---

### Task 1: Add fl_chart dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add fl_chart to pubspec.yaml**

In `pubspec.yaml`, add after the `geolocator` line (around line 49):
```yaml
  fl_chart: ^0.69.0
```

- [ ] **Step 2: Run pub get**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn && flutter pub get
```

Expected: `Got dependencies!` with no errors.

- [ ] **Step 3: Commit**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn
git add pubspec.yaml pubspec.lock
git commit -m "feat: add fl_chart dependency for analytics charts"
```

---

### Task 2: Create RevenueLineChart widget

**Files:**
- Create: `lib/presentation/widgets/charts/revenue_line_chart.dart`

- [ ] **Step 1: Create the file**

```dart
// lib/presentation/widgets/charts/revenue_line_chart.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:turfinn/core/theme/app_colors.dart';

class RevenueLineChart extends StatelessWidget {
  const RevenueLineChart({super.key, required this.data});

  /// Each map must have 'date' (String) and 'amount' (num).
  final List<Map<String, dynamic>> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'No data',
            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final spots = data.asMap().entries.map((e) {
      final amount = (e.value['amount'] as num?)?.toDouble() ?? 0.0;
      return FlSpot(e.key.toDouble(), amount);
    }).toList();

    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final showEveryN = data.length > 10 ? (data.length / 6).ceil() : 1;

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppColors.primaryDeep.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= data.length || idx % showEveryN != 0) {
                    return const SizedBox.shrink();
                  }
                  final dateStr = '${data[idx]['date'] ?? ''}';
                  final label = dateStr.length >= 5
                      ? dateStr.substring(dateStr.length - 5)
                      : dateStr;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      label,
                      style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.textSecondary),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (value, meta) {
                  final String label;
                  if (value >= 1000000) {
                    label = '${(value / 1000000).toStringAsFixed(1)}M';
                  } else if (value >= 1000) {
                    label = '${(value / 1000).toStringAsFixed(0)}K';
                  } else {
                    label = value.toStringAsFixed(0);
                  }
                  return Text(
                    label,
                    style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.textSecondary),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minY: 0,
          maxY: maxY * 1.15,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.primary,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.3),
                    AppColors.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                final idx = spot.spotIndex;
                final date = idx < data.length ? '${data[idx]['date'] ?? ''}' : '';
                final amount = spot.y;
                final amtStr = amount >= 1000
                    ? '৳${(amount / 1000).toStringAsFixed(1)}K'
                    : '৳${amount.toStringAsFixed(0)}';
                return LineTooltipItem(
                  '$date\n$amtStr',
                  GoogleFonts.dmSans(fontSize: 11, color: AppColors.textPrimary),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn && flutter analyze lib/presentation/widgets/charts/revenue_line_chart.dart
```

Expected: no errors (warnings about unused imports if fl_chart not yet pulled are OK at this stage — run `flutter pub get` first if needed).

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/widgets/charts/revenue_line_chart.dart
git commit -m "feat: add RevenueLineChart widget"
```

---

### Task 3: Create PeakHoursBarChart widget

**Files:**
- Create: `lib/presentation/widgets/charts/peak_hours_bar_chart.dart`

- [ ] **Step 1: Create the file**

```dart
// lib/presentation/widgets/charts/peak_hours_bar_chart.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:turfinn/core/theme/app_colors.dart';

class PeakHoursBarChart extends StatelessWidget {
  const PeakHoursBarChart({super.key, required this.data});

  /// Each map must have 'hour' (int 0–23) and 'count' (num).
  final List<Map<String, dynamic>> data;

  String _formatHour(int h) {
    if (h == 0) return '12am';
    if (h < 12) return '${h}am';
    if (h == 12) return '12pm';
    return '${h - 12}pm';
  }

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'No data',
            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final counts = data.map((d) => (d['count'] as num?)?.toDouble() ?? 0.0).toList();
    final maxCount = counts.isEmpty ? 1.0 : counts.reduce((a, b) => a > b ? a : b);

    final barGroups = data.asMap().entries.map((e) {
      final idx = e.key;
      final count = (e.value['count'] as num?)?.toDouble() ?? 0.0;
      final isPeak = count == maxCount && maxCount > 0;
      return BarChartGroupData(
        x: idx,
        barRods: [
          BarChartRodData(
            toY: count,
            color: isPeak ? AppColors.primaryMid : AppColors.primary,
            width: 14,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      );
    }).toList();

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppColors.primaryDeep.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.textSecondary),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= data.length) return const SizedBox.shrink();
                  final hour = (data[idx]['hour'] as num?)?.toInt() ?? 0;
                  if (hour % 3 != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _formatHour(hour),
                      style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.textSecondary),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: barGroups,
          maxY: maxCount * 1.25,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final idx = group.x;
                if (idx < 0 || idx >= data.length) return null;
                final hour = (data[idx]['hour'] as num?)?.toInt() ?? 0;
                final count = rod.toY.toInt();
                return BarTooltipItem(
                  '${hour.toString().padLeft(2, '0')}:00 — $count bookings',
                  GoogleFonts.dmSans(fontSize: 11, color: AppColors.textPrimary),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn && flutter analyze lib/presentation/widgets/charts/peak_hours_bar_chart.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/widgets/charts/peak_hours_bar_chart.dart
git commit -m "feat: add PeakHoursBarChart widget"
```

---

### Task 4: Create PitchRevenueBarChart widget

**Files:**
- Create: `lib/presentation/widgets/charts/pitch_revenue_bar_chart.dart`

Note: fl_chart has no native horizontal bar chart. This widget uses Flutter primitives (Row + FractionallySizedBox) to render horizontal bars — matching the spec's visual exactly.

- [ ] **Step 1: Create the file**

```dart
// lib/presentation/widgets/charts/pitch_revenue_bar_chart.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:turfinn/core/theme/app_colors.dart';

class PitchRevenueBarChart extends StatelessWidget {
  const PitchRevenueBarChart({super.key, required this.data});

  /// Each map must have 'pitch_name' (String) and 'revenue' (num).
  final List<Map<String, dynamic>> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: 48,
        child: Center(
          child: Text(
            'No data',
            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final revenues = data.map((d) => (d['revenue'] as num?)?.toDouble() ?? 0.0).toList();
    final maxRevenue = revenues.isEmpty ? 1.0 : revenues.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: data.map((item) {
        final name = '${item['pitch_name'] ?? ''}';
        final revenue = (item['revenue'] as num?)?.toDouble() ?? 0.0;
        final fraction = maxRevenue > 0 ? (revenue / maxRevenue).clamp(0.0, 1.0) : 0.0;
        final displayName = name.length > 14 ? '${name.substring(0, 14)}…' : name;
        final revenueStr = revenue >= 1000
            ? '৳${(revenue / 1000).toStringAsFixed(1)}K'
            : '৳${revenue.toStringAsFixed(0)}';

        return Tooltip(
          message: '$name — $revenueStr',
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    displayName,
                    style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: fraction,
                      child: Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: Text(
                    revenueStr,
                    style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textSecondary),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn && flutter analyze lib/presentation/widgets/charts/pitch_revenue_bar_chart.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/widgets/charts/pitch_revenue_bar_chart.dart
git commit -m "feat: add PitchRevenueBarChart widget (horizontal bars)"
```

---

### Task 5: Create OccupancyHeatmap widget

**Files:**
- Create: `lib/presentation/widgets/charts/occupancy_heatmap.dart`

Note: Uses Flutter primitives per spec — fl_chart has no heatmap widget. Renders a 7×24 grid (all hours 0–23, not just 8–23 like the existing inline heatmap).

- [ ] **Step 1: Create the file**

```dart
// lib/presentation/widgets/charts/occupancy_heatmap.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:turfinn/core/theme/app_colors.dart';

class OccupancyHeatmap extends StatelessWidget {
  const OccupancyHeatmap({super.key, required this.data});

  /// Sparse list. Each element: {day_of_week: int (0=Sun–6=Sat), hour: int, count: int, revenue: double}
  final List<dynamic> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'No data',
            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    // Build O(1) lookup map: day -> hour -> count
    final grid = <int, Map<int, int>>{};
    int maxCount = 1;
    for (final cell in data) {
      final m = cell as Map<String, dynamic>;
      final day = (m['day_of_week'] as num?)?.toInt() ?? 0;
      final hour = (m['hour'] as num?)?.toInt() ?? 0;
      final count = (m['count'] as num?)?.toInt() ?? 0;
      grid.putIfAbsent(day, () => {});
      grid[day]![hour] = count;
      if (count > maxCount) maxCount = count;
    }

    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    // Column labels every 4th hour
    const labelHours = [0, 4, 8, 12, 16, 20];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Column headers (every 4th hour)
          Row(
            children: [
              const SizedBox(width: 40), // spacer for row labels
              for (int h = 0; h < 24; h++)
                SizedBox(
                  width: 28,
                  child: labelHours.contains(h)
                      ? Text(
                          '$h',
                          style: GoogleFonts.dmSans(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        )
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 4),
          // 7 rows (Sun–Sat)
          for (int d = 0; d < 7; d++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(
                      days[d],
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  for (int h = 0; h < 24; h++)
                    _Cell(
                      count: grid[d]?[h] ?? 0,
                      maxCount: maxCount,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.count, required this.maxCount});
  final int count;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final intensity = maxCount > 0 ? count / maxCount : 0.0;
    final color = count == 0
        ? AppColors.background
        : Color.lerp(AppColors.background, AppColors.primary, intensity)!;

    return Tooltip(
      message: '$count bookings',
      child: Container(
        width: 24,
        height: 22,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn && flutter analyze lib/presentation/widgets/charts/occupancy_heatmap.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/widgets/charts/occupancy_heatmap.dart
git commit -m "feat: add OccupancyHeatmap widget (7x24 grid)"
```

---

### Task 6: Integrate charts into `_MyAnalyticsView`

**Files:**
- Modify: `lib/presentation/screens/manage/manage_panel_screen.dart`

The current `_MyAnalyticsViewState.build()` has:
1. Stat cards row (lines ~424–436)
2. `const SizedBox(height: 24)` (line 437)
3. `if (_revenueChart != null ...)` `DataTableCard` titled 'Daily Revenue' (lines 438–447)
4. `const SizedBox(height: 24)` (line 448)
5. `if (_pitchBreakdown != null ...)` `DataTableCard` titled 'Per-Pitch Breakdown' (lines 449–464)

We need to:
- Add `RevenueLineChart` in a chart card container **before** the Daily Revenue `DataTableCard`
- Add `PitchRevenueBarChart` in a chart card container **before** the Per-Pitch `DataTableCard`

- [ ] **Step 1: Add chart imports at the top of manage_panel_screen.dart**

Find the existing import block (around line 1–15). Add after the last import:
```dart
import 'package:turfinn/presentation/widgets/charts/revenue_line_chart.dart';
import 'package:turfinn/presentation/widgets/charts/pitch_revenue_bar_chart.dart';
import 'package:turfinn/presentation/widgets/charts/peak_hours_bar_chart.dart';
import 'package:turfinn/presentation/widgets/charts/occupancy_heatmap.dart';
```

- [ ] **Step 2: Add `_ChartCard` helper widget**

At the bottom of `manage_panel_screen.dart` (after the last class, before EOF), add:

```dart
// ─────────────────────────────────────────────────────────────────────────────
// Shared chart card container
// ─────────────────────────────────────────────────────────────────────────────
class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryDeep, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Insert RevenueLineChart before Daily Revenue DataTableCard**

Find this block in `_MyAnalyticsViewState.build()` (around line 437–447):
```dart
          const SizedBox(height: 24),
          if (_revenueChart != null && _revenueChart!.isNotEmpty)
            DataTableCard(
              title: 'Daily Revenue',
```

Replace with:
```dart
          const SizedBox(height: 24),
          if (_revenueChart != null && _revenueChart!.isNotEmpty) ...[
            _ChartCard(
              title: 'Daily Revenue',
              child: RevenueLineChart(
                data: _revenueChart!
                    .map((d) => d as Map<String, dynamic>)
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_revenueChart != null && _revenueChart!.isNotEmpty)
            DataTableCard(
              title: 'Daily Revenue',
```

- [ ] **Step 4: Insert PitchRevenueBarChart before Per-Pitch DataTableCard**

Find this block (around line 448–464):
```dart
          const SizedBox(height: 24),
          if (_pitchBreakdown != null && _pitchBreakdown!.isNotEmpty)
            DataTableCard(
              title: 'Per-Pitch Breakdown',
```

Replace with:
```dart
          const SizedBox(height: 24),
          if (_pitchBreakdown != null && _pitchBreakdown!.isNotEmpty) ...[
            _ChartCard(
              title: 'Per-Pitch Breakdown',
              child: PitchRevenueBarChart(
                data: _pitchBreakdown!
                    .map((p) => p as Map<String, dynamic>)
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_pitchBreakdown != null && _pitchBreakdown!.isNotEmpty)
            DataTableCard(
              title: 'Per-Pitch Breakdown',
```

- [ ] **Step 5: Verify**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn && flutter analyze lib/presentation/screens/manage/manage_panel_screen.dart
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/screens/manage/manage_panel_screen.dart
git commit -m "feat: add revenue + pitch revenue charts to _MyAnalyticsView"
```

---

### Task 7: Integrate charts into `_AnalyticsProView` — Overview tab

**Files:**
- Modify: `lib/presentation/screens/manage/manage_panel_screen.dart`

The Overview tab (`_buildOverviewTab()`) currently starts with "Busiest/Slowest Hours" cards then the pitch breakdown table. Per spec: insert `RevenueLineChart` + `PitchRevenueBarChart` before the pitch breakdown table.

`_AnalyticsProView` doesn't currently fetch `_revenueChart` data — we need to add this.

- [ ] **Step 1: Add `_revenueChart` field to `_AnalyticsProViewState`**

Find `_AnalyticsProViewState` fields (around line 1577):
```dart
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _heatmap;
  Map<String, dynamic>? _peaks;
  Map<String, dynamic>? _customers;
  List<dynamic>? _pitchBreakdown;
```

Replace with:
```dart
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _heatmap;
  Map<String, dynamic>? _peaks;
  Map<String, dynamic>? _customers;
  List<dynamic>? _pitchBreakdown;
  List<dynamic>? _revenueChart;
```

- [ ] **Step 2: Fetch `_revenueChart` in `_AnalyticsProViewState._load()`**

Find the `_load()` method `Future.wait` call (around lines 1596–1608):
```dart
      final results = await Future.wait([
        src.getManagerSummary(period: _period),
        src.getManagerHeatmap(period: _period),
        src.getManagerPeakHours(period: _period),
        src.getManagerCustomerInsights(period: _period),
        src.getManagerPitchBreakdown(period: _period),
      ]);
      _summary = results[0] as Map<String, dynamic>;
      _heatmap = results[1] as Map<String, dynamic>;
      _peaks = results[2] as Map<String, dynamic>;
      _customers = results[3] as Map<String, dynamic>;
      _pitchBreakdown = results[4] as List<dynamic>;
```

Replace with:
```dart
      final days = _period == 'today' ? 1 : (_period == 'week' ? 7 : 30);
      final results = await Future.wait([
        src.getManagerSummary(period: _period),
        src.getManagerHeatmap(period: _period),
        src.getManagerPeakHours(period: _period),
        src.getManagerCustomerInsights(period: _period),
        src.getManagerPitchBreakdown(period: _period),
        src.getManagerRevenueChart(days: days),
      ]);
      _summary = results[0] as Map<String, dynamic>;
      _heatmap = results[1] as Map<String, dynamic>;
      _peaks = results[2] as Map<String, dynamic>;
      _customers = results[3] as Map<String, dynamic>;
      _pitchBreakdown = results[4] as List<dynamic>;
      _revenueChart = results[5] as List<dynamic>;
```

- [ ] **Step 3: Insert charts before pitch breakdown table in `_buildOverviewTab()`**

Find `_buildOverviewTab()` (around line 1667). It returns a `Column` with children:
1. Row of Busiest/Slowest peak cards
2. `const SizedBox(height: 24)`
3. `if (_pitchBreakdown ...) DataTableCard('Per-Pitch Breakdown', ...)`

Insert charts before the pitch breakdown `DataTableCard`. Find:
```dart
        const SizedBox(height: 24),
        // Per-pitch breakdown
        if (_pitchBreakdown != null && _pitchBreakdown!.isNotEmpty)
          DataTableCard(
            title: 'Per-Pitch Breakdown',
```

Replace with:
```dart
        const SizedBox(height: 24),
        if (_revenueChart != null && _revenueChart!.isNotEmpty) ...[
          _ChartCard(
            title: 'Daily Revenue',
            child: RevenueLineChart(
              data: _revenueChart!
                  .map((d) => d as Map<String, dynamic>)
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_pitchBreakdown != null && _pitchBreakdown!.isNotEmpty) ...[
          _ChartCard(
            title: 'Per-Pitch Breakdown',
            child: PitchRevenueBarChart(
              data: _pitchBreakdown!
                  .map((p) => p as Map<String, dynamic>)
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        // Per-pitch breakdown table
        if (_pitchBreakdown != null && _pitchBreakdown!.isNotEmpty)
          DataTableCard(
            title: 'Per-Pitch Breakdown',
```

- [ ] **Step 4: Verify**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn && flutter analyze lib/presentation/screens/manage/manage_panel_screen.dart
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/manage/manage_panel_screen.dart
git commit -m "feat: add revenue + pitch revenue charts to AnalyticsPro overview tab"
```

---

### Task 8: Integrate charts into `_AnalyticsProView` — Heatmap tab

**Files:**
- Modify: `lib/presentation/screens/manage/manage_panel_screen.dart`

The Heatmap tab (`_buildHeatmapTab()`) currently renders only the inline heatmap grid widget. Per spec: insert `OccupancyHeatmap` chart widget at the top, then `PeakHoursBarChart` below it, then the existing inline heatmap remains.

- [ ] **Step 1: Modify `_buildHeatmapTab()`**

Find `_buildHeatmapTab()` (around line 1752). Currently it starts:
```dart
  Widget _buildHeatmapTab() {
    final data = _heatmap?['data'] as List<dynamic>? ?? [];
    if (data.isEmpty) {
      return Center(child: Text('No heatmap data', ...));
    }
    // ... builds the existing inline heatmap Container
```

The method returns a single `Container`. We need to wrap it in a `Column` and prepend the new widgets. Find the `return Container(` that starts the heatmap grid (around line 1772) and wrap everything:

Replace the entire method body with:
```dart
  Widget _buildHeatmapTab() {
    final data = _heatmap?['data'] as List<dynamic>? ?? [];
    final busiest = (_peaks?['busiest'] as List<dynamic>? ?? [])
        .map((h) => h as Map<String, dynamic>)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Occupancy heatmap chart
        _ChartCard(
          title: 'Occupancy Heatmap',
          child: OccupancyHeatmap(data: data),
        ),
        const SizedBox(height: 16),
        // Peak hours bar chart
        _ChartCard(
          title: 'Peak Hours',
          child: PeakHoursBarChart(data: busiest),
        ),
        const SizedBox(height: 24),
        // Existing inline detailed heatmap (kept for detail)
        if (data.isNotEmpty) _buildExistingHeatmapGrid(data),
      ],
    );
  }
```

- [ ] **Step 2: Rename the existing heatmap body to `_buildExistingHeatmapGrid`**

The existing method body (from `final days = ...` through the closing `);`) should become a new private method. Find the current `_buildHeatmapTab` body after the early-return check — extract the full `Container(...)` into:

```dart
  Widget _buildExistingHeatmapGrid(List<dynamic> data) {
    final days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    // Build lookup: [day][hour] -> count
    final grid = <int, Map<int, int>>{};
    int maxCount = 1;
    for (final cell in data) {
      final m = cell as Map<String, dynamic>;
      final day = (m['day_of_week'] as num?)?.toInt() ?? 0;
      final hour = (m['hour'] as num?)?.toInt() ?? 0;
      final count = (m['count'] as num?)?.toInt() ?? 0;
      grid.putIfAbsent(day, () => {});
      grid[day]![hour] = count;
      if (count > maxCount) maxCount = count;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryDeep, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Booking Heatmap (Detail)', style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Booking density by day and hour (darker = more bookings)', style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hour headers
                Row(
                  children: [
                    const SizedBox(width: 40),
                    for (int h = 8; h < 24; h++)
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${h.toString().padLeft(2, '0')}',
                          style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                // Rows per day
                for (int d = 0; d < 7; d++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          child: Text(days[d], style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                        ),
                        for (int h = 8; h < 24; h++)
                          _heatCell(grid[d]?[h] ?? 0, maxCount),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Legend
          Row(
            children: [
              Text('Less', style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(width: 6),
              for (double intensity in [0.0, 0.25, 0.5, 0.75, 1.0])
                Container(
                  width: 20, height: 20,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1 + intensity * 0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              const SizedBox(width: 6),
              Text('More', style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 3: Verify**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn && flutter analyze lib/presentation/screens/manage/manage_panel_screen.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/manage/manage_panel_screen.dart
git commit -m "feat: add OccupancyHeatmap + PeakHoursBarChart to AnalyticsPro heatmap tab"
```

---

### Task 9: Build and smoke-test

- [ ] **Step 1: Full analyze pass**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn && flutter analyze
```

Expected: no errors (warnings OK).

- [ ] **Step 2: Build manage web app**

```bash
cd /Users/fin.com/Projects/brain-systems/turfinn && flutter build web --target lib/main_manage.dart --output build/web_manage --dart-define=API_BASE_URL=/api/v1
```

Expected: `✓ Built build/web_manage` with no errors.

- [ ] **Step 3: Commit build artifacts if needed (usually not committed)**

If Docker volumes need the build output:
```bash
docker compose restart manage
```

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: analytics charts complete — revenue line, peak hours bar, pitch revenue bar, occupancy heatmap"
```
