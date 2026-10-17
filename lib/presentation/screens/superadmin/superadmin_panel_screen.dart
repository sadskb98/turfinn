import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/sources/remote/admin_remote_source.dart';
import '../../../data/sources/remote/superadmin_remote_source.dart';
import '../panel/widgets/panel_scaffold.dart';
import '../panel/widgets/stat_card.dart';
import '../panel/widgets/data_table_card.dart';
import 'widgets/pitch_pricing_dialog.dart';

class SuperAdminPanelScreen extends ConsumerStatefulWidget {
  const SuperAdminPanelScreen({super.key});

  @override
  ConsumerState<SuperAdminPanelScreen> createState() =>
      _SuperAdminPanelScreenState();
}

class _SuperAdminPanelScreenState
    extends ConsumerState<SuperAdminPanelScreen> {
  int _selectedIdx = 0;

  static const _navItems = [
    // ── Admin items ──────────────────────────────────────────────────────────
    PanelNavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    PanelNavItem(icon: Icons.people_rounded, label: 'Users'),
    PanelNavItem(icon: Icons.stadium_rounded, label: 'Pitches'),
    PanelNavItem(icon: Icons.calendar_month_rounded, label: 'Bookings'),
    PanelNavItem(icon: Icons.groups_rounded, label: 'Teams'),
    PanelNavItem(icon: Icons.sports_esports_rounded, label: 'Matches'),
    PanelNavItem(icon: Icons.tune_rounded, label: 'Platform Config'),
    PanelNavItem(icon: Icons.campaign_rounded, label: 'Marketing'),
    // KYC / Verification removed — in-app NID/selfie collection requires
    // a Bangladesh PII handling licence we don't hold. Real KYC is done
    // offline before super-admin registers a manager via Turf Admins.
    PanelNavItem(icon: Icons.gavel_rounded, label: 'Disputes & Support'),
    PanelNavItem(icon: Icons.badge_rounded, label: 'Turf Admins'),
    PanelNavItem(icon: Icons.payments_rounded, label: 'Match Payments'),
    PanelNavItem(icon: Icons.event_busy_rounded, label: 'Match Cancellations'),
    // ── Super-admin items ────────────────────────────────────────────────────
    PanelNavItem(icon: Icons.insights_rounded, label: 'Business Intelligence'),
    PanelNavItem(icon: Icons.account_balance_rounded, label: 'Finance & Audit'),
    PanelNavItem(icon: Icons.settings_rounded, label: 'System Control'),
    PanelNavItem(icon: Icons.map_rounded, label: 'Zones & Partners'),
    PanelNavItem(icon: Icons.add_business_rounded, label: 'Turf Onboarding'),
  ];

  @override
  Widget build(BuildContext context) {
    return PanelScaffold(
      title: 'Turfinn Super Admin',
      items: _navItems,
      selectedIndex: _selectedIdx,
      onItemTap: (i) => setState(() => _selectedIdx = i),
      body: IndexedStack(
        index: _selectedIdx,
        children: const [
          _DashboardView(),
          _UsersView(),
          _PitchesView(),
          _BookingsView(),
          _TeamsView(),
          _MatchesView(),
          _PlatformConfigView(),
          _MarketingView(),
          _DisputesView(),
          _TurfAdminsView(),
          _MatchPaymentsView(),
          _MatchCancellationsView(),
          _BIView(),
          _FinanceView(),
          _SystemControlView(),
          _ZonesPartnersView(),
          _TurfOnboardingView(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard
// ─────────────────────────────────────────────────────────────────────────────
class _DashboardView extends ConsumerStatefulWidget {
  const _DashboardView();
  @override
  ConsumerState<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<_DashboardView> {
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _stats = await ref.read(adminRemoteSourceProvider).getDashboard();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    final s = _stats ?? {};
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(title: 'Dashboard', subtitle: 'Platform overview'),
          const SizedBox(height: 24),
          LayoutBuilder(builder: (ctx, box) {
            final cols = box.maxWidth > 900 ? 3 : 2;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _statBox(cols, box, 'Total Users', '${s['total_users'] ?? 0}',
                    Icons.people, AppColors.primary),
                _statBox(cols, box, 'Active Pitches',
                    '${s['total_pitches'] ?? 0}', Icons.stadium, Colors.blueAccent),
                _statBox(cols, box, 'Total Bookings',
                    '${s['total_bookings'] ?? 0}', Icons.calendar_month,
                    Colors.orangeAccent),
                _statBox(cols, box, 'Revenue (BDT)',
                    _formatNum(s['total_revenue']), Icons.payments,
                    AppColors.primary),
                _statBox(cols, box, 'Teams', '${s['total_teams'] ?? 0}',
                    Icons.groups, Colors.purpleAccent),
                _statBox(cols, box, 'Matches', '${s['total_matches'] ?? 0}',
                    Icons.sports_esports, Colors.tealAccent),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _statBox(int cols, BoxConstraints box, String label, String value,
      IconData icon, Color color) {
    final w = (box.maxWidth - (cols - 1) * 16) / cols;
    return SizedBox(
        width: w,
        child: StatCard(label: label, value: value, icon: icon, iconColor: color));
  }

  String _formatNum(dynamic v) {
    if (v == null) return '0';
    final n = (v is int) ? v.toDouble() : (v as double);
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Users
// ─────────────────────────────────────────────────────────────────────────────
class _UsersView extends ConsumerStatefulWidget {
  const _UsersView();
  @override
  ConsumerState<_UsersView> createState() => _UsersViewState();
}

class _UsersViewState extends ConsumerState<_UsersView> {
  List<dynamic> _users = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String? _roleFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await ref.read(adminRemoteSourceProvider).listUsers(
            search: _searchCtrl.text,
            role: _roleFilter,
            limit: 50,
          );
      _users = resp['data'] as List<dynamic>? ?? [];
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setActive(String userId, bool active, String displayName) async {
    final verb = active ? 'Reactivate' : 'Deactivate';
    final body = active
        ? 'They will be able to sign in and use the platform again.'
        : "They'll be signed out on their next request and can't sign back in until reactivated. Existing bookings stay confirmed.";
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1F1A),
        title: Text('$verb $displayName?',
            style: GoogleFonts.nunito(
                color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
        content: Text(body,
            style: GoogleFonts.dmSans(
                fontSize: 13, color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: active
                      ? AppColors.primary
                      : const Color(0xFFB00020),
                  foregroundColor: active ? Colors.black : Colors.white),
              child: Text(verb)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(adminRemoteSourceProvider)
          .setUserActive(userId, active);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(active
              ? 'User reactivated.'
              : 'User deactivated. They are signed out on next request.')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not update: $e'),
          backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(title: 'Users', subtitle: 'Manage all platform users'),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 280,
                child: _PanelSearchField(
                  controller: _searchCtrl,
                  hint: 'Search by name or phone...',
                  onSubmit: (_) => _load(),
                ),
              ),
              const SizedBox(width: 12),
              _PanelDropdown(
                value: _roleFilter,
                hint: 'All Roles',
                items: const ['player', 'manager', 'admin'],
                onChanged: (v) {
                  _roleFilter = v;
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
          else
            DataTableCard.rich(
              title: 'All users (${_users.length})',
              columns: const [
                TableColumn('Name', flex: 3),
                TableColumn('Phone', flex: 3),
                TableColumn('Role', flex: 2),
                TableColumn('Status', flex: 2),
                TableColumn('Joined', flex: 2),
                TableColumn('Actions', flex: 3, alignRight: true),
              ],
              onRefresh: _load,
              rows: _users.map((u) {
                final m = u as Map<String, dynamic>;
                final role = (m['role'] as String?) ?? 'player';
                final isActive = (m['is_active'] as bool?) ?? true;
                final isSuperAdmin = role == 'super_admin';
                return [
                  CellText(
                      m['name']?.toString().isNotEmpty == true
                          ? m['name']
                          : '—',
                      bold: true),
                  CellText(m['phone'] ?? '—'),
                  StatusBadge(status: role),
                  StatusBadge(status: isActive ? 'active' : 'banned'),
                  CellText(_shortDate(m['created_at']), muted: true),
                  // Action column. Super-admin row: locked icon + tooltip.
                  // Everyone else: Activate / Deactivate button.
                  isSuperAdmin
                      ? const _LockedAction(
                          tooltip:
                              'Super-admin accounts cannot be modified from the panel.')
                      : _ActivationButton(
                          isActive: isActive,
                          onChange: (active) =>
                              _setActive(m['id'], active, m['name'] ?? 'this user'),
                        ),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }

  String _shortDate(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso);
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return iso;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pitches
// ─────────────────────────────────────────────────────────────────────────────
class _PitchesView extends ConsumerStatefulWidget {
  const _PitchesView();
  @override
  ConsumerState<_PitchesView> createState() => _PitchesViewState();
}

class _PitchesViewState extends ConsumerState<_PitchesView> {
  List<dynamic> _pitches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp =
          await ref.read(adminRemoteSourceProvider).listPitches(limit: 50);
      _pitches = resp['data'] as List<dynamic>? ?? [];
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(String id, bool active) async {
    final action = active ? 'Disable' : 'Enable';
    final body = active
        ? 'New bookings will be blocked, but existing ones stay confirmed.'
        : 'Players will be able to book this pitch again.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1F1A),
        title: Text('$action this pitch?',
            style: GoogleFonts.nunito(
                color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
        content: Text(body,
            style: GoogleFonts.dmSans(
                fontSize: 13, color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: active
                      ? const Color(0xFFB00020)
                      : AppColors.primary,
                  foregroundColor:
                      active ? Colors.white : Colors.black),
              child: Text(action)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(adminRemoteSourceProvider).togglePitch(id, !active);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(active ? 'Pitch disabled.' : 'Pitch enabled.')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not toggle: $e'),
          backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _editPricing(Map<String, dynamic> pitch) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => PitchPricingDialog(pitch: pitch),
    );
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pricing updated.')));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
              title: 'Pitches',
              subtitle: 'Manage all turfs on the platform'),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
          else
            DataTableCard(
              title: 'All Pitches (${_pitches.length})',
              columns: const [
                'Name', 'City', 'Price/hr', 'Plan / Rate', 'Status', 'Actions'
              ],
              onRefresh: _load,
              rows: _pitches.map((p) {
                final m = p as Map<String, dynamic>;
                final active = m['is_active'] == true;
                return [
                  CellText(m['name'] ?? '', bold: true),
                  CellText(m['city'] ?? ''),
                  CellText('${m['price_per_hour'] ?? 0} BDT'),
                  _PlanRateCell(p: m),
                  StatusBadge(status: active ? 'active' : 'cancelled'),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _ActionButton(
                      label: 'Pricing',
                      color: AppColors.primary,
                      onTap: () => _editPricing(m),
                    ),
                    const SizedBox(width: 6),
                    _ActionButton(
                      label: active ? 'Deactivate' : 'Activate',
                      color: active ? Colors.redAccent : Colors.blueAccent,
                      onTap: () => _toggle(m['id'], active),
                    ),
                  ]),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bookings
// ─────────────────────────────────────────────────────────────────────────────
class _BookingsView extends ConsumerStatefulWidget {
  const _BookingsView();
  @override
  ConsumerState<_BookingsView> createState() => _BookingsViewState();
}

class _BookingsViewState extends ConsumerState<_BookingsView> {
  List<dynamic> _bookings = [];
  bool _loading = true;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await ref.read(adminRemoteSourceProvider).listBookings(
            limit: 50,
            status: _statusFilter,
          );
      _bookings = resp['data'] as List<dynamic>? ?? [];
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setStatus(String id, String status) async {
    try {
      await ref
          .read(adminRemoteSourceProvider)
          .updateBookingStatus(id, status);
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
              title: 'Bookings', subtitle: 'All platform bookings'),
          const SizedBox(height: 16),
          Row(
            children: [
              _PanelDropdown(
                value: _statusFilter,
                hint: 'All Statuses',
                items: const [
                  'pending', 'confirmed', 'cancelled', 'completed'
                ],
                onChanged: (v) {
                  _statusFilter = v;
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
          else
            DataTableCard(
              title: 'Bookings (${_bookings.length})',
              columns: const [
                'Pitch', 'User', 'Date', 'Cost', 'Status', 'Actions'
              ],
              onRefresh: _load,
              rows: _bookings.map((b) {
                final m = b as Map<String, dynamic>;
                return [
                  CellText(m['pitch_name'] ?? '', bold: true),
                  CellText(m['user_name']?.toString().isNotEmpty == true
                      ? m['user_name']
                      : m['user_phone'] ?? ''),
                  CellText(_shortDateTime(m['starts_at'])),
                  CellText('${m['total_cost'] ?? 0} BDT'),
                  StatusBadge(status: m['status'] ?? ''),
                  _BookingActions(
                    status: m['status'] ?? '',
                    onConfirm: () => _setStatus(m['id'], 'confirmed'),
                    onCancel: () => _setStatus(m['id'], 'cancelled'),
                    onComplete: () => _setStatus(m['id'], 'completed'),
                  ),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }

  String _shortDateTime(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso);
      return '${d.day}/${d.month} '
          '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Teams
// ─────────────────────────────────────────────────────────────────────────────
class _TeamsView extends ConsumerStatefulWidget {
  const _TeamsView();
  @override
  ConsumerState<_TeamsView> createState() => _TeamsViewState();
}

class _TeamsViewState extends ConsumerState<_TeamsView> {
  List<dynamic> _teams = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp =
          await ref.read(adminRemoteSourceProvider).listTeams(limit: 50);
      _teams = resp['data'] as List<dynamic>? ?? [];
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
              title: 'Teams', subtitle: 'All teams on the platform'),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
          else
            DataTableCard(
              title: 'Teams (${_teams.length})',
              columns: const ['Name', 'Code', 'Format', 'Members', 'Status'],
              onRefresh: _load,
              rows: _teams.map((t) {
                final m = t as Map<String, dynamic>;
                final members = m['members'] as List<dynamic>? ?? [];
                return [
                  CellText(m['name'] ?? '', bold: true),
                  CellText(m['code'] ?? ''),
                  CellText(m['format'] ?? ''),
                  CellText('${members.length}/${m['max_players'] ?? '?'}'),
                  StatusBadge(status: m['status'] ?? ''),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Matches
// ─────────────────────────────────────────────────────────────────────────────
class _MatchesView extends ConsumerStatefulWidget {
  const _MatchesView();
  @override
  ConsumerState<_MatchesView> createState() => _MatchesViewState();
}

class _MatchesViewState extends ConsumerState<_MatchesView> {
  List<dynamic> _matches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp =
          await ref.read(adminRemoteSourceProvider).listMatches(limit: 50);
      _matches = resp['data'] as List<dynamic>? ?? [];
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
              title: 'Matches', subtitle: 'All matchmaking results'),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
          else
            DataTableCard(
              title: 'Matches (${_matches.length})',
              columns: const [
                'Home Team', 'Away Team', 'Format', 'Status', 'Created'
              ],
              onRefresh: _load,
              rows: _matches.map((m) {
                final data = m as Map<String, dynamic>;
                final home = data['home_team'] as Map<String, dynamic>?;
                final away = data['away_team'] as Map<String, dynamic>?;
                return [
                  CellText(home?['name'] ?? '—', bold: true),
                  CellText(away?['name'] ?? 'Waiting...'),
                  CellText(data['format'] ?? ''),
                  StatusBadge(status: data['status'] ?? ''),
                  CellText(_shortDate(data['created_at'])),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }

  String _shortDate(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso);
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return iso;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Platform Configuration
// ─────────────────────────────────────────────────────────────────────────────
class _PlatformConfigView extends ConsumerStatefulWidget {
  const _PlatformConfigView();
  @override
  ConsumerState<_PlatformConfigView> createState() =>
      _PlatformConfigViewState();
}

class _PlatformConfigViewState extends ConsumerState<_PlatformConfigView> {
  List<dynamic>? _settings;
  List<dynamic>? _pricingRules;
  List<dynamic>? _flags;
  List<dynamic>? _templates;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final src = ref.read(adminRemoteSourceProvider);
    try {
      final results = await Future.wait([
        src.getSettings(),
        src.getPricingRules(),
        src.getFlags(),
        src.getTemplates(),
      ]);
      _settings = results[0] as List<dynamic>;
      _pricingRules = results[1] as List<dynamic>;
      _flags = results[2] as List<dynamic>;
      _templates = results[3] as List<dynamic>;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleFlag(String key, bool current) async {
    try {
      await ref.read(adminRemoteSourceProvider).updateFlag(key, !current);
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
              title: 'Platform Configuration',
              subtitle:
                  'Settings, pricing rules, feature flags & templates'),
          const SizedBox(height: 24),
          if (_settings != null)
            DataTableCard(
              title: 'Settings',
              columns: const ['Key', 'Value', 'Description'],
              onRefresh: _load,
              rows: _settings!
                  .map((s) => [
                        CellText('${s['key']}', bold: true),
                        CellText('${s['value']}'),
                        CellText('${s['description'] ?? ''}'),
                      ])
                  .toList(),
            ),
          const SizedBox(height: 24),
          if (_pricingRules != null)
            DataTableCard(
              title: 'Pricing Rules',
              columns: const [
                'Name', 'Type', 'Multiplier', 'Fixed Amt', 'Days', 'Time',
                'Active'
              ],
              onRefresh: _load,
              rows: _pricingRules!
                  .map((r) => [
                        CellText('${r['name']}', bold: true),
                        CellText('${r['rule_type']}'),
                        CellText('${r['multiplier']}'),
                        CellText('${r['fixed_amount']}'),
                        CellText('${r['applies_to_days'] ?? ''}'),
                        CellText(
                            '${r['time_from'] ?? ''}-${r['time_to'] ?? ''}'),
                        StatusBadge(
                            status: r['is_active'] == true
                                ? 'active'
                                : 'pending'),
                      ])
                  .toList(),
            ),
          const SizedBox(height: 24),
          if (_flags != null)
            DataTableCard(
              title: 'Feature Flags',
              columns: const ['Key', 'Status', 'Description', 'Actions'],
              onRefresh: _load,
              rows: _flags!.map((f) {
                final enabled = f['enabled'] == true;
                return [
                  CellText('${f['key']}', bold: true),
                  StatusBadge(status: enabled ? 'active' : 'pending'),
                  CellText('${f['description'] ?? ''}'),
                  _ActionButton(
                    label: enabled ? 'Disable' : 'Enable',
                    color: enabled ? Colors.redAccent : AppColors.primary,
                    onTap: () => _toggleFlag('${f['key']}', enabled),
                  ),
                ];
              }).toList(),
            ),
          const SizedBox(height: 24),
          if (_templates != null)
            DataTableCard(
              title: 'Notification Templates',
              columns: const ['Type', 'Channel', 'Subject', 'Active'],
              onRefresh: _load,
              rows: _templates!
                  .map((t) => [
                        CellText('${t['type']}', bold: true),
                        CellText('${t['channel']}'),
                        CellText('${t['subject'] ?? ''}'),
                        StatusBadge(
                            status: t['is_active'] == true
                                ? 'active'
                                : 'pending'),
                      ])
                  .toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Marketing & Growth
// ─────────────────────────────────────────────────────────────────────────────
class _MarketingView extends ConsumerStatefulWidget {
  const _MarketingView();
  @override
  ConsumerState<_MarketingView> createState() => _MarketingViewState();
}

class _MarketingViewState extends ConsumerState<_MarketingView> {
  List<dynamic>? _promoCodes;
  List<dynamic>? _campaigns;
  List<dynamic>? _featured;
  List<dynamic>? _banners;
  Map<String, dynamic>? _referralStats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final src = ref.read(adminRemoteSourceProvider);
    try {
      final results = await Future.wait([
        src.listPromoCodes(),
        src.listCampaigns(),
        src.listFeaturedPitches(),
        src.listBanners(),
        src.getReferralStats(),
      ]);
      _promoCodes =
          (results[0] as Map<String, dynamic>)['data'] as List<dynamic>?;
      _campaigns =
          (results[1] as Map<String, dynamic>)['data'] as List<dynamic>?;
      _featured = results[2] as List<dynamic>;
      _banners = results[3] as List<dynamic>;
      _referralStats = results[4] as Map<String, dynamic>;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
              title: 'Marketing & Growth',
              subtitle: 'Promo codes, campaigns, banners & referrals'),
          const SizedBox(height: 24),
          if (_referralStats != null)
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: 220,
                  child: StatCard(
                    label: 'Total Referrals',
                    value:
                        '${_referralStats!['total_referrals'] ?? 0}',
                    icon: Icons.share_rounded,
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: StatCard(
                    label: 'Total Rewarded',
                    value:
                        '${_referralStats!['total_rewarded'] ?? 0}',
                    icon: Icons.card_giftcard_rounded,
                    iconColor: Colors.orangeAccent,
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: StatCard(
                    label: 'Conversion Rate',
                    value:
                        '${(_referralStats!['conversion_rate'] as num?)?.toStringAsFixed(1) ?? '0'}%',
                    icon: Icons.trending_up_rounded,
                    iconColor: Colors.blueAccent,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
          if (_promoCodes != null)
            DataTableCard(
              title: 'Promo Codes',
              columns: const [
                'Code', 'Type', 'Value', 'Uses', 'Valid To', 'Active'
              ],
              onRefresh: _load,
              rows: (_promoCodes ?? [])
                  .map((p) => [
                        CellText('${p['code']}', bold: true),
                        CellText('${p['discount_type']}'),
                        CellText('${p['discount_value']}'),
                        CellText('${p['used_count']}/${p['max_uses']}'),
                        CellText(
                            '${p['valid_to']?.toString().substring(0, 10) ?? ''}'),
                        StatusBadge(
                            status: p['is_active'] == true
                                ? 'active'
                                : 'cancelled'),
                      ])
                  .toList(),
            ),
          const SizedBox(height: 24),
          if (_campaigns != null)
            DataTableCard(
              title: 'Campaigns',
              columns: const ['Title', 'Segment', 'Sent', 'Created'],
              onRefresh: _load,
              rows: (_campaigns ?? [])
                  .map((c) => [
                        CellText('${c['title']}', bold: true),
                        CellText('${c['segment_type']}'),
                        CellText('${c['sent_count']}'),
                        CellText(
                            '${c['created_at']?.toString().substring(0, 10) ?? ''}'),
                      ])
                  .toList(),
            ),
          const SizedBox(height: 24),
          if (_banners != null)
            DataTableCard(
              title: 'Banners',
              columns: const ['Title', 'Order', 'Active'],
              onRefresh: _load,
              rows: (_banners ?? [])
                  .map((b) => [
                        CellText(
                            '${b['title'] ?? b['image_url'] ?? ''}',
                            bold: true),
                        CellText('${b['display_order']}'),
                        StatusBadge(
                            status: b['is_active'] == true
                                ? 'active'
                                : 'pending'),
                      ])
                  .toList(),
            ),
          const SizedBox(height: 24),
          if (_featured != null)
            DataTableCard(
              title: 'Featured Pitches',
              columns: const [
                'Pitch', 'Position', 'Amount Paid', 'Starts', 'Ends'
              ],
              onRefresh: _load,
              rows: (_featured ?? [])
                  .map((f) => [
                        CellText(
                            '${f['pitch_name'] ?? f['pitch_id']}',
                            bold: true),
                        CellText('${f['position']}'),
                        CellText('${f['amount_paid']} BDT'),
                        CellText(
                            '${f['starts_at']?.toString().substring(0, 10) ?? ''}'),
                        CellText(
                            '${f['ends_at']?.toString().substring(0, 10) ?? ''}'),
                      ])
                  .toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KYC / Verification
// ─────────────────────────────────────────────────────────────────────────────
class _KYCView extends ConsumerStatefulWidget {
  const _KYCView();
  @override
  ConsumerState<_KYCView> createState() => _KYCViewState();
}

class _KYCViewState extends ConsumerState<_KYCView> {
  List<dynamic> _items = [];
  bool _loading = true;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await ref
          .read(adminRemoteSourceProvider)
          .listKYC(limit: 50, status: _statusFilter);
      _items = resp['data'] as List<dynamic>? ?? [];
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _approve(String id) async {
    try {
      await ref.read(adminRemoteSourceProvider).approveKYC(id);
      _load();
    } catch (_) {}
  }

  Future<void> _reject(String id) async {
    final ctrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1F1A),
        title: Text('Reject KYC',
            style: GoogleFonts.nunito(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Reason',
            labelStyle: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) Navigator.pop(ctx, true);
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (result == true) {
      try {
        await ref
            .read(adminRemoteSourceProvider)
            .rejectKYC(id, ctrl.text);
        _load();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
              title: 'KYC / Verification',
              subtitle:
                  'Manager onboarding and identity verification'),
          const SizedBox(height: 16),
          Row(
            children: [
              _PanelDropdown(
                value: _statusFilter,
                hint: 'All Statuses',
                items: const ['pending', 'approved', 'rejected'],
                onChanged: (v) {
                  _statusFilter = v;
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
          else
            DataTableCard(
              title: 'KYC Applications (${_items.length})',
              columns: const [
                'Name', 'Phone', 'NID', 'Business', 'Status', 'Actions'
              ],
              onRefresh: _load,
              rows: _items.map((k) {
                final m = k as Map<String, dynamic>;
                final status = m['status'] ?? '';
                return [
                  CellText(m['user_name'] ?? '—', bold: true),
                  CellText(m['user_phone'] ?? ''),
                  CellText(m['nid_number'] ?? ''),
                  CellText(m['business_name'] ?? ''),
                  StatusBadge(status: status),
                  if (status == 'pending')
                    Wrap(spacing: 6, children: [
                      _ActionButton(
                          label: 'Approve',
                          color: AppColors.primary,
                          onTap: () => _approve(m['id'])),
                      _ActionButton(
                          label: 'Reject',
                          color: Colors.redAccent,
                          onTap: () => _reject(m['id'])),
                    ])
                  else
                    const SizedBox.shrink(),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Disputes & Support
// ─────────────────────────────────────────────────────────────────────────────
class _DisputesView extends ConsumerStatefulWidget {
  const _DisputesView();
  @override
  ConsumerState<_DisputesView> createState() => _DisputesViewState();
}

class _DisputesViewState extends ConsumerState<_DisputesView> {
  List<dynamic> _disputes = [];
  List<dynamic> _tickets = [];
  List<dynamic> _flaggedReviews = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final src = ref.read(adminRemoteSourceProvider);
    try {
      final results = await Future.wait([
        src.listDisputes(limit: 50),
        src.listTickets(limit: 50),
        src.listFlaggedReviews(limit: 50),
      ]);
      _disputes =
          (results[0] as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];
      _tickets =
          (results[1] as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];
      _flaggedReviews =
          (results[2] as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
              title: 'Disputes & Support',
              subtitle: 'Disputes, tickets & review moderation'),
          const SizedBox(height: 24),
          DataTableCard(
            title: 'Disputes (${_disputes.length})',
            columns: const [
              'Booking', 'Raised By', 'Reason', 'Status', 'Created'
            ],
            onRefresh: _load,
            rows: _disputes.map((d) {
              final m = d as Map<String, dynamic>;
              return [
                CellText(
                    '${m['booking_id']?.toString().substring(0, 8) ?? ''}',
                    bold: true),
                CellText(m['raised_by_name'] ?? ''),
                CellText(m['reason'] ?? ''),
                StatusBadge(status: m['status'] ?? ''),
                CellText(
                    '${m['created_at']?.toString().substring(0, 10) ?? ''}'),
              ];
            }).toList(),
          ),
          const SizedBox(height: 24),
          DataTableCard(
            title: 'Support Tickets (${_tickets.length})',
            columns: const [
              'Subject', 'User', 'Category', 'Priority', 'Status', 'Created'
            ],
            onRefresh: _load,
            rows: _tickets.map((t) {
              final m = t as Map<String, dynamic>;
              return [
                CellText(m['subject'] ?? '', bold: true),
                CellText(m['user_name'] ?? ''),
                CellText(m['category'] ?? ''),
                CellText(m['priority'] ?? 'normal'),
                StatusBadge(status: m['status'] ?? ''),
                CellText(
                    '${m['created_at']?.toString().substring(0, 10) ?? ''}'),
              ];
            }).toList(),
          ),
          const SizedBox(height: 24),
          DataTableCard(
            title: 'Flagged Reviews (${_flaggedReviews.length})',
            columns: const [
              'Pitch', 'User', 'Rating', 'Comment', 'Status', 'Actions'
            ],
            onRefresh: _load,
            rows: _flaggedReviews.map((r) {
              final m = r as Map<String, dynamic>;
              return [
                CellText(m['pitch_name'] ?? '', bold: true),
                CellText(m['user_name'] ?? ''),
                CellText('${m['rating']}/5'),
                CellText(m['comment'] ?? ''),
                StatusBadge(status: m['status'] ?? ''),
                Wrap(spacing: 6, children: [
                  _ActionButton(
                      label: 'Approve',
                      color: AppColors.primary,
                      onTap: () async {
                        try {
                          await ref
                              .read(adminRemoteSourceProvider)
                              .moderateReview(m['id'], action: 'approve');
                          _load();
                        } catch (_) {}
                      }),
                  _ActionButton(
                      label: 'Remove',
                      color: Colors.redAccent,
                      onTap: () async {
                        try {
                          await ref
                              .read(adminRemoteSourceProvider)
                              .moderateReview(m['id'], action: 'remove');
                          _load();
                        } catch (_) {}
                      }),
                ]),
              ];
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Business Intelligence
// ─────────────────────────────────────────────────────────────────────────────
class _BIView extends ConsumerStatefulWidget {
  const _BIView();
  @override
  ConsumerState<_BIView> createState() => _BIViewState();
}

class _BIViewState extends ConsumerState<_BIView> {
  Map<String, dynamic>? _northStar;
  List<dynamic>? _funnel;
  List<dynamic>? _revenue;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final src = ref.read(superAdminRemoteSourceProvider);
    try {
      final results = await Future.wait([
        src.getNorthStar(),
        src.getFunnel(),
        src.getRevenueTimeSeries(),
      ]);
      _northStar = results[0] as Map<String, dynamic>;
      _funnel = results[1] as List<dynamic>;
      _revenue = results[2] as List<dynamic>;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Business Intelligence',
              style: GoogleFonts.nunito(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text('North Star Metrics & Analytics',
              style: GoogleFonts.dmSans(
                  fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          if (_northStar != null)
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: 240,
                  child: StatCard(
                    label: 'Total GMV',
                    value:
                        '${(_northStar!['gmv'] ?? 0).toStringAsFixed(0)} BDT',
                    icon: Icons.monetization_on_rounded,
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: StatCard(
                    label: 'GMV (MTD)',
                    value:
                        '${(_northStar!['gmv_mtd'] ?? 0).toStringAsFixed(0)} BDT',
                    icon: Icons.trending_up_rounded,
                    iconColor: Colors.blueAccent,
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: StatCard(
                    label: 'Net Revenue',
                    value:
                        '${(_northStar!['net_revenue'] ?? 0).toStringAsFixed(0)} BDT',
                    icon: Icons.attach_money_rounded,
                    iconColor: Colors.orangeAccent,
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: StatCard(
                    label: 'Active Turfs',
                    value: '${_northStar!['active_turfs'] ?? 0}',
                    icon: Icons.stadium_rounded,
                    iconColor: Colors.purpleAccent,
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: StatCard(
                    label: 'Active Players',
                    value: '${_northStar!['active_players'] ?? 0}',
                    icon: Icons.people_rounded,
                    iconColor: Colors.tealAccent,
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: StatCard(
                    label: 'Bookings (MTD)',
                    value: '${_northStar!['bookings_mtd'] ?? 0}',
                    icon: Icons.calendar_month_rounded,
                    iconColor: Colors.pinkAccent,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 32),
          if (_funnel != null && _funnel!.isNotEmpty)
            DataTableCard(
              title: 'Booking Funnel',
              columns: const ['Step', 'Count', 'Drop-off'],
              rows: _funnel!
                  .map((s) => [
                        CellText('${s['event_type']}', bold: true),
                        CellText('${s['count']}'),
                        CellText(
                            '${(s['drop_off'] as num?)?.toStringAsFixed(1) ?? '0.0'}%'),
                      ])
                  .toList(),
              onRefresh: _load,
            ),
          const SizedBox(height: 24),
          if (_revenue != null && _revenue!.isNotEmpty)
            DataTableCard(
              title: 'Revenue Time Series',
              columns: const ['Date', 'Revenue (BDT)'],
              rows: _revenue!
                  .map((r) => [
                        CellText('${r['date']}'),
                        CellText(
                            '${(r['revenue'] as num?)?.toStringAsFixed(0) ?? '0'}'),
                      ])
                  .toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Finance & Audit
// ─────────────────────────────────────────────────────────────────────────────
class _FinanceView extends ConsumerStatefulWidget {
  const _FinanceView();
  @override
  ConsumerState<_FinanceView> createState() => _FinanceViewState();
}

class _FinanceViewState extends ConsumerState<_FinanceView> {
  Map<String, dynamic>? _trialBalance;
  Map<String, dynamic>? _auditLog;
  List<dynamic>? _vatReport;
  List<dynamic>? _fraudFlags;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final src = ref.read(superAdminRemoteSourceProvider);
    try {
      final results = await Future.wait([
        src.getTrialBalance(),
        src.listAuditLog(),
        src.getVATReport(),
        src.listFraudFlags(),
      ]);
      _trialBalance = results[0] as Map<String, dynamic>;
      _auditLog = results[1] as Map<String, dynamic>;
      _vatReport = results[2] as List<dynamic>;
      _fraudFlags =
          (results[3] as Map<String, dynamic>)['data'] as List<dynamic>?;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Finance & Audit',
              style: GoogleFonts.nunito(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text('Ledger, VAT, Fraud Monitoring & Audit Trail',
              style: GoogleFonts.dmSans(
                  fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          if (_trialBalance != null && _trialBalance!.isNotEmpty)
            DataTableCard(
              title: 'Trial Balance',
              columns: const ['Account', 'Net Balance (Paisa)'],
              rows: _trialBalance!.entries
                  .map((e) => [
                        CellText(e.key, bold: true),
                        CellText('${e.value}'),
                      ])
                  .toList(),
            ),
          const SizedBox(height: 24),
          if (_vatReport != null && _vatReport!.isNotEmpty)
            DataTableCard(
              title: 'VAT Report',
              columns: const [
                'Month', 'Bookings', 'GMV', 'Platform Fee', 'VAT'
              ],
              rows: _vatReport!
                  .map((r) => [
                        CellText('${r['month']}', bold: true),
                        CellText('${r['total_bookings']}'),
                        CellText(
                            '${(r['total_gmv'] as num?)?.toStringAsFixed(0) ?? '0'}'),
                        CellText(
                            '${(r['total_platform_fee'] as num?)?.toStringAsFixed(0) ?? '0'}'),
                        CellText(
                            '${(r['vat_amount'] as num?)?.toStringAsFixed(0) ?? '0'}'),
                      ])
                  .toList(),
            ),
          const SizedBox(height: 24),
          if (_fraudFlags != null)
            DataTableCard(
              title: 'Fraud Flags',
              columns: const ['Entity', 'Type', 'Status', 'Created'],
              rows: (_fraudFlags ?? [])
                  .map((f) => [
                        CellText(
                            '${f['entity_type']}/${f['entity_id']?.toString().substring(0, 8) ?? ''}'),
                        CellText('${f['flag_type']}', bold: true),
                        StatusBadge(status: '${f['status']}'),
                        CellText(
                            '${f['created_at']?.toString().substring(0, 10) ?? ''}'),
                      ])
                  .toList(),
              onRefresh: _load,
            ),
          const SizedBox(height: 24),
          if (_auditLog != null)
            _AuditLogTable(
                data: (_auditLog!['data'] as List<dynamic>?) ?? []),
        ],
      ),
    );
  }
}

class _AuditLogTable extends StatelessWidget {
  const _AuditLogTable({required this.data});
  final List<dynamic> data;

  @override
  Widget build(BuildContext context) {
    return DataTableCard(
      title: 'Audit Log (Recent)',
      columns: const ['Actor', 'Action', 'Entity', 'When'],
      rows: data
          .take(20)
          .map((a) => [
                CellText(
                    '${a['actor_id']?.toString().substring(0, 8) ?? ''}'),
                CellText('${a['action']}', bold: true),
                CellText(
                    '${a['entity_type']}/${a['entity_id']?.toString().substring(0, 8) ?? ''}'),
                CellText(
                    '${a['created_at']?.toString().substring(0, 10) ?? ''}'),
              ])
          .toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// System Control
// ─────────────────────────────────────────────────────────────────────────────
class _SystemControlView extends ConsumerStatefulWidget {
  const _SystemControlView();
  @override
  ConsumerState<_SystemControlView> createState() =>
      _SystemControlViewState();
}

class _SystemControlViewState extends ConsumerState<_SystemControlView> {
  List<dynamic>? _rateLimits;
  List<dynamic>? _apiKeys;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final src = ref.read(superAdminRemoteSourceProvider);
    try {
      final results = await Future.wait([
        src.listRateLimits(),
        src.listAPIKeys(),
      ]);
      _rateLimits = results[0] as List<dynamic>;
      _apiKeys =
          (results[1] as Map<String, dynamic>)['data'] as List<dynamic>?;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('System Control',
              style: GoogleFonts.nunito(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text('Rate Limits & API Keys',
              style: GoogleFonts.dmSans(
                  fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          if (_rateLimits != null)
            DataTableCard(
              title: 'Rate Limits',
              columns: const [
                'Endpoint Group', 'RPM', 'Burst', 'Enabled'
              ],
              rows: _rateLimits!
                  .map((r) => [
                        CellText('${r['endpoint_group']}', bold: true),
                        CellText('${r['requests_per_minute']}'),
                        CellText('${r['burst']}'),
                        StatusBadge(
                            status: r['is_enabled'] == true
                                ? 'active'
                                : 'pending'),
                      ])
                  .toList(),
              onRefresh: _load,
            ),
          const SizedBox(height: 24),
          if (_apiKeys != null)
            DataTableCard(
              title: 'API Keys',
              columns: const ['Name', 'Owner', 'Status', 'Created'],
              rows: (_apiKeys ?? [])
                  .map((k) => [
                        CellText('${k['name']}', bold: true),
                        CellText('${k['owner_org'] ?? '-'}'),
                        StatusBadge(
                            status: k['is_active'] == true
                                ? 'active'
                                : 'cancelled'),
                        CellText(
                            '${k['created_at']?.toString().substring(0, 10) ?? ''}'),
                      ])
                  .toList(),
              trailing: _CreateAPIKeyButton(onCreated: _load),
            ),
        ],
      ),
    );
  }
}

class _CreateAPIKeyButton extends ConsumerWidget {
  const _CreateAPIKeyButton({required this.onCreated});
  final VoidCallback onCreated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      onPressed: () async {
        final nameCtrl = TextEditingController();
        final orgCtrl = TextEditingController();
        final result = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF0A1F1A),
            title: Text('Create API Key',
                style: GoogleFonts.nunito(color: AppColors.textPrimary)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: orgCtrl,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Owner Org (optional)',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  if (nameCtrl.text.isEmpty) return;
                  try {
                    final data = await ref
                        .read(superAdminRemoteSourceProvider)
                        .createAPIKey(
                          name: nameCtrl.text,
                          ownerOrg:
                              orgCtrl.text.isEmpty ? null : orgCtrl.text,
                        );
                    if (ctx.mounted) {
                      Navigator.pop(ctx, true);
                      showDialog(
                        context: ctx,
                        builder: (c) => AlertDialog(
                          backgroundColor: const Color(0xFF0A1F1A),
                          title: Text('API Key Created',
                              style: GoogleFonts.nunito(
                                  color: AppColors.textPrimary)),
                          content: SelectableText(
                            '${data['key']}',
                            style: GoogleFonts.firaCode(
                                fontSize: 13, color: AppColors.primary),
                          ),
                          actions: [
                            FilledButton(
                              onPressed: () => Navigator.pop(c),
                              child: const Text('Done'),
                            ),
                          ],
                        ),
                      );
                    }
                  } catch (_) {
                    if (ctx.mounted) Navigator.pop(ctx, false);
                  }
                },
                child: const Text('Create'),
              ),
            ],
          ),
        );
        if (result == true) onCreated();
      },
      icon: const Icon(Icons.add, size: 16),
      label: Text('New Key',
          style: GoogleFonts.dmSans(
              fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Zones & Partners
// ─────────────────────────────────────────────────────────────────────────────
class _ZonesPartnersView extends ConsumerStatefulWidget {
  const _ZonesPartnersView();
  @override
  ConsumerState<_ZonesPartnersView> createState() =>
      _ZonesPartnersViewState();
}

class _ZonesPartnersViewState extends ConsumerState<_ZonesPartnersView> {
  List<dynamic>? _zones;
  List<dynamic>? _orgs;
  List<dynamic>? _resellers;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final src = ref.read(superAdminRemoteSourceProvider);
    try {
      final results = await Future.wait([
        src.listZones(),
        src.listOrganizations(),
        src.listResellers(),
      ]);
      _zones = results[0] as List<dynamic>;
      _orgs =
          (results[1] as Map<String, dynamic>)['data'] as List<dynamic>?;
      _resellers =
          (results[2] as Map<String, dynamic>)['data'] as List<dynamic>?;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Zones & Partners',
              style: GoogleFonts.nunito(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text('Geographic Zones, Corporate Partners & Resellers',
              style: GoogleFonts.dmSans(
                  fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          if (_zones != null)
            DataTableCard(
              title: 'Zones',
              columns: const ['Name', 'City', 'Radius (KM)', 'Status'],
              rows: _zones!
                  .map((z) => [
                        CellText('${z['name']}', bold: true),
                        CellText('${z['city']}'),
                        CellText(
                            '${(z['radius_km'] as num?)?.toStringAsFixed(1) ?? '0'}'),
                        StatusBadge(
                            status: z['is_active'] == true
                                ? 'active'
                                : 'pending'),
                      ])
                  .toList(),
              onRefresh: _load,
            ),
          const SizedBox(height: 24),
          if (_orgs != null)
            DataTableCard(
              title: 'Corporate Partners',
              columns: const [
                'Name', 'Contact', 'Wallet (BDT)', 'Status'
              ],
              rows: (_orgs ?? [])
                  .map((o) => [
                        CellText('${o['name']}', bold: true),
                        CellText('${o['contact_name'] ?? '-'}'),
                        CellText(
                            '${((o['wallet_balance_paisa'] as num?) ?? 0) / 100}'),
                        StatusBadge(
                            status: o['is_active'] == true
                                ? 'active'
                                : 'cancelled'),
                      ])
                  .toList(),
            ),
          const SizedBox(height: 24),
          if (_resellers != null)
            DataTableCard(
              title: 'Resellers / Franchisees',
              columns: const [
                'Name', 'Commission %', 'Earned (BDT)', 'Pitches', 'Status'
              ],
              rows: (_resellers ?? [])
                  .map((r) => [
                        CellText('${r['name']}', bold: true),
                        CellText('${r['commission_percent']}%'),
                        CellText(
                            '${((r['total_earned_paisa'] as num?) ?? 0) / 100}'),
                        CellText('${r['active_pitches_count'] ?? 0}'),
                        StatusBadge(
                            status: r['is_active'] == true
                                ? 'active'
                                : 'cancelled'),
                      ])
                  .toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Turf Onboarding
// ─────────────────────────────────────────────────────────────────────────────
class _TurfOnboardingView extends ConsumerStatefulWidget {
  const _TurfOnboardingView();
  @override
  ConsumerState<_TurfOnboardingView> createState() =>
      _TurfOnboardingViewState();
}

class _TurfOnboardingViewState extends ConsumerState<_TurfOnboardingView> {
  List<dynamic> _pitches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp =
          await ref.read(adminRemoteSourceProvider).listPitches(limit: 100);
      _pitches = resp['data'] as List<dynamic>? ?? [];
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(String id, bool active) async {
    try {
      await ref.read(adminRemoteSourceProvider).togglePitch(id, !active);
      _load();
    } catch (_) {}
  }

  Future<void> _showOnboardDialog() async {
    final nameCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final capacityCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final imageCtrl = TextEditingController();
    String surface = 'artificial';
    String? selectedManagerId;
    String? selectedManagerLabel;
    String? error;
    bool busy = false;
    // Default centered on Chittagong — most owners onboarding first will
    // be there, and even if they're elsewhere the visible map is faster
    // to scroll than typing coordinates.
    LatLng pickedLatLng = const LatLng(22.3569, 91.7832);
    final mapCtrl = MapController();

    // Pre-load managers so the dropdown is populated when the dialog opens.
    // We snapshot once — managers added after this call won't appear until
    // the dialog is reopened (acceptable for an admin tool).
    List<Map<String, dynamic>> managers = [];
    try {
      final list = await ref
          .read(superAdminRemoteSourceProvider)
          .listManagers();
      managers = list.cast<Map<String, dynamic>>();
    } catch (_) {}

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          backgroundColor: const Color(0xFF0A1F1A),
          title: Text(
            'Onboard new turf',
            style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DialogField(
                      controller: nameCtrl, label: 'Pitch name'),
                  const SizedBox(height: 12),
                  _DialogField(
                      controller: addressCtrl, label: 'Street address'),
                  const SizedBox(height: 12),
                  _DialogField(controller: cityCtrl, label: 'City'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _DialogField(
                            controller: priceCtrl,
                            label: 'Price per hour (BDT)',
                            keyboardType: TextInputType.number),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DialogField(
                            controller: capacityCtrl,
                            label: 'Capacity (players)',
                            keyboardType: TextInputType.number),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Surface',
                      style: GoogleFonts.dmSans(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF051210),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primaryDeep),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: surface,
                        dropdownColor: const Color(0xFF0A1F1A),
                        icon: const Icon(Icons.keyboard_arrow_down,
                            color: AppColors.textSecondary, size: 18),
                        style: GoogleFonts.dmSans(
                            fontSize: 13, color: AppColors.textPrimary),
                        onChanged: (v) {
                          if (v != null) setDs(() => surface = v);
                        },
                        items: const ['artificial', 'grass', 'futsal']
                            .map((s) =>
                                DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DialogField(
                      controller: descCtrl,
                      label: 'Description (optional)',
                      maxLines: 3),
                  const SizedBox(height: 12),
                  _DialogField(
                      controller: imageCtrl,
                      label: 'Banner image URL (optional)'),
                  const SizedBox(height: 16),
                  // ── Location picker. Tap on the map to drop a marker at
                  // the venue's coordinates. We pre-fill with Chittagong.
                  Text('Location',
                      style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                  const SizedBox(height: 6),
                  Text(
                      'Tap on the map to mark the pitch entrance. Drag the map to scroll, scroll to zoom.',
                      style: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Container(
                    height: 240,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primaryDeep),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: FlutterMap(
                        mapController: mapCtrl,
                        options: MapOptions(
                          initialCenter: pickedLatLng,
                          initialZoom: 13,
                          onTap: (_, latLng) =>
                              setDs(() => pickedLatLng = latLng),
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.all &
                                ~InteractiveFlag.rotate,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.app.turfinn',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: pickedLatLng,
                                width: 40,
                                height: 40,
                                alignment: Alignment.topCenter,
                                child: const Icon(
                                  Icons.location_on,
                                  color: AppColors.primary,
                                  size: 36,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF051210),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primaryDeep),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.gps_fixed_rounded,
                            size: 14, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              'Lat: ${pickedLatLng.latitude.toStringAsFixed(6)} · Lng: ${pickedLatLng.longitude.toStringAsFixed(6)}',
                              style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  color: AppColors.textPrimary)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ── Manager picker — replaces the old "type a UUID" field
                  Text('Assign to a turf admin',
                      style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                  const SizedBox(height: 6),
                  Text(
                      managers.isEmpty
                          ? "No managers registered yet — register one in the Turf Admins tab first."
                          : 'Pick the manager who'
                              ' will operate this pitch:',
                      style: GoogleFonts.dmSans(
                          fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF051210),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primaryDeep),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: selectedManagerId,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF0A1F1A),
                        hint: Text(
                            managers.isEmpty
                                ? 'No managers available'
                                : 'Unassigned',
                            style: GoogleFonts.dmSans(
                                fontSize: 13,
                                color: AppColors.textSecondary)),
                        icon: const Icon(Icons.keyboard_arrow_down,
                            color: AppColors.textSecondary, size: 18),
                        style: GoogleFonts.dmSans(
                            fontSize: 13, color: AppColors.textPrimary),
                        onChanged: managers.isEmpty
                            ? null
                            : (v) {
                                final m = managers.firstWhere(
                                    (e) => (e['id'] as String?) == v,
                                    orElse: () => const {});
                                setDs(() {
                                  selectedManagerId = v;
                                  final n = (m['name'] as String?) ?? '';
                                  final p = (m['phone'] as String?) ?? '';
                                  selectedManagerLabel =
                                      n.isEmpty ? p : '$n · $p';
                                });
                              },
                        items: [
                          const DropdownMenuItem<String?>(
                              value: null, child: Text('Unassigned')),
                          ...managers.map((m) {
                            final n = (m['name'] as String?) ?? '';
                            final p = (m['phone'] as String?) ?? '';
                            final label = n.isEmpty ? p : '$n · $p';
                            return DropdownMenuItem<String?>(
                                value: m['id'] as String?,
                                child: Text(label,
                                    overflow: TextOverflow.ellipsis));
                          }),
                        ],
                      ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!,
                        style: GoogleFonts.dmSans(
                            fontSize: 12, color: Colors.redAccent)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary))),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.background),
              onPressed: busy
                  ? null
                  : () async {
                      // Front-end validation with visible error so users
                      // know exactly what's missing instead of staring at
                      // an inert button.
                      if (nameCtrl.text.trim().isEmpty) {
                        setDs(() => error = 'Pitch name is required.');
                        return;
                      }
                      if (cityCtrl.text.trim().isEmpty) {
                        setDs(() => error = 'City is required.');
                        return;
                      }
                      final price = double.tryParse(priceCtrl.text) ?? 0;
                      if (price <= 0) {
                        setDs(() =>
                            error = 'Enter a positive price per hour.');
                        return;
                      }
                      setDs(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final data = <String, dynamic>{
                          'name': nameCtrl.text.trim(),
                          'address': addressCtrl.text.trim(),
                          'city': cityCtrl.text.trim(),
                          'price_per_hour': price,
                          'capacity': int.tryParse(capacityCtrl.text) ?? 0,
                          'surface': surface,
                          'description': descCtrl.text.trim(),
                          'image_url': imageCtrl.text.trim(),
                          'latitude': pickedLatLng.latitude,
                          'longitude': pickedLatLng.longitude,
                          if (selectedManagerId != null)
                            'owner_id': selectedManagerId,
                        };
                        await ref
                            .read(adminRemoteSourceProvider)
                            .createPitch(data);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setDs(() {
                          busy = false;
                          error = 'Could not onboard: $e';
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Text('Onboard turf',
                      style: GoogleFonts.dmSans(
                          fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    if (result == true) _load();
    // Suppress unused-var lint (label is rendered inline in the dropdown
    // selection but read again here as a no-op for analyzer's sake).
    selectedManagerLabel;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    final total = _pitches.length;
    final active = _pitches.where((p) => p['is_active'] == true).length;
    final pending = total - active;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _PageHeader(
                  title: 'Turf Onboarding',
                  subtitle: 'Onboard and manage turf facilities',
                ),
              ),
              _ActionButton(
                label: 'Onboard New Turf',
                color: AppColors.primary,
                onTap: _showOnboardDialog,
              ),
            ],
          ),
          const SizedBox(height: 24),
          LayoutBuilder(builder: (ctx, box) {
            final w = (box.maxWidth - 2 * 16) / 3;
            return Row(
              children: [
                SizedBox(
                    width: w,
                    child: StatCard(
                        label: 'Total Turfs',
                        value: '$total',
                        icon: Icons.stadium_rounded,
                        iconColor: AppColors.primary)),
                const SizedBox(width: 16),
                SizedBox(
                    width: w,
                    child: StatCard(
                        label: 'Active Turfs',
                        value: '$active',
                        icon: Icons.check_circle_rounded,
                        iconColor: Colors.greenAccent)),
                const SizedBox(width: 16),
                SizedBox(
                    width: w,
                    child: StatCard(
                        label: 'Pending Review',
                        value: '$pending',
                        icon: Icons.hourglass_top_rounded,
                        iconColor: Colors.orangeAccent)),
              ],
            );
          }),
          const SizedBox(height: 24),
          DataTableCard(
            title: 'All Turfs ($total)',
            columns: const [
              'Name', 'City', 'Price/hr', 'Surface', 'Owner', 'Status',
              'Actions'
            ],
            onRefresh: _load,
            rows: _pitches.map((p) {
              final m = p as Map<String, dynamic>;
              final active = m['is_active'] == true;
              final ownerId = m['owner_id'] as String?;
              final ownerDisplay = ownerId != null && ownerId.length >= 8
                  ? ownerId.substring(0, 8)
                  : ownerId ?? 'Unassigned';
              return [
                CellText(m['name'] ?? '', bold: true),
                CellText(m['city'] ?? ''),
                CellText('${m['price_per_hour'] ?? 0} BDT'),
                CellText(m['surface'] ?? ''),
                CellText(ownerDisplay),
                StatusBadge(status: active ? 'active' : 'inactive'),
                _ActionButton(
                  label: active ? 'Deactivate' : 'Activate',
                  color: active ? Colors.redAccent : AppColors.primary,
                  onTap: () => _toggle(m['id'], active),
                ),
              ];
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String label;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF051210),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primaryDeep),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared panel widgets
// ─────────────────────────────────────────────────────────────────────────────
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.nunito(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: GoogleFonts.dmSans(
                fontSize: 14, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _PanelSearchField extends StatelessWidget {
  const _PanelSearchField(
      {required this.controller, required this.hint, this.onSubmit});
  final TextEditingController controller;
  final String hint;
  final void Function(String)? onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFF051210),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primaryDeep),
      ),
      child: TextField(
        controller: controller,
        onSubmitted: onSubmit,
        style:
            GoogleFonts.dmSans(fontSize: 14, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.dmSans(
              fontSize: 14, color: AppColors.textSecondary),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          prefixIcon: const Icon(Icons.search,
              color: AppColors.textSecondary, size: 18),
        ),
      ),
    );
  }
}

class _PanelDropdown extends StatelessWidget {
  const _PanelDropdown(
      {required this.value,
      required this.hint,
      required this.items,
      required this.onChanged});
  final String? value;
  final String hint;
  final List<String> items;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF051210),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primaryDeep),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint,
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: AppColors.textSecondary)),
          dropdownColor: const Color(0xFF0A1F1A),
          icon: const Icon(Icons.keyboard_arrow_down,
              color: AppColors.textSecondary, size: 18),
          style: GoogleFonts.dmSans(
              fontSize: 13, color: AppColors.textPrimary),
          onChanged: onChanged,
          items: [
            DropdownMenuItem(
                value: null,
                child: Text(hint,
                    style: GoogleFonts.dmSans(
                        fontSize: 13, color: AppColors.textSecondary))),
            ...items.map((i) => DropdownMenuItem(value: i, child: Text(i))),
          ],
        ),
      ),
    );
  }
}

class _RoleDropdown extends StatelessWidget {
  const _RoleDropdown({required this.current, required this.onChanged});
  final String current;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF051210),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primaryDeep),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: current,
          dropdownColor: const Color(0xFF0A1F1A),
          icon: const Icon(Icons.keyboard_arrow_down,
              color: AppColors.textSecondary, size: 14),
          isDense: true,
          style: GoogleFonts.dmSans(
              fontSize: 12, color: AppColors.textPrimary),
          onChanged: (v) {
            if (v != null && v != current) onChanged(v);
          },
          items: ['player', 'manager', 'admin']
              .map((r) => DropdownMenuItem(value: r, child: Text(r)))
              .toList(),
        ),
      ),
    );
  }
}

class _PlanRateCell extends StatelessWidget {
  const _PlanRateCell({required this.p});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    final plan = p['plan'] as String? ?? 'marketplace';
    final isErp = plan == 'erp_only';
    final effectiveBps = (p['effective_commission_bps'] as num?)?.toInt() ?? 0;
    final pct = (effectiveBps / 100).toStringAsFixed(effectiveBps % 100 == 0 ? 0 : 2);
    final boost = p['marketing_boost_active'] == true;
    final premiumIso = p['premium_active_until'] as String?;
    final premiumDt = premiumIso == null ? null : DateTime.tryParse(premiumIso)?.toLocal();
    final premiumActive = premiumDt != null && premiumDt.isAfter(DateTime.now());
    final trialIso = p['trial_ends_at'] as String?;
    final trialDt = trialIso == null ? null : DateTime.tryParse(trialIso)?.toLocal();
    final trialActive = trialDt != null && trialDt.isAfter(DateTime.now());

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(isErp ? 'ERP only' : '$pct%',
          style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary)),
      const SizedBox(height: 4),
      Wrap(spacing: 4, runSpacing: 4, children: [
        if (trialActive) const _MiniBadge(label: 'Trial', color: Colors.orangeAccent),
        if (premiumActive) const _MiniBadge(label: 'Premium', color: AppColors.primary),
        if (boost) const _MiniBadge(label: 'Boost', color: Colors.amber),
      ]),
    ]);
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(
      {required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
              fontSize: 11, fontWeight: FontWeight.w600, color: color),
        ),
      ),
    );
  }
}

class _BookingActions extends StatelessWidget {
  const _BookingActions(
      {required this.status,
      this.onConfirm,
      this.onCancel,
      this.onComplete});
  final String status;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: [
        if (status == 'pending')
          _ActionButton(
              label: 'Confirm',
              color: AppColors.primary,
              onTap: onConfirm ?? () {}),
        if (status == 'confirmed')
          _ActionButton(
              label: 'Complete',
              color: Colors.blueAccent,
              onTap: onComplete ?? () {}),
        if (status != 'cancelled' && status != 'completed')
          _ActionButton(
              label: 'Cancel',
              color: Colors.redAccent,
              onTap: onCancel ?? () {}),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Match Payments — refund queue
// ─────────────────────────────────────────────────────────────────────────────
class _MatchPaymentsView extends ConsumerStatefulWidget {
  const _MatchPaymentsView();
  @override
  ConsumerState<_MatchPaymentsView> createState() =>
      _MatchPaymentsViewState();
}

class _MatchPaymentsViewState extends ConsumerState<_MatchPaymentsView> {
  List<dynamic> _rows = [];
  int _total = 0;
  bool _loading = true;
  String _refundFilter = 'any'; // any | requested | refunded | refund_failed
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(superAdminRemoteSourceProvider).listMatchPayments(
            refundStatus: _refundFilter,
            q: _searchCtrl.text.trim(),
            limit: 50,
          );
      _rows = (data['data'] as List<dynamic>?) ?? [];
      _total = ((data['meta'] as Map?)?['total'] as int?) ?? 0;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _retry(String id) async {
    try {
      await ref.read(superAdminRemoteSourceProvider).retryMatchRefund(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Refund re-queued. Cron will pick it up shortly.')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Retry failed: $e'),
          backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _markRefunded(String id) async {
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          backgroundColor: const Color(0xFF0A1F1A),
          title: const Text('Manual refund override',
              style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: c,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Operator note (optional)',
              labelStyle: TextStyle(color: Colors.white70),
              hintText: 'e.g. settled via SSL portal — ref ABC123',
              hintStyle: TextStyle(color: Colors.white38),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, c.text),
                child: const Text('Mark refunded')),
          ],
        );
      },
    );
    if (note == null) return;
    try {
      await ref
          .read(superAdminRemoteSourceProvider)
          .markMatchRefunded(id, note: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marked as refunded.')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Override failed: $e'),
          backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
              title: 'Match Payments',
              subtitle: 'Refund queue, retries & manual overrides'),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  value: _refundFilter,
                  dropdownColor: const Color(0xFF0A1F1A),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Refund status',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'any', child: Text('Any refund row')),
                    DropdownMenuItem(value: 'requested', child: Text('Requested')),
                    DropdownMenuItem(value: 'refunded', child: Text('Refunded')),
                    DropdownMenuItem(
                        value: 'refund_failed', child: Text('Refund failed')),
                    DropdownMenuItem(value: '', child: Text('All payments')),
                  ],
                  onChanged: (v) {
                    setState(() => _refundFilter = v ?? 'any');
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _searchCtrl,
                  onSubmitted: (_) => _load(),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Search user / phone / tran_id / match',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search, color: Colors.white70),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Apply'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary)))
          else
            DataTableCard(
              title: 'Refund queue ($_total total)',
              columns: const [
                'Match',
                'User',
                'Amount',
                'Refund',
                'Attempts',
                'Last error',
                'Actions',
              ],
              onRefresh: _load,
              rows: _rows.map((e) {
                final m = e as Map<String, dynamic>;
                final amount = ((m['amount_paisa'] as num?)?.toInt() ?? 0) / 100;
                final refundStatus = (m['refund_status'] as String?) ?? '—';
                final id = m['id'] as String;
                return [
                  CellText(m['match_title'] ?? '', bold: true),
                  CellText(
                      '${m['user_name'] ?? ''}\n${m['user_phone'] ?? ''}'),
                  CellText('${amount.toStringAsFixed(2)} BDT'),
                  StatusBadge(status: refundStatus),
                  CellText('${m['refund_attempts'] ?? 0}'),
                  CellText(m['last_refund_error'] ?? '—'),
                  Wrap(spacing: 6, children: [
                    if (refundStatus == 'refund_failed' ||
                        refundStatus == 'requested')
                      _ActionButton(
                          label: 'Retry',
                          color: AppColors.primary,
                          onTap: () => _retry(id)),
                    if (refundStatus != 'refunded')
                      _ActionButton(
                          label: 'Manual mark refunded',
                          color: const Color(0xFFFFC857),
                          onTap: () => _markRefunded(id)),
                  ]),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Match Cancellations — audit log
// ─────────────────────────────────────────────────────────────────────────────
class _MatchCancellationsView extends ConsumerStatefulWidget {
  const _MatchCancellationsView();
  @override
  ConsumerState<_MatchCancellationsView> createState() =>
      _MatchCancellationsViewState();
}

class _MatchCancellationsViewState
    extends ConsumerState<_MatchCancellationsView> {
  List<dynamic> _rows = [];
  int _total = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref
          .read(superAdminRemoteSourceProvider)
          .listMatchCancellations(limit: 50);
      _rows = (data['data'] as List<dynamic>?) ?? [];
      _total = ((data['meta'] as Map?)?['total'] as int?) ?? 0;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _short(dynamic d) {
    if (d == null) return '—';
    final s = d.toString();
    return s.length >= 16 ? s.substring(0, 16).replaceAll('T', ' ') : s;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
              title: 'Match Cancellations',
              subtitle: 'Cancelled matches with refund roll-up'),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary)))
          else
            DataTableCard(
              title: 'Cancellations ($_total total)',
              columns: const [
                'Match',
                'Host',
                'Pitch',
                'Kickoff',
                'Cancelled at',
                'Reason',
                'Joiners',
                'Refunds',
              ],
              onRefresh: _load,
              rows: _rows.map((e) {
                final m = e as Map<String, dynamic>;
                final req = (m['refunds_requested'] as num?)?.toInt() ?? 0;
                final done = (m['refunds_completed'] as num?)?.toInt() ?? 0;
                final fail = (m['refunds_failed'] as num?)?.toInt() ?? 0;
                final pending = req - done - fail;
                return [
                  CellText(m['title'] ?? '', bold: true),
                  CellText(m['host_name'] ?? ''),
                  CellText(m['pitch_name'] ?? ''),
                  CellText(_short(m['match_date'])),
                  CellText(_short(m['cancelled_at'])),
                  CellText(m['cancellation_reason'] ?? ''),
                  CellText('${m['joiner_count'] ?? 0}'),
                  CellText('$done done · $pending pending · $fail failed'),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Turf Admins — register new managers
// ─────────────────────────────────────────────────────────────────────────────
class _TurfAdminsView extends ConsumerStatefulWidget {
  const _TurfAdminsView();
  @override
  ConsumerState<_TurfAdminsView> createState() => _TurfAdminsViewState();
}

class _TurfAdminsViewState extends ConsumerState<_TurfAdminsView> {
  List<dynamic> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = await ref.read(superAdminRemoteSourceProvider).listManagers();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _showAddDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String? error;
    bool busy = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF0A1F1A),
          title: Text('Register turf admin',
              style: GoogleFonts.nunito(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    "They'll log in via OTP at the manager panel using this phone number.",
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    labelStyle: TextStyle(color: Colors.white70),
                    hintText: '+8801XXXXXXXXX',
                    hintStyle: TextStyle(color: Colors.white30),
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      style: GoogleFonts.dmSans(
                          fontSize: 12, color: Colors.redAccent)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: busy
                    ? null
                    : () async {
                        final name = nameCtrl.text.trim();
                        final phone = phoneCtrl.text.trim();
                        if (name.isEmpty || phone.isEmpty) {
                          setS(() => error = 'Both fields are required.');
                          return;
                        }
                        setS(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await ref
                              .read(superAdminRemoteSourceProvider)
                              .createManager(name: name, phone: phone);
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          setS(() {
                            busy = false;
                            error = 'Could not register: $e';
                          });
                        }
                      },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black),
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Text('Register')),
          ],
        ),
      ),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PageHeader(
                    title: 'Turf Admins',
                    subtitle:
                        'Register new managers — they log in via OTP at the manager panel.'),
              ),
              ElevatedButton.icon(
                onPressed: _showAddDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add manager'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary)))
          else
            DataTableCard(
              title: 'Managers (${_rows.length})',
              columns: const ['Name', 'Phone', 'Role', 'Created'],
              onRefresh: _load,
              rows: _rows.map((e) {
                final m = e as Map<String, dynamic>;
                return [
                  CellText(m['name'] ?? '', bold: true),
                  CellText(m['phone'] ?? ''),
                  StatusBadge(status: m['role'] ?? 'manager'),
                  CellText(((m['created_at'] as String?) ?? '')
                      .replaceAll('T', ' ')
                      .substring(0,
                          (m['created_at'] as String?)?.length.clamp(0, 16) ??
                              0)),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Activation toggle button (used in Users table)
// ─────────────────────────────────────────────────────────────────────────────
class _ActivationButton extends StatelessWidget {
  const _ActivationButton({required this.isActive, required this.onChange});
  final bool isActive;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    if (isActive) {
      return OutlinedButton.icon(
        onPressed: () => onChange(false),
        icon: const Icon(Icons.block_rounded, size: 14),
        label: Text('Deactivate', style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFFF6B6B),
          side: BorderSide(color: const Color(0xFFFF6B6B).withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: const Size(0, 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: () => onChange(true),
      icon: const Icon(Icons.check_rounded, size: 14),
      label: Text('Reactivate', style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: const Size(0, 32),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _LockedAction extends StatelessWidget {
  const _LockedAction({required this.tooltip});
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded,
              size: 14,
              color: AppColors.textSecondary.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Text('Locked',
              style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: AppColors.textSecondary.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}
