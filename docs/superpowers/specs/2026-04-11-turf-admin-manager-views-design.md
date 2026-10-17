# Turf Admin Panel — Manager Dashboard Views Design

## Goal

Add 3 new sidebar views to the existing turf admin web panel (`admin_panel_screen.dart`) so turf owners can see their analytics, manage their bookings (including walk-in), and view financial reports — all scoped to their own pitches.

## Scope

- **Audience:** Turf owners/managers using the web admin panel
- **Panel:** Existing `lib/presentation/screens/admin/admin_panel_screen.dart`
- **Backend:** Reuses the `/manager/*` endpoints already built (analytics, bookings, financials)
- **Not in scope:** Super admin panel, player-facing mobile app

---

## Data Layer

Add 7 new methods to `AdminRemoteSource` (`lib/data/sources/remote/admin_remote_source.dart`):

| Method | Endpoint | Returns |
|---|---|---|
| `getManagerSummary(String period)` | `GET /manager/analytics/summary?period=` | `Map<String, dynamic>` |
| `getManagerRevenueChart(int days)` | `GET /manager/analytics/revenue-chart?days=` | `List<dynamic>` |
| `getManagerPitchBreakdown(String period)` | `GET /manager/analytics/pitch-breakdown?period=` | `List<dynamic>` |
| `getManagerBookings({status, source, page, limit})` | `GET /manager/bookings` | `Map<String, dynamic>` |
| `createWalkInBooking(Map<String, dynamic> data)` | `POST /manager/bookings` | `void` |
| `updateManagerBookingStatus(String id, String status)` | `PUT /manager/bookings/:id/status` | `void` |
| `getManagerFinancials({String? from, String? to})` | `GET /manager/financials` | `Map<String, dynamic>` |

No freezed models — raw `Map<String, dynamic>`, consistent with every other view in this panel.

---

## New Sidebar Items

Append 3 items to `_navItems` in `admin_panel_screen.dart`:

```
My Analytics    (Icons.analytics_rounded)
My Bookings     (Icons.event_note_rounded)
My Financials   (Icons.account_balance_rounded)
```

Add corresponding views to the `IndexedStack`:
- `_MyAnalyticsView()`
- `_MyBookingsView()`
- `_MyFinancialsView()`

---

## View Designs

### My Analytics (`_MyAnalyticsView`)

- Period selector: `_PanelDropdown` with options `today`, `week`, `month` (default: `month`)
- 4 `StatCard` widgets in a responsive `Wrap` (3 cols on wide, 2 on narrow):
  - Revenue (BDT), Bookings count, Occupancy %, Avg Rating
- Daily revenue `DataTableCard`: columns Date, Amount — from `/revenue-chart`
- Per-pitch breakdown `DataTableCard`: Pitch Name, Bookings, Revenue, Occupancy %, Avg Rating

### My Bookings (`_MyBookingsView`)

- Filter row: status dropdown (All / pending / confirmed / cancelled) + source dropdown (All / turfinn / walk_in)
- "Add Walk-in" button → opens `showDialog` with form:
  - Pitch ID text field
  - Date picker (text field with date format)
  - Start time, End time (text fields, HH:mm format)
  - Customer name
  - Payment method dropdown (cash / card / transfer)
  - Amount field
  - Submit calls `createWalkInBooking`, then reloads list
- `DataTableCard`: Pitch, Customer, Time, Source, Cost, Status, Actions
- Actions: Confirm / Cancel buttons for pending bookings (same `_BookingActions` pattern)

### My Financials (`_MyFinancialsView`)

- Period selector: `_PanelDropdown` with `week`, `month`, `custom`
- For custom: two date text fields (from, to) in YYYY-MM-DD format
- 4 `StatCard` widgets: Total Revenue, Turfinn Revenue, Walk-in Revenue, Walk-in %
- Payment method breakdown `DataTableCard`: Method, Amount, Count (if available)

---

## Modified Files

```
lib/data/sources/remote/admin_remote_source.dart  — add 7 manager methods
lib/presentation/screens/admin/admin_panel_screen.dart — add 3 sidebar items + 3 view classes
```

No new files needed. Everything fits in the existing structure.

---

## Error Handling

- All `_load()` methods use try/catch with empty catch (consistent with existing views)
- `mounted` check before `setState` (consistent with existing views)
- Walk-in booking dialog shows error in a `Text` widget on failure
