import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/geocoding_service.dart';
import '../../../data/sources/remote/manage_remote_source.dart';
import '../panel/widgets/panel_scaffold.dart';
import '../panel/widgets/stat_card.dart';
import '../panel/widgets/data_table_card.dart';
import 'widgets/billing_view.dart';
import 'widgets/premium_gate_view.dart';

class ManagePanelScreen extends ConsumerStatefulWidget {
  const ManagePanelScreen({super.key});

  @override
  ConsumerState<ManagePanelScreen> createState() => _ManagePanelScreenState();
}

class _ManagePanelScreenState extends ConsumerState<ManagePanelScreen> {
  int _selectedIdx = 0;

  // Sidebar order is intentional: daily-ops first, then operational tools,
  // then strategic / reporting. New owners landing on the panel see
  // "Today" first — the most actionable view.
  static const _navItems = [
    PanelNavItem(icon: Icons.today_rounded, label: 'Today'),
    PanelNavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    PanelNavItem(icon: Icons.calendar_month_rounded, label: 'Bookings'),
    PanelNavItem(icon: Icons.event_note_rounded, label: 'My Bookings'),
    PanelNavItem(icon: Icons.stadium_rounded, label: 'My Pitches'),
    PanelNavItem(icon: Icons.analytics_rounded, label: 'Analytics Pro'),
    PanelNavItem(icon: Icons.account_balance_rounded, label: 'Financials Pro'),
    PanelNavItem(icon: Icons.dynamic_feed_rounded, label: 'Smart Pricing'),
    PanelNavItem(icon: Icons.campaign_rounded, label: 'Campaigns'),
    PanelNavItem(icon: Icons.event_busy_rounded, label: 'Match Cancellations'),
    PanelNavItem(icon: Icons.receipt_long_rounded, label: 'Billing'),
  ];

  @override
  Widget build(BuildContext context) {
    return PanelScaffold(
      title: 'Turf Manager',
      items: _navItems,
      selectedIndex: _selectedIdx,
      onItemTap: (i) => setState(() => _selectedIdx = i),
      body: IndexedStack(
        index: _selectedIdx,
        children: const [
          _TodayView(),
          _ManagerDashboard(),
          _ManagerBookingsView(),
          _MyBookingsEnhancedView(),
          _MyPitchesView(),
          PremiumGateView(
            featureName: 'Analytics Pro',
            featureBlurb:
                'Heatmaps, peak-hour pricing, customer LTV, and per-pitch breakdowns. The numbers your accountant actually asks for.',
            child: _AnalyticsProView(),
          ),
          PremiumGateView(
            featureName: 'Financials Pro',
            featureBlurb:
                'Daily P&L, VAT-ready report, owner ledger export. Cuts month-end paperwork from a day to ten minutes.',
            child: _FinancialsProView(),
          ),
          PremiumGateView(
            featureName: 'Smart Pricing',
            featureBlurb:
                'Charge more during peak slots, less during cold ones. Rules engine you control — no app calls needed.',
            child: _SmartPricingView(),
          ),
          PremiumGateView(
            featureName: 'Campaigns',
            featureBlurb:
                'Run promo codes and broadcast SMS to drive bookings on slow days. Track ROI per campaign.',
            child: _CampaignsView(),
          ),
          _ManagerMatchCancellationsView(),
          BillingView(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard
// ─────────────────────────────────────────────────────────────────────────────
class _ManagerDashboard extends ConsumerStatefulWidget {
  const _ManagerDashboard();
  @override
  ConsumerState<_ManagerDashboard> createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends ConsumerState<_ManagerDashboard> {
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
      _stats = await ref.read(manageRemoteSourceProvider).getDashboard();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));

    final s = _stats ?? {};
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dashboard', style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Your turf business at a glance', style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          LayoutBuilder(builder: (ctx, box) {
            final cols = box.maxWidth > 800 ? 3 : 2;
            final w = (box.maxWidth - (cols - 1) * 16) / cols;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(width: w, child: StatCard(label: 'My Pitches', value: '${s['total_pitches'] ?? 0}', icon: Icons.stadium, iconColor: AppColors.primary)),
                SizedBox(width: w, child: StatCard(label: 'Total Bookings', value: '${s['total_bookings'] ?? 0}', icon: Icons.calendar_month, iconColor: Colors.blueAccent)),
                SizedBox(width: w, child: StatCard(label: 'Revenue (BDT)', value: _fmt(s['total_revenue']), icon: Icons.payments, iconColor: AppColors.primary)),
                SizedBox(width: w, child: StatCard(label: 'Today\'s Bookings', value: '${s['today_bookings'] ?? 0}', icon: Icons.today, iconColor: Colors.orangeAccent)),
                SizedBox(width: w, child: StatCard(label: 'Upcoming', value: '${s['upcoming_bookings'] ?? 0}', icon: Icons.upcoming, iconColor: Colors.purpleAccent)),
                // Cash collection — the operational KPI that matters under
                // the partial-payment model. If this number is rising, the
                // owner has uncollected money sitting on the calendar.
                SizedBox(width: w, child: StatCard(label: 'Cash to collect', value: '${_fmt(s['cash_to_collect_bdt'] ?? 0)} BDT', icon: Icons.payments_outlined, iconColor: const Color(0xFFFFC857))),
              ],
            );
          }),
        ],
      ),
    );
  }

  String _fmt(dynamic v) {
    if (v == null) return '0';
    final n = (v is int) ? v.toDouble() : (v as double);
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My Pitches (CRUD)
// ─────────────────────────────────────────────────────────────────────────────
class _MyPitchesView extends ConsumerStatefulWidget {
  const _MyPitchesView();
  @override
  ConsumerState<_MyPitchesView> createState() => _MyPitchesViewState();
}

class _MyPitchesViewState extends ConsumerState<_MyPitchesView> {
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
      _pitches = await ref.read(manageRemoteSourceProvider).listMyPitches();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openWhatsApp() async {
    final url = Uri.parse(
        'https://wa.me/8801700000000?text=${Uri.encodeComponent("Hi Turfinn, I'd like to register a new pitch.")}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Pitches',
              style: GoogleFonts.nunito(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Inventory of pitches Turfinn has registered for you',
              style: GoogleFonts.dmSans(
                  fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          // ── "Need a new pitch?" CTA — replaces the in-app create flow.
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.18),
                  AppColors.primary.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.5),
                  width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.add_business_rounded,
                      color: Colors.black, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Need to register a new turf?',
                          style: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Text(
                          'Contact Turfinn — we verify the venue + add it to your inventory in 24 hours.',
                          style: GoogleFonts.dmSans(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              height: 1.4)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                  ),
                  onPressed: _openWhatsApp,
                  icon: const Icon(Icons.chat_rounded, size: 18),
                  label: Text('Contact us',
                      style: GoogleFonts.dmSans(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_loading)
            const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
          else if (_pitches.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(60),
                child: Column(
                  children: [
                    Icon(Icons.stadium,
                        size: 64,
                        color:
                            AppColors.textSecondary.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    Text('No pitches yet',
                        style: GoogleFonts.nunito(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    Text(
                        'Turfinn will register your first pitch — tap "Contact us" above.',
                        style: GoogleFonts.dmSans(
                            fontSize: 14, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            )
          else
            DataTableCard.rich(
              title: 'Pitches (${_pitches.length})',
              columns: const [
                TableColumn('Name', flex: 4),
                TableColumn('City', flex: 3),
                TableColumn('Price / hr', flex: 2, alignRight: true),
                TableColumn('Capacity', flex: 2, alignRight: true),
                TableColumn('Status', flex: 2),
              ],
              onRefresh: _load,
              rows: _pitches.map((p) {
                final m = p as Map<String, dynamic>;
                final active = m['is_active'] == true;
                return [
                  CellText(m['name'] ?? '', bold: true),
                  CellText(m['city'] ?? ''),
                  CellText('${m['price_per_hour'] ?? 0} BDT'),
                  CellText('${m['capacity'] ?? '—'}'),
                  StatusBadge(status: active ? 'active' : 'cancelled'),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bookings for my pitches
// ─────────────────────────────────────────────────────────────────────────────
class _ManagerBookingsView extends ConsumerStatefulWidget {
  const _ManagerBookingsView();
  @override
  ConsumerState<_ManagerBookingsView> createState() => _ManagerBookingsViewState();
}

class _ManagerBookingsViewState extends ConsumerState<_ManagerBookingsView> {
  List<dynamic> _bookings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await ref.read(manageRemoteSourceProvider).listBookings(limit: 50);
      _bookings = resp['data'] as List<dynamic>? ?? [];
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _confirm(String id) async {
    await ref.read(manageRemoteSourceProvider).confirmBooking(id);
    _load();
  }

  Future<void> _cancel(String id) async {
    await ref.read(manageRemoteSourceProvider).cancelBooking(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bookings', style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Bookings across all your pitches', style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: AppColors.primary))
          else
            DataTableCard(
              title: 'All Bookings (${_bookings.length})',
              columns: const ['Pitch', 'Customer', 'Phone', 'Date', 'Cost', 'Status', 'Actions'],
              onRefresh: _load,
              rows: _bookings.map((b) {
                final m = b as Map<String, dynamic>;
                final status = m['status'] ?? '';
                return [
                  CellText(m['pitch_name'] ?? '', bold: true),
                  CellText(m['user_name']?.toString().isNotEmpty == true ? m['user_name'] : '—'),
                  CellText(m['user_phone'] ?? ''),
                  CellText(_shortDT(m['starts_at'])),
                  CellText('${m['total_cost'] ?? 0} BDT'),
                  StatusBadge(status: status),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (status == 'pending')
                        _SmallAction(icon: Icons.check, color: AppColors.primary, onTap: () => _confirm(m['id'])),
                      if (status != 'cancelled' && status != 'completed')
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _SmallAction(icon: Icons.close, color: Colors.redAccent, onTap: () => _cancel(m['id'])),
                        ),
                    ],
                  ),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }

  String _shortDT(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso);
      return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My Analytics (Manager-scoped)
// ─────────────────────────────────────────────────────────────────────────────
class _MyAnalyticsView extends ConsumerStatefulWidget {
  const _MyAnalyticsView();
  @override
  ConsumerState<_MyAnalyticsView> createState() => _MyAnalyticsViewState();
}

class _MyAnalyticsViewState extends ConsumerState<_MyAnalyticsView> {
  Map<String, dynamic>? _summary;
  List<dynamic>? _revenueChart;
  List<dynamic>? _pitchBreakdown;
  bool _loading = true;
  String _period = 'month';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final src = ref.read(manageRemoteSourceProvider);
    try {
      final days = _period == 'today' ? 1 : (_period == 'week' ? 7 : 30);
      final results = await Future.wait([
        src.getManagerSummary(period: _period),
        src.getManagerRevenueChart(days: days),
        src.getManagerPitchBreakdown(period: _period),
      ]);
      _summary = results[0] as Map<String, dynamic>;
      _revenueChart = results[1] as List<dynamic>;
      _pitchBreakdown = results[2] as List<dynamic>;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));

    final s = _summary ?? {};
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Analytics', style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Performance overview for your pitches', style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          Row(children: [
            _PeriodDropdown(value: _period, onChanged: (v) { _period = v; _load(); }),
          ]),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (ctx, box) {
            final cols = box.maxWidth > 900 ? 4 : 2;
            final w = (box.maxWidth - (cols - 1) * 16) / cols;
            return Wrap(
              spacing: 16, runSpacing: 16,
              children: [
                SizedBox(width: w, child: StatCard(label: 'Revenue (BDT)', value: _formatNum(s['revenue']), icon: Icons.payments, iconColor: AppColors.primary)),
                SizedBox(width: w, child: StatCard(label: 'Bookings', value: '${s['bookings'] ?? 0}', icon: Icons.calendar_month, iconColor: Colors.blueAccent)),
                SizedBox(width: w, child: StatCard(label: 'Occupancy', value: '${(s['occupancy'] as num?)?.toStringAsFixed(1) ?? '0'}%', icon: Icons.stadium, iconColor: Colors.orangeAccent)),
                SizedBox(width: w, child: StatCard(label: 'Avg Rating', value: (s['avg_rating'] as num?)?.toStringAsFixed(1) ?? '—', icon: Icons.star, iconColor: Colors.amber)),
              ],
            );
          }),
          const SizedBox(height: 24),
          if (_revenueChart != null && _revenueChart!.isNotEmpty)
            DataTableCard(
              title: 'Daily Revenue',
              columns: const ['Date', 'Amount (BDT)'],
              onRefresh: _load,
              rows: _revenueChart!.map((d) {
                final m = d as Map<String, dynamic>;
                return [CellText('${m['date'] ?? ''}'), CellText('${m['amount'] ?? 0}', bold: true)];
              }).toList(),
            ),
          const SizedBox(height: 24),
          if (_pitchBreakdown != null && _pitchBreakdown!.isNotEmpty)
            DataTableCard(
              title: 'Per-Pitch Breakdown',
              columns: const ['Pitch', 'Bookings', 'Revenue', 'Occupancy %', 'Avg Rating'],
              onRefresh: _load,
              rows: _pitchBreakdown!.map((p) {
                final m = p as Map<String, dynamic>;
                return [
                  CellText('${m['pitch_name'] ?? ''}', bold: true),
                  CellText('${m['bookings'] ?? 0}'),
                  CellText('${m['revenue'] ?? 0} BDT'),
                  CellText('${(m['occupancy'] as num?)?.toStringAsFixed(1) ?? '0'}%'),
                  CellText('${(m['avg_rating'] as num?)?.toStringAsFixed(1) ?? '—'}'),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }

  String _formatNum(dynamic v) {
    if (v == null) return '0';
    final n = (v is int) ? v.toDouble() : (v as num).toDouble();
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My Bookings Enhanced (Manager-scoped with filters + walk-in)
// ─────────────────────────────────────────────────────────────────────────────
class _MyBookingsEnhancedView extends ConsumerStatefulWidget {
  const _MyBookingsEnhancedView();
  @override
  ConsumerState<_MyBookingsEnhancedView> createState() => _MyBookingsEnhancedViewState();
}

class _MyBookingsEnhancedViewState extends ConsumerState<_MyBookingsEnhancedView> {
  List<dynamic> _bookings = [];
  bool _loading = true;
  String? _statusFilter;
  String? _sourceFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await ref.read(manageRemoteSourceProvider).getManagerBookings(
        limit: 50, status: _statusFilter, source: _sourceFilter,
      );
      _bookings = resp['data'] as List<dynamic>? ?? [];
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setStatus(String id, String status) async {
    try {
      await ref.read(manageRemoteSourceProvider).updateManagerBookingStatus(id, status);
      _load();
    } catch (_) {}
  }

  Future<void> _markCashCollected(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1F1A),
        title: Text('Confirm cash collected',
            style: GoogleFonts.nunito(
                color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
        content: Text(
            'Mark this booking\'s cash share as collected at the venue. '
            'This is irreversible — only confirm after physically receiving the money.',
            style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC857),
                  foregroundColor: Colors.black),
              child: const Text('Confirm collected')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(manageRemoteSourceProvider).markCashCollected(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cash marked as collected.')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not mark collected: $e'),
          backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _showWalkInDialog() async {
    final pitchIdCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    final startCtrl = TextEditingController();
    final endCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String paymentMethod = 'cash';
    String? error;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0A1F1A),
          title: Text('Add Walk-in Booking', style: GoogleFonts.nunito(color: AppColors.textPrimary)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WalkInField(controller: pitchIdCtrl, label: 'Pitch ID (UUID)'),
                  const SizedBox(height: 10),
                  _WalkInField(controller: dateCtrl, label: 'Date (YYYY-MM-DD)'),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _WalkInField(controller: startCtrl, label: 'Start (HH:mm)')),
                    const SizedBox(width: 10),
                    Expanded(child: _WalkInField(controller: endCtrl, label: 'End (HH:mm)')),
                  ]),
                  const SizedBox(height: 10),
                  _WalkInField(controller: nameCtrl, label: 'Customer name'),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF051210),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.primaryDeep),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: paymentMethod,
                            dropdownColor: const Color(0xFF0A1F1A),
                            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textPrimary),
                            icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary, size: 18),
                            onChanged: (v) => setDialogState(() => paymentMethod = v ?? 'cash'),
                            items: ['cash', 'card', 'transfer'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _WalkInField(controller: amountCtrl, label: 'Amount (BDT)')),
                  ]),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (pitchIdCtrl.text.isEmpty || dateCtrl.text.isEmpty ||
                    startCtrl.text.isEmpty || endCtrl.text.isEmpty ||
                    nameCtrl.text.isEmpty || amountCtrl.text.isEmpty) {
                  setDialogState(() => error = 'All fields are required');
                  return;
                }
                final amount = double.tryParse(amountCtrl.text);
                if (amount == null) {
                  setDialogState(() => error = 'Invalid amount');
                  return;
                }
                try {
                  await ref.read(manageRemoteSourceProvider).createWalkInBooking({
                    'pitch_id': pitchIdCtrl.text.trim(),
                    'starts_at': '${dateCtrl.text.trim()}T${startCtrl.text.trim()}:00Z',
                    'ends_at': '${dateCtrl.text.trim()}T${endCtrl.text.trim()}:00Z',
                    'customer_name': nameCtrl.text.trim(),
                    'payment_method': paymentMethod,
                    'payment_amount': amount,
                  });
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  setDialogState(() => error = 'Failed to create booking');
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Bookings', style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Manage bookings across your pitches', style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          Row(children: [
            _PeriodDropdown(value: _statusFilter, hint: 'All Statuses', items: const ['pending', 'confirmed', 'cancelled'], onChanged: (v) { _statusFilter = v; _load(); }),
            const SizedBox(width: 12),
            _PeriodDropdown(value: _sourceFilter, hint: 'All Sources', items: const ['turfinn', 'walk_in'], onChanged: (v) { _sourceFilter = v; _load(); }),
            const Spacer(),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              onPressed: _showWalkInDialog,
              icon: const Icon(Icons.add, color: Colors.black, size: 18),
              label: Text('Add Walk-in', style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black)),
            ),
          ]),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: AppColors.primary))
          else
            DataTableCard.rich(
              title: 'Bookings (${_bookings.length})',
              columns: const [
                TableColumn('Pitch', flex: 3),
                TableColumn('Customer', flex: 4),
                TableColumn('Slot', flex: 3),
                TableColumn('Source', flex: 2),
                TableColumn('Cash due', flex: 2, alignRight: true),
                TableColumn('Status', flex: 2),
                TableColumn('Actions', flex: 3, alignRight: true),
              ],
              onRefresh: _load,
              rows: _bookings.map((b) {
                final m = b as Map<String, dynamic>;
                final isWalkIn = m['source'] == 'walk_in';
                final customerName = m['customer_name']?.toString().isNotEmpty == true
                    ? m['customer_name']
                    : (isWalkIn ? 'Walk-in guest' : m['user_id']?.toString().substring(0, 8) ?? '—');
                final customerPhone =
                    (m['customer_phone'] as String?) ?? '';
                final paymentMode = (m['payment_mode'] as String?) ?? 'full_online';
                final cashDuePaisa = (m['cash_due_paisa'] as num?)?.toInt() ?? 0;
                final cashCollectedAt = m['cash_collected_at'] as String?;
                final isPartial = paymentMode == 'partial_online' && cashDuePaisa > 0;
                Widget cashCell;
                if (!isPartial) {
                  cashCell = CellText('—', muted: true);
                } else if (cashCollectedAt != null) {
                  cashCell = StatusBadge(status: 'collected');
                } else {
                  cashCell = CellText(
                      '${(cashDuePaisa / 100).toStringAsFixed(0)} BDT',
                      bold: true);
                }
                return [
                  CellText(m['pitch_name'] ?? '—', bold: true),
                  CellText(
                    customerName,
                    subtitle: customerPhone.isEmpty ? null : customerPhone,
                  ),
                  CellText(_shortDateTime(m['starts_at'])),
                  StatusBadge(status: isWalkIn ? 'walk_in' : 'turfinn'),
                  cashCell,
                  StatusBadge(status: m['status'] ?? ''),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (m['status'] == 'pending')
                      _SmallAction(icon: Icons.check, color: AppColors.primary, onTap: () => _setStatus(m['id'], 'confirmed')),
                    if (isPartial && cashCollectedAt == null)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _SmallAction(
                            icon: Icons.payments_rounded,
                            color: const Color(0xFFFFC857),
                            onTap: () => _markCashCollected(m['id'])),
                      ),
                    if (m['status'] != 'cancelled' && m['status'] != 'completed')
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _SmallAction(icon: Icons.close, color: Colors.redAccent, onTap: () => _setStatus(m['id'], 'cancelled')),
                      ),
                  ]),
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
      return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) { return iso; }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My Financials (Manager-scoped)
// ─────────────────────────────────────────────────────────────────────────────
class _MyFinancialsView extends ConsumerStatefulWidget {
  const _MyFinancialsView();
  @override
  ConsumerState<_MyFinancialsView> createState() => _MyFinancialsViewState();
}

class _MyFinancialsViewState extends ConsumerState<_MyFinancialsView> {
  Map<String, dynamic>? _financials;
  bool _loading = true;
  String _preset = 'month';
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  String? get _from {
    if (_preset == 'custom' && _fromCtrl.text.isNotEmpty) return _fromCtrl.text;
    final now = DateTime.now();
    final days = _preset == 'week' ? 7 : 30;
    final d = now.subtract(Duration(days: days));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String? get _to {
    if (_preset == 'custom' && _toCtrl.text.isNotEmpty) return _toCtrl.text;
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _financials = await ref.read(manageRemoteSourceProvider).getManagerFinancials(from: _from, to: _to);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));

    final f = _financials ?? {};
    final total = (f['total_revenue'] as num?)?.toDouble() ?? 0.0;
    final turfinn = (f['turfinn_revenue'] as num?)?.toDouble() ?? 0.0;
    final walkin = (f['walkin_revenue'] as num?)?.toDouble() ?? 0.0;
    final walkinPct = total > 0 ? (walkin / total * 100) : 0.0;
    final pmList = f['by_payment_method'] as List<dynamic>? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Financials', style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Revenue breakdown for your pitches', style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          Row(children: [
            _PeriodDropdown(value: _preset, items: const ['week', 'month', 'custom'], onChanged: (v) {
              _preset = v; if (v != 'custom') _load();
            }),
            if (_preset == 'custom') ...[
              const SizedBox(width: 12),
              SizedBox(width: 160, child: _WalkInField(controller: _fromCtrl, label: 'From (YYYY-MM-DD)')),
              const SizedBox(width: 8),
              SizedBox(width: 160, child: _WalkInField(controller: _toCtrl, label: 'To (YYYY-MM-DD)')),
              const SizedBox(width: 8),
              _SmallAction(icon: Icons.search, color: AppColors.primary, onTap: _load),
            ],
          ]),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (ctx, box) {
            final cols = box.maxWidth > 900 ? 4 : 2;
            final w = (box.maxWidth - (cols - 1) * 16) / cols;
            return Wrap(
              spacing: 16, runSpacing: 16,
              children: [
                SizedBox(width: w, child: StatCard(label: 'Total Revenue', value: '${total.toStringAsFixed(0)} BDT', icon: Icons.payments, iconColor: AppColors.primary)),
                SizedBox(width: w, child: StatCard(label: 'Turfinn Revenue', value: '${turfinn.toStringAsFixed(0)} BDT', icon: Icons.phone_android, iconColor: Colors.blueAccent)),
                SizedBox(width: w, child: StatCard(label: 'Walk-in Revenue', value: '${walkin.toStringAsFixed(0)} BDT', icon: Icons.store, iconColor: Colors.orangeAccent)),
                SizedBox(width: w, child: StatCard(label: 'Walk-in %', value: '${walkinPct.toStringAsFixed(1)}%', icon: Icons.pie_chart, iconColor: Colors.purpleAccent)),
              ],
            );
          }),
          const SizedBox(height: 24),
          if (pmList.isNotEmpty)
            DataTableCard(
              title: 'Walk-in Payment Methods',
              columns: const ['Method', 'Amount (BDT)', 'Count'],
              onRefresh: _load,
              rows: pmList.map((pm) {
                final m = pm as Map<String, dynamic>;
                return [
                  CellText('${(m['method'] ?? '')[0].toString().toUpperCase()}${(m['method'] ?? '').toString().substring(1)}', bold: true),
                  CellText('${m['amount'] ?? 0}'),
                  CellText('${m['count'] ?? 0}'),
                ];
              }).toList(),
            ),
          if (pmList.isEmpty && total == 0)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(child: Text('No financial data for this period', style: GoogleFonts.dmSans(color: AppColors.textSecondary))),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Smart Pricing
// ─────────────────────────────────────────────────────────────────────────────
class _SmartPricingView extends ConsumerStatefulWidget {
  const _SmartPricingView();
  @override
  ConsumerState<_SmartPricingView> createState() => _SmartPricingViewState();
}

class _SmartPricingViewState extends ConsumerState<_SmartPricingView> {
  List<dynamic> _rules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rules = await ref.read(manageRemoteSourceProvider).listPricingRules();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(String id) async {
    try {
      await ref.read(manageRemoteSourceProvider).togglePricingRule(id);
      _load();
    } catch (_) {}
  }

  Future<void> _delete(String id) async {
    try {
      await ref.read(manageRemoteSourceProvider).deletePricingRule(id);
      _load();
    } catch (_) {}
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (_) => _PricingRuleDialog(
        onSave: (data) async {
          try {
            await ref.read(manageRemoteSourceProvider).createPricingRule(data);
            _load();
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
              );
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Smart Pricing', style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Set dynamic pricing rules for your pitches', style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                onPressed: _showAddDialog,
                icon: const Icon(Icons.add, color: Colors.black, size: 18),
                label: Text('Add Rule', style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: AppColors.primary))
          else if (_rules.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(60),
                child: Column(
                  children: [
                    Icon(Icons.dynamic_feed_rounded, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    Text('No pricing rules yet', style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    Text('Add a rule to apply discounts or surcharges at specific times', style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            )
          else
            DataTableCard(
              title: 'Pricing Rules (${_rules.length})',
              columns: const ['Name', 'Type', 'Multiplier', 'Days', 'Time Range', 'Active', 'Actions'],
              onRefresh: _load,
              rows: _rules.map((r) {
                final m = r as Map<String, dynamic>;
                final active = m['is_active'] == true;
                final timeFrom = m['time_from'] ?? '—';
                final timeTo = m['time_to'] ?? '—';
                final timeRange = (timeFrom == '—' && timeTo == '—') ? '—' : '$timeFrom–$timeTo';
                final multiplier = m['multiplier'];
                final multiplierText = multiplier != null ? '${multiplier}x' : '—';
                return [
                  CellText(m['name'] ?? '', bold: true),
                  CellText(m['rule_type'] ?? m['type'] ?? '—'),
                  CellText(multiplierText),
                  CellText(m['days_of_week'] ?? m['days'] ?? '—'),
                  CellText(timeRange),
                  StatusBadge(status: active ? 'active' : 'cancelled'),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SmallAction(
                        icon: active ? Icons.pause : Icons.play_arrow,
                        color: active ? Colors.orangeAccent : AppColors.primary,
                        onTap: () => _toggle(m['id']),
                      ),
                      const SizedBox(width: 6),
                      _SmallAction(
                        icon: Icons.delete_outline,
                        color: Colors.redAccent,
                        onTap: () => _delete(m['id']),
                      ),
                    ],
                  ),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pricing Rule dialog
// ─────────────────────────────────────────────────────────────────────────────
class _PricingRuleDialog extends StatefulWidget {
  const _PricingRuleDialog({required this.onSave});
  final Future<void> Function(Map<String, dynamic>) onSave;

  @override
  State<_PricingRuleDialog> createState() => _PricingRuleDialogState();
}

class _PricingRuleDialogState extends State<_PricingRuleDialog> {
  final _nameCtrl = TextEditingController();
  final _multiplierCtrl = TextEditingController();
  final _fixedAmountCtrl = TextEditingController();
  final _daysCtrl = TextEditingController();
  final _timeFromCtrl = TextEditingController();
  final _timeToCtrl = TextEditingController();
  final _pitchIdCtrl = TextEditingController();
  String _ruleType = 'off_peak';
  bool _saving = false;
  String? _error;

  static const _ruleTypes = ['off_peak', 'peak', 'weekend', 'weekday', 'custom'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _multiplierCtrl.dispose();
    _fixedAmountCtrl.dispose();
    _daysCtrl.dispose();
    _timeFromCtrl.dispose();
    _timeToCtrl.dispose();
    _pitchIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Rule name is required');
      return;
    }
    final multiplier = double.tryParse(_multiplierCtrl.text.trim());
    final fixedAmount = double.tryParse(_fixedAmountCtrl.text.trim());
    if (_multiplierCtrl.text.trim().isNotEmpty && multiplier == null) {
      setState(() => _error = 'Invalid multiplier value');
      return;
    }
    if (_fixedAmountCtrl.text.trim().isNotEmpty && fixedAmount == null) {
      setState(() => _error = 'Invalid fixed amount');
      return;
    }
    setState(() { _saving = true; _error = null; });
    final data = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'rule_type': _ruleType,
      if (multiplier != null) 'multiplier': multiplier,
      if (fixedAmount != null) 'fixed_amount': fixedAmount,
      if (_daysCtrl.text.trim().isNotEmpty) 'days_of_week': _daysCtrl.text.trim(),
      if (_timeFromCtrl.text.trim().isNotEmpty) 'time_from': _timeFromCtrl.text.trim(),
      if (_timeToCtrl.text.trim().isNotEmpty) 'time_to': _timeToCtrl.text.trim(),
      if (_pitchIdCtrl.text.trim().isNotEmpty) 'pitch_id': _pitchIdCtrl.text.trim(),
    };
    await widget.onSave(data);
    if (mounted) Navigator.pop(context);
  }

  Widget _field(String label, TextEditingController ctrl, {bool numeric = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF051210),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primaryDeep),
            ),
            child: TextField(
              controller: ctrl,
              keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
              style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textPrimary),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                hintStyle: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0A1F1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add Pricing Rule', style: GoogleFonts.nunito(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 20),
              _field('Rule Name *', _nameCtrl),
              // Rule type dropdown
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rule Type', style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF051210),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primaryDeep),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _ruleType,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF0A1F1A),
                          style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textPrimary),
                          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary, size: 18),
                          onChanged: (v) => setState(() => _ruleType = v ?? 'off_peak'),
                          items: _ruleTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(children: [
                Expanded(child: _field('Multiplier (e.g. 0.8)', _multiplierCtrl, numeric: true)),
                const SizedBox(width: 12),
                Expanded(child: _field('Fixed Amount (optional)', _fixedAmountCtrl, numeric: true)),
              ]),
              _field('Days (e.g. Mon,Tue,Wed)', _daysCtrl),
              Row(children: [
                Expanded(child: _field('Time From (HH:mm)', _timeFromCtrl)),
                const SizedBox(width: 12),
                Expanded(child: _field('Time To (HH:mm)', _timeToCtrl)),
              ]),
              _field('Pitch ID (optional, blank = all pitches)', _pitchIdCtrl),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : Text('Create', style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared widgets for manager views ────────────────────────────────────────
class _PeriodDropdown extends StatelessWidget {
  const _PeriodDropdown({this.value, this.hint = 'Period', this.items = const ['today', 'week', 'month'], required this.onChanged});
  final String? value;
  final String hint;
  final List<String> items;
  final void Function(String) onChanged;

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
          hint: Text(hint, style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
          dropdownColor: const Color(0xFF0A1F1A),
          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary, size: 18),
          style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textPrimary),
          onChanged: (v) { if (v != null) onChanged(v); },
          items: [
            DropdownMenuItem(value: null, child: Text(hint, style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary))),
            ...items.map((i) => DropdownMenuItem(value: i, child: Text(i))),
          ],
        ),
      ),
    );
  }
}

class _WalkInField extends StatelessWidget {
  const _WalkInField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

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
        style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pitch form dialog (create/edit)
// ─────────────────────────────────────────────────────────────────────────────
class _PitchFormDialog extends StatefulWidget {
  const _PitchFormDialog({this.existing, required this.onSave, required this.remoteSource});
  final Map<String, dynamic>? existing;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final ManageRemoteSource remoteSource;

  @override
  State<_PitchFormDialog> createState() => _PitchFormDialogState();
}

class _PitchFormDialogState extends State<_PitchFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _price;
  late final TextEditingController _capacity;
  late final TextEditingController _desc;
  String _surface = 'artificial';
  bool _saving = false;
  String? _bannerUrl;
  List<String> _galleryUrls = [];
  bool _uploadingBanner = false;
  bool _uploadingGallery = false;
  LatLng? _pinLocation;
  bool _geocoding = false;
  double? _serviceRadius;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name'] ?? '');
    _address = TextEditingController(text: e?['address'] ?? '');
    _city = TextEditingController(text: e?['city'] ?? 'Dhaka');
    _price = TextEditingController(text: '${e?['price_per_hour'] ?? ''}');
    _capacity = TextEditingController(text: '${e?['capacity'] ?? ''}');
    _desc = TextEditingController(text: e?['description'] ?? '');
    _surface = e?['surface'] ?? 'artificial';
    _serviceRadius = (e?['service_radius_km'] as num?)?.toDouble();
    _bannerUrl = e?['banner_url'] as String?;
    final rawGallery = e?['image_urls'] as String? ?? '';
    _galleryUrls = rawGallery.isEmpty ? [] : rawGallery.split(',').where((s) => s.trim().isNotEmpty).toList();
    final latVal = double.tryParse('${e?['latitude'] ?? ''}');
    final lngVal = double.tryParse('${e?['longitude'] ?? ''}');
    if (latVal != null && lngVal != null && latVal != 0 && lngVal != 0) {
      _pinLocation = LatLng(latVal, lngVal);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _city.dispose();
    _price.dispose();
    _capacity.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _locateOnMap() async {
    final query = '${_address.text}, ${_city.text}';
    if (query.trim().length < 3) return;
    setState(() => _geocoding = true);
    final result = await GeocodingService.forward(query);
    setState(() => _geocoding = false);
    if (result != null) {
      setState(() => _pinLocation = LatLng(result.lat, result.lng));
    }
  }

  Future<void> _onPinPlaced(LatLng point) async {
    setState(() => _pinLocation = point);
    final result = await GeocodingService.reverse(point.latitude, point.longitude);
    if (result != null && mounted) {
      setState(() {
        if (result.address.isNotEmpty) _address.text = result.address;
        if (result.city.isNotEmpty) _city.text = result.city;
      });
    }
  }

  Future<String?> _uploadImage(String bucket) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    if (file.bytes == null) return null;
    final ext = file.extension ?? 'jpg';
    final presign = await widget.remoteSource.presignUpload(
        bucket, 'pitch_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await widget.remoteSource.uploadToPresignUrl(
        presign['url'] as String, file.bytes!, 'image/$ext');
    return presign['public_url'] as String;
  }

  Future<void> _submit() async {
    if (_name.text.isEmpty || _address.text.isEmpty || _city.text.isEmpty || _price.text.isEmpty) return;
    setState(() => _saving = true);
    await widget.onSave({
      'name': _name.text,
      'description': _desc.text,
      'address': _address.text,
      'city': _city.text,
      'price_per_hour': double.tryParse(_price.text) ?? 0,
      'surface': _surface,
      'capacity': int.tryParse(_capacity.text) ?? 0,
      'banner_url': _bannerUrl ?? '',
      'image_urls': _galleryUrls.join(','),
      'latitude': _pinLocation?.latitude ?? 0.0,
      'longitude': _pinLocation?.longitude ?? 0.0,
      'service_radius_km': _serviceRadius,
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Dialog(
      backgroundColor: const Color(0xFF0A1F1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isEdit ? 'Edit Pitch' : 'Add New Pitch',
                  style: GoogleFonts.nunito(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 20),
              _FormField(label: 'Name *', controller: _name),
              _FormField(label: 'Address *', controller: _address),
              Row(
                children: [
                  Expanded(child: _FormField(label: 'City *', controller: _city)),
                  const SizedBox(width: 12),
                  Expanded(child: _FormField(label: 'Price/hr (BDT) *', controller: _price, numeric: true)),
                ],
              ),
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
                    onTap: (_, point) => _onPinPlaced(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.turfinn.app',
                    ),
                    if (_pinLocation != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: _pinLocation!,
                          width: 30, height: 30,
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
              Row(
                children: [
                  Expanded(child: _FormField(label: 'Capacity', controller: _capacity, numeric: true)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Surface', style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary)),
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
                            child: DropdownButton<String>(
                              value: _surface,
                              isExpanded: true,
                              dropdownColor: const Color(0xFF0A1F1A),
                              style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textPrimary),
                              onChanged: (v) => setState(() => _surface = v!),
                              items: ['artificial', 'grass', 'futsal']
                                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                  .toList(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ],
              ),
              _FormField(label: 'Description', controller: _desc, maxLines: 3),
              // Banner image
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('Banner Image', style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary)),
              ),
              GestureDetector(
                onTap: _uploadingBanner ? null : () async {
                  setState(() => _uploadingBanner = true);
                  final url = await _uploadImage('pitch-images');
                  if (url != null) setState(() => _bannerUrl = url);
                  setState(() => _uploadingBanner = false);
                },
                child: Container(
                  height: 52,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _bannerUrl != null ? AppColors.primary : AppColors.primaryDeep),
                  ),
                  child: Row(children: [
                    if (_uploadingBanner)
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                    else
                      Icon(_bannerUrl != null ? Icons.check_circle : Icons.image_rounded, size: 18,
                          color: _bannerUrl != null ? AppColors.primary : AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Text(_bannerUrl != null ? 'Banner uploaded ✓' : 'Tap to upload banner',
                        style: GoogleFonts.dmSans(fontSize: 13,
                            color: _bannerUrl != null ? AppColors.primary : AppColors.textSecondary)),
                  ]),
                ),
              ),
              // Gallery photos (up to 5)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('Gallery Photos (up to 5)', style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary)),
              ),
              if (_galleryUrls.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _galleryUrls.map((url) => Stack(
                      children: [
                        Container(
                          width: 60, height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.primaryDeep),
                            image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
                          ),
                        ),
                        Positioned(
                          top: 2, right: 2,
                          child: GestureDetector(
                            onTap: () => setState(() => _galleryUrls.remove(url)),
                            child: Container(
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.background),
                              child: const Icon(Icons.cancel, size: 18, color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      ],
                    )).toList(),
                  ),
                ),
              if (_galleryUrls.length < 5)
                GestureDetector(
                  onTap: _uploadingGallery ? null : () async {
                    setState(() => _uploadingGallery = true);
                    final url = await _uploadImage('pitch-images');
                    if (url != null && _galleryUrls.length < 5) setState(() => _galleryUrls.add(url));
                    setState(() => _uploadingGallery = false);
                  },
                  child: Container(
                    height: 48,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primaryDeep),
                    ),
                    child: Row(children: [
                      if (_uploadingGallery)
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                      else
                        const Icon(Icons.add_photo_alternate_rounded, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 10),
                      Text(_uploadingGallery ? 'Uploading...' : 'Add photo (${_galleryUrls.length}/5)',
                          style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
                    ]),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : Text(isEdit ? 'Update' : 'Create', style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({required this.label, required this.controller, this.numeric = false, this.maxLines = 1});
  final String label;
  final TextEditingController controller;
  final bool numeric;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF051210),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primaryDeep),
            ),
            child: TextField(
              controller: controller,
              keyboardType: numeric ? TextInputType.number : TextInputType.text,
              maxLines: maxLines,
              style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                hintStyle: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Analytics Pro (Enhanced with Heatmap, Peak Hours, Customer Insights)
// ─────────────────────────────────────────────────────────────────────────────
class _AnalyticsProView extends ConsumerStatefulWidget {
  const _AnalyticsProView();
  @override
  ConsumerState<_AnalyticsProView> createState() => _AnalyticsProViewState();
}

class _AnalyticsProViewState extends ConsumerState<_AnalyticsProView> {
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _heatmap;
  Map<String, dynamic>? _peaks;
  Map<String, dynamic>? _customers;
  List<dynamic>? _pitchBreakdown;
  bool _loading = true;
  String _period = 'month';
  int _tab = 0; // 0=overview, 1=heatmap, 2=customers

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final src = ref.read(manageRemoteSourceProvider);
    try {
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
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));

    final s = _summary ?? {};
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Analytics Pro', style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Deep performance insights for your business', style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          // Period selector + tab selector
          Row(children: [
            _PeriodDropdown(value: _period, onChanged: (v) { _period = v; _load(); }),
            const SizedBox(width: 24),
            _TabButton(label: 'Overview', active: _tab == 0, onTap: () => setState(() => _tab = 0)),
            const SizedBox(width: 8),
            _TabButton(label: 'Heatmap', active: _tab == 1, onTap: () => setState(() => _tab = 1)),
            const SizedBox(width: 8),
            _TabButton(label: 'Customers', active: _tab == 2, onTap: () => setState(() => _tab = 2)),
          ]),
          const SizedBox(height: 20),
          // Summary cards (always visible)
          LayoutBuilder(builder: (ctx, box) {
            final cols = box.maxWidth > 1000 ? 5 : (box.maxWidth > 600 ? 3 : 2);
            final w = (box.maxWidth - (cols - 1) * 16) / cols;
            return Wrap(
              spacing: 16, runSpacing: 16,
              children: [
                SizedBox(width: w, child: StatCard(label: 'Revenue (BDT)', value: _fmtNum(s['revenue']), icon: Icons.payments, iconColor: AppColors.primary)),
                SizedBox(width: w, child: StatCard(label: 'Bookings', value: '${s['bookings'] ?? 0}', icon: Icons.calendar_month, iconColor: Colors.blueAccent)),
                SizedBox(width: w, child: StatCard(label: 'Occupancy', value: '${(s['occupancy'] as num?)?.toStringAsFixed(1) ?? '0'}%', icon: Icons.stadium, iconColor: Colors.orangeAccent)),
                SizedBox(width: w, child: StatCard(label: 'Avg Rating', value: (s['avg_rating'] as num?)?.toStringAsFixed(1) ?? '—', icon: Icons.star, iconColor: Colors.amber)),
                SizedBox(width: w, child: StatCard(
                  label: 'Avg/Day',
                  value: (_peaks?['avg_bookings_per_day'] as num?)?.toStringAsFixed(1) ?? '0',
                  icon: Icons.trending_up,
                  iconColor: Colors.tealAccent,
                )),
              ],
            );
          }),
          const SizedBox(height: 24),
          // Tab content
          if (_tab == 0) _buildOverviewTab(),
          if (_tab == 1) _buildHeatmapTab(),
          if (_tab == 2) _buildCustomersTab(),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final peakData = _peaks ?? {};
    final busiest = peakData['busiest'] as List<dynamic>? ?? [];
    final slowest = peakData['slowest'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Peak hours cards
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _peakHoursCard('Busiest Hours', busiest, AppColors.primary)),
            const SizedBox(width: 16),
            Expanded(child: _peakHoursCard('Slowest Hours', slowest, Colors.orangeAccent)),
          ],
        ),
        const SizedBox(height: 24),
        // Per-pitch breakdown
        if (_pitchBreakdown != null && _pitchBreakdown!.isNotEmpty)
          DataTableCard(
            title: 'Per-Pitch Breakdown',
            columns: const ['Pitch', 'Bookings', 'Revenue', 'Occupancy %', 'Rating'],
            onRefresh: _load,
            rows: _pitchBreakdown!.map((p) {
              final m = p as Map<String, dynamic>;
              return [
                CellText('${m['pitch_name'] ?? ''}', bold: true),
                CellText('${m['bookings'] ?? 0}'),
                CellText('${m['revenue'] ?? 0} BDT'),
                CellText('${(m['occupancy'] as num?)?.toStringAsFixed(1) ?? '0'}%'),
                CellText('${(m['avg_rating'] as num?)?.toStringAsFixed(1) ?? '—'}'),
              ];
            }).toList(),
          ),
      ],
    );
  }

  Widget _peakHoursCard(String title, List<dynamic> hours, Color accent) {
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
          Text(title, style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          ...hours.map((h) {
            final m = h as Map<String, dynamic>;
            final hour = m['hour'] as int? ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${hour.toString().padLeft(2, '0')}:00',
                      style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: accent),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('${m['count'] ?? 0} bookings', style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textPrimary)),
                  const Spacer(),
                  Text('${m['revenue'] ?? 0} BDT', style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHeatmapTab() {
    final data = _heatmap?['data'] as List<dynamic>? ?? [];
    if (data.isEmpty) {
      return Center(child: Text('No heatmap data', style: GoogleFonts.dmSans(color: AppColors.textSecondary)));
    }

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
          Text('Booking Heatmap', style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
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

  Widget _heatCell(int count, int maxCount) {
    final intensity = maxCount > 0 ? count / maxCount : 0.0;
    return Tooltip(
      message: '$count bookings',
      child: Container(
        width: 40, height: 32,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: count == 0
              ? const Color(0xFF051210)
              : AppColors.primary.withValues(alpha: 0.15 + intensity * 0.75),
          borderRadius: BorderRadius.circular(4),
        ),
        child: count > 0
            ? Center(child: Text('$count', style: GoogleFonts.dmSans(fontSize: 10, color: Colors.white70)))
            : null,
      ),
    );
  }

  Widget _buildCustomersTab() {
    final c = _customers ?? {};
    final topCustomers = c['top_customers'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (ctx, box) {
          final cols = box.maxWidth > 800 ? 4 : 2;
          final w = (box.maxWidth - (cols - 1) * 16) / cols;
          return Wrap(
            spacing: 16, runSpacing: 16,
            children: [
              SizedBox(width: w, child: StatCard(label: 'Total Customers', value: '${c['total_customers'] ?? 0}', icon: Icons.people, iconColor: Colors.blueAccent)),
              SizedBox(width: w, child: StatCard(label: 'New Customers', value: '${c['new_customers'] ?? 0}', icon: Icons.person_add, iconColor: AppColors.primary)),
              SizedBox(width: w, child: StatCard(label: 'Returning %', value: '${(c['returning_pct'] as num?)?.toStringAsFixed(1) ?? '0'}%', icon: Icons.repeat, iconColor: Colors.purpleAccent)),
              SizedBox(width: w, child: StatCard(label: 'Avg Spend', value: _avgSpend(topCustomers), icon: Icons.payments, iconColor: Colors.orangeAccent)),
            ],
          );
        }),
        const SizedBox(height: 24),
        if (topCustomers.isNotEmpty)
          DataTableCard(
            title: 'Top Customers by Spend',
            columns: const ['Name', 'Phone', 'Bookings', 'Total Spent', 'Last Visit'],
            onRefresh: _load,
            rows: topCustomers.map((cu) {
              final m = cu as Map<String, dynamic>;
              return [
                CellText(m['name']?.toString().isNotEmpty == true ? m['name'] : 'Anonymous', bold: true),
                CellText(m['phone'] ?? '—'),
                CellText('${m['booking_count'] ?? 0}'),
                CellText('${m['total_spent'] ?? 0} BDT'),
                CellText(m['last_visit'] ?? '—'),
              ];
            }).toList(),
          ),
      ],
    );
  }

  String _avgSpend(List<dynamic> customers) {
    if (customers.isEmpty) return '0';
    double total = 0;
    for (final c in customers) {
      total += ((c as Map<String, dynamic>)['total_spent'] as num?)?.toDouble() ?? 0;
    }
    return '${(total / customers.length).toStringAsFixed(0)} BDT';
  }

  String _fmtNum(dynamic v) {
    if (v == null) return '0';
    final n = (v is int) ? v.toDouble() : (v as num).toDouble();
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Financials Pro (Daily Ledger + Pitch P&L)
// ─────────────────────────────────────────────────────────────────────────────
class _FinancialsProView extends ConsumerStatefulWidget {
  const _FinancialsProView();
  @override
  ConsumerState<_FinancialsProView> createState() => _FinancialsProViewState();
}

class _FinancialsProViewState extends ConsumerState<_FinancialsProView> {
  Map<String, dynamic>? _ledger;
  List<dynamic>? _pitchPnL;
  Map<String, dynamic>? _basicFinancials;
  bool _loading = true;
  String _preset = 'month';
  int _tab = 0; // 0=overview, 1=daily ledger, 2=pitch P&L
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  String? get _from {
    if (_preset == 'custom' && _fromCtrl.text.isNotEmpty) return _fromCtrl.text;
    final now = DateTime.now();
    final days = _preset == 'week' ? 7 : 30;
    final d = now.subtract(Duration(days: days));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String? get _to {
    if (_preset == 'custom' && _toCtrl.text.isNotEmpty) return _toCtrl.text;
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final src = ref.read(manageRemoteSourceProvider);
    try {
      final results = await Future.wait([
        src.getManagerFinancials(from: _from, to: _to),
        src.getManagerDailyLedger(from: _from, to: _to),
        src.getManagerPitchPnL(from: _from, to: _to),
      ]);
      _basicFinancials = results[0] as Map<String, dynamic>;
      _ledger = results[1] as Map<String, dynamic>;
      _pitchPnL = results[2] as List<dynamic>;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));

    final f = _basicFinancials ?? {};
    final total = (f['total_revenue'] as num?)?.toDouble() ?? 0.0;
    final turfinn = (f['turfinn_revenue'] as num?)?.toDouble() ?? 0.0;
    final walkin = (f['walkin_revenue'] as num?)?.toDouble() ?? 0.0;
    final commission = turfinn * 0.05;
    final net = total - commission;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Financials Pro', style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Complete financial overview with daily ledger', style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          // Controls row
          Row(children: [
            _PeriodDropdown(value: _preset, items: const ['week', 'month', 'custom'], onChanged: (v) {
              _preset = v; if (v != 'custom') _load();
            }),
            if (_preset == 'custom') ...[
              const SizedBox(width: 12),
              SizedBox(width: 160, child: _WalkInField(controller: _fromCtrl, label: 'From (YYYY-MM-DD)')),
              const SizedBox(width: 8),
              SizedBox(width: 160, child: _WalkInField(controller: _toCtrl, label: 'To (YYYY-MM-DD)')),
              const SizedBox(width: 8),
              _SmallAction(icon: Icons.search, color: AppColors.primary, onTap: _load),
            ],
            const SizedBox(width: 24),
            _TabButton(label: 'Overview', active: _tab == 0, onTap: () => setState(() => _tab = 0)),
            const SizedBox(width: 8),
            _TabButton(label: 'Daily Ledger', active: _tab == 1, onTap: () => setState(() => _tab = 1)),
            const SizedBox(width: 8),
            _TabButton(label: 'Pitch P&L', active: _tab == 2, onTap: () => setState(() => _tab = 2)),
          ]),
          const SizedBox(height: 20),
          // Summary cards
          LayoutBuilder(builder: (ctx, box) {
            final cols = box.maxWidth > 1000 ? 5 : (box.maxWidth > 600 ? 3 : 2);
            final w = (box.maxWidth - (cols - 1) * 16) / cols;
            return Wrap(
              spacing: 16, runSpacing: 16,
              children: [
                SizedBox(width: w, child: StatCard(label: 'Gross Revenue', value: '${total.toStringAsFixed(0)} BDT', icon: Icons.payments, iconColor: AppColors.primary)),
                SizedBox(width: w, child: StatCard(label: 'App Revenue', value: '${turfinn.toStringAsFixed(0)} BDT', icon: Icons.phone_android, iconColor: Colors.blueAccent)),
                SizedBox(width: w, child: StatCard(label: 'Walk-in Revenue', value: '${walkin.toStringAsFixed(0)} BDT', icon: Icons.store, iconColor: Colors.orangeAccent)),
                SizedBox(width: w, child: StatCard(label: 'Commission (5%)', value: '${commission.toStringAsFixed(0)} BDT', icon: Icons.receipt_long, iconColor: Colors.redAccent)),
                SizedBox(width: w, child: StatCard(label: 'Net Revenue', value: '${net.toStringAsFixed(0)} BDT', icon: Icons.account_balance_wallet, iconColor: Colors.tealAccent)),
              ],
            );
          }),
          const SizedBox(height: 24),
          if (_tab == 0) _buildFinOverview(),
          if (_tab == 1) _buildDailyLedger(),
          if (_tab == 2) _buildPitchPnL(),
        ],
      ),
    );
  }

  Widget _buildFinOverview() {
    final pmList = _basicFinancials?['by_payment_method'] as List<dynamic>? ?? [];
    if (pmList.isEmpty) {
      return Center(child: Text('No financial data for this period', style: GoogleFonts.dmSans(color: AppColors.textSecondary)));
    }
    return DataTableCard(
      title: 'Walk-in Payment Methods',
      columns: const ['Method', 'Amount (BDT)', 'Count'],
      onRefresh: _load,
      rows: pmList.map((pm) {
        final m = pm as Map<String, dynamic>;
        final method = (m['method'] ?? '').toString();
        return [
          CellText(method.isNotEmpty ? '${method[0].toUpperCase()}${method.substring(1)}' : '—', bold: true),
          CellText('${m['amount'] ?? 0}'),
          CellText('${m['count'] ?? 0}'),
        ];
      }).toList(),
    );
  }

  Widget _buildDailyLedger() {
    final entries = _ledger?['entries'] as List<dynamic>? ?? [];
    final summary = _ledger?['summary'] as Map<String, dynamic>? ?? {};

    if (entries.isEmpty) {
      return Center(child: Text('No ledger entries', style: GoogleFonts.dmSans(color: AppColors.textSecondary)));
    }

    return DataTableCard(
      title: 'Daily Revenue Ledger (${entries.length} days)',
      columns: const ['Date', 'Bookings', 'Total', 'App', 'Walk-in', 'Commission', 'Net'],
      onRefresh: _load,
      rows: [
        ...entries.map((e) {
          final m = e as Map<String, dynamic>;
          final total = (m['total_revenue'] as num?)?.toDouble() ?? 0;
          final commission = (m['commission'] as num?)?.toDouble() ?? 0;
          return [
            CellText(m['date'] ?? '', bold: true),
            CellText('${m['booking_count'] ?? 0}'),
            CellText('${total.toStringAsFixed(0)}'),
            CellText('${((m['app_revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}'),
            CellText('${((m['walkin_revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}'),
            CellText('${commission.toStringAsFixed(0)}'),
            CellText('${(total - commission).toStringAsFixed(0)}'),
          ];
        }),
        // Summary row
        [
          CellText('TOTAL', bold: true),
          CellText('${summary['booking_count'] ?? 0}', bold: true),
          CellText('${((summary['total_revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', bold: true),
          CellText('${((summary['app_revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', bold: true),
          CellText('${((summary['walkin_revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', bold: true),
          CellText('${((summary['commission'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', bold: true),
          CellText('${(((summary['total_revenue'] as num?)?.toDouble() ?? 0) - ((summary['commission'] as num?)?.toDouble() ?? 0)).toStringAsFixed(0)}', bold: true),
        ],
      ],
    );
  }

  Widget _buildPitchPnL() {
    if (_pitchPnL == null || _pitchPnL!.isEmpty) {
      return Center(child: Text('No pitch data', style: GoogleFonts.dmSans(color: AppColors.textSecondary)));
    }

    return DataTableCard(
      title: 'Per-Pitch Profit & Loss',
      columns: const ['Pitch', 'Revenue', 'Bookings', 'Hours', 'Occupancy', 'Commission', 'Net'],
      onRefresh: _load,
      rows: _pitchPnL!.map((p) {
        final m = p as Map<String, dynamic>;
        return [
          CellText(m['pitch_name'] ?? '', bold: true),
          CellText('${((m['revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} BDT'),
          CellText('${m['booking_count'] ?? 0}'),
          CellText('${((m['booked_hours'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)}h'),
          CellText('${((m['occupancy_pct'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)}%'),
          CellText('${((m['commission'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} BDT'),
          CellText('${((m['net_revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} BDT'),
        ];
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Campaigns (Manager Promo Codes)
// ─────────────────────────────────────────────────────────────────────────────
class _CampaignsView extends ConsumerStatefulWidget {
  const _CampaignsView();
  @override
  ConsumerState<_CampaignsView> createState() => _CampaignsViewState();
}

class _CampaignsViewState extends ConsumerState<_CampaignsView> {
  List<dynamic> _promos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _promos = await ref.read(manageRemoteSourceProvider).listManagerPromos();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _deactivate(String id) async {
    try {
      await ref.read(manageRemoteSourceProvider).deactivateManagerPromo(id);
      _load();
    } catch (_) {}
  }

  void _showCreateDialog() {
    final codeCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    final maxUsesCtrl = TextEditingController(text: '100');
    final fromCtrl = TextEditingController();
    final toCtrl = TextEditingController();
    String discountType = 'percent';
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0A1F1A),
          title: Text('Create Promo Code', style: GoogleFonts.nunito(color: AppColors.textPrimary)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WalkInField(controller: codeCtrl, label: 'Promo Code (e.g. SUMMER25)'),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF051210),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.primaryDeep),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: discountType,
                            dropdownColor: const Color(0xFF0A1F1A),
                            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textPrimary),
                            icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary, size: 18),
                            onChanged: (v) => setDialogState(() => discountType = v ?? 'percent'),
                            items: const [
                              DropdownMenuItem(value: 'percent', child: Text('Percent (%)')),
                              DropdownMenuItem(value: 'fixed', child: Text('Fixed (BDT)')),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _WalkInField(controller: valueCtrl, label: discountType == 'percent' ? 'Discount %' : 'Discount BDT')),
                  ]),
                  const SizedBox(height: 10),
                  _WalkInField(controller: maxUsesCtrl, label: 'Max Uses'),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _WalkInField(controller: fromCtrl, label: 'Valid From (YYYY-MM-DD)')),
                    const SizedBox(width: 10),
                    Expanded(child: _WalkInField(controller: toCtrl, label: 'Valid To (YYYY-MM-DD)')),
                  ]),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (codeCtrl.text.isEmpty || valueCtrl.text.isEmpty ||
                    fromCtrl.text.isEmpty || toCtrl.text.isEmpty) {
                  setDialogState(() => error = 'All fields are required');
                  return;
                }
                final value = double.tryParse(valueCtrl.text);
                if (value == null || value <= 0) {
                  setDialogState(() => error = 'Invalid discount value');
                  return;
                }
                if (discountType == 'percent' && value > 100) {
                  setDialogState(() => error = 'Percent discount cannot exceed 100');
                  return;
                }
                try {
                  await ref.read(manageRemoteSourceProvider).createManagerPromo({
                    'code': codeCtrl.text.trim(),
                    'discount_type': discountType,
                    'discount_value': value,
                    'max_uses': int.tryParse(maxUsesCtrl.text) ?? 100,
                    'valid_from': fromCtrl.text.trim(),
                    'valid_to': toCtrl.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  setDialogState(() => error = 'Failed to create promo');
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Campaigns', style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Create promo codes for your pitches to attract more players', style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                onPressed: _showCreateDialog,
                icon: const Icon(Icons.add, color: Colors.black, size: 18),
                label: Text('New Promo', style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Stats summary
          if (_promos.isNotEmpty) ...[
            LayoutBuilder(builder: (ctx, box) {
              final cols = box.maxWidth > 800 ? 3 : 2;
              final w = (box.maxWidth - (cols - 1) * 16) / cols;
              final active = _promos.where((p) => (p as Map)['is_active'] == true).length;
              final totalUsed = _promos.fold<int>(0, (sum, p) => sum + ((p as Map)['used_count'] as int? ?? 0));
              return Wrap(
                spacing: 16, runSpacing: 16,
                children: [
                  SizedBox(width: w, child: StatCard(label: 'Total Promos', value: '${_promos.length}', icon: Icons.local_offer, iconColor: Colors.blueAccent)),
                  SizedBox(width: w, child: StatCard(label: 'Active', value: '$active', icon: Icons.check_circle, iconColor: AppColors.primary)),
                  SizedBox(width: w, child: StatCard(label: 'Total Redemptions', value: '$totalUsed', icon: Icons.redeem, iconColor: Colors.purpleAccent)),
                ],
              );
            }),
            const SizedBox(height: 24),
          ],
          if (_loading)
            const Center(child: CircularProgressIndicator(color: AppColors.primary))
          else if (_promos.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(60),
                child: Column(
                  children: [
                    Icon(Icons.campaign, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    Text('No promo codes yet', style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    Text('Create your first promo code to attract more players', style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            )
          else
            DataTableCard(
              title: 'Promo Codes (${_promos.length})',
              columns: const ['Code', 'Type', 'Value', 'Used / Max', 'Valid From', 'Valid To', 'Status', 'Actions'],
              onRefresh: _load,
              rows: _promos.map((p) {
                final m = p as Map<String, dynamic>;
                final isActive = m['is_active'] == true;
                final discountType = m['discount_type'] ?? '';
                final discountValue = m['discount_value'] ?? 0;
                return [
                  CellText(m['code'] ?? '', bold: true),
                  CellText(discountType == 'percent' ? 'Percent' : 'Fixed'),
                  CellText(discountType == 'percent' ? '$discountValue%' : '$discountValue BDT'),
                  CellText('${m['used_count'] ?? 0} / ${m['max_uses'] ?? '—'}'),
                  CellText(m['valid_from'] ?? ''),
                  CellText(m['valid_to'] ?? ''),
                  StatusBadge(status: isActive ? 'active' : 'cancelled'),
                  isActive
                      ? _SmallAction(
                          icon: Icons.pause,
                          color: Colors.orangeAccent,
                          onTap: () => _deactivate(m['id']),
                        )
                      : const SizedBox.shrink(),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.primaryDeep,
            width: active ? 1.5 : 0.5,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.icon, required this.color, required this.onTap});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: color, size: 15),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Match Cancellations — visibility for the pitch owner
// ─────────────────────────────────────────────────────────────────────────────
class _ManagerMatchCancellationsView extends ConsumerStatefulWidget {
  const _ManagerMatchCancellationsView();
  @override
  ConsumerState<_ManagerMatchCancellationsView> createState() =>
      _ManagerMatchCancellationsViewState();
}

class _ManagerMatchCancellationsViewState
    extends ConsumerState<_ManagerMatchCancellationsView> {
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
          .read(manageRemoteSourceProvider)
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
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    final pendingTotal = _rows.fold<int>(0, (acc, e) {
      final m = e as Map<String, dynamic>;
      final req = (m['refunds_requested'] as num?)?.toInt() ?? 0;
      final done = (m['refunds_completed'] as num?)?.toInt() ?? 0;
      final fail = (m['refunds_failed'] as num?)?.toInt() ?? 0;
      return acc + (req - done - fail);
    });
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Match Cancellations',
              style: GoogleFonts.nunito(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(
              'Cancelled matches at your pitches. Pending refunds: $pendingTotal',
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          DataTableCard(
            title: 'Cancellations ($_total total)',
            columns: const [
              'Match',
              'Host',
              'Pitch',
              'Kickoff',
              'Cancelled',
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
// Today — the daily operations cockpit. Designed to be the first screen an
// owner opens in the morning: today's bookings, cash to collect, alerts.
//
// This is the screen that justifies Turfinn ERP's 3% fee — it answers
// "what do I need to do today?" in one glance, replacing what owners
// would otherwise track via spreadsheets / WhatsApp / memory.
// ─────────────────────────────────────────────────────────────────────────────
class _TodayView extends ConsumerStatefulWidget {
  const _TodayView();
  @override
  ConsumerState<_TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends ConsumerState<_TodayView> {
  Map<String, dynamic>? _stats;
  List<dynamic> _todayBookings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final src = ref.read(manageRemoteSourceProvider);
      // Fetch dashboard summary + today's bookings in parallel.
      final results = await Future.wait([
        src.getDashboard(),
        src.getManagerBookings(limit: 100),
      ]);
      _stats = results[0] as Map<String, dynamic>;
      final all = ((results[1] as Map<String, dynamic>)['data'] as List<dynamic>?) ?? [];
      // Filter to today client-side. Server has the full list; for v1 this
      // is fine, scales to ~100 bookings/day before we'd want a server filter.
      final now = DateTime.now();
      _todayBookings = all.where((b) {
        final m = b as Map<String, dynamic>;
        try {
          final s = DateTime.parse(m['starts_at'] as String).toLocal();
          return s.year == now.year && s.month == now.month && s.day == now.day;
        } catch (_) {
          return false;
        }
      }).toList();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _money(num? v) {
    if (v == null) return '0';
    final n = v.toDouble();
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    final s = _stats ?? {};
    final cashToCollect = (s['cash_to_collect_bdt'] as num?)?.toDouble() ?? 0;
    final today = _todayBookings;

    // Ops alerts — partial-payment bookings happening today that haven't
    // had cash collected yet.
    final pendingCash = today.where((b) {
      final m = b as Map<String, dynamic>;
      final mode = (m['payment_mode'] as String?) ?? 'full_online';
      final due = (m['cash_due_paisa'] as num?)?.toInt() ?? 0;
      final collected = m['cash_collected_at'] as String?;
      return mode == 'partial_online' && due > 0 && collected == null;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Today',
                        style: GoogleFonts.nunito(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text(_humanDate(DateTime.now()),
                        style: GoogleFonts.dmSans(
                            fontSize: 14, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded,
                    color: AppColors.textSecondary),
                onPressed: _load,
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 24),
          // ── KPI tiles row ──
          LayoutBuilder(builder: (ctx, box) {
            final cols = box.maxWidth > 900 ? 4 : (box.maxWidth > 600 ? 2 : 1);
            final w = (box.maxWidth - (cols - 1) * 14) / cols;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                SizedBox(
                    width: w,
                    child: _TodayTile(
                      label: "Today's bookings",
                      value: '${today.length}',
                      icon: Icons.event_note_rounded,
                      iconColor: AppColors.primary,
                      sub: "${today.where((b) => (b['status'] ?? '') == 'confirmed').length} confirmed",
                    )),
                SizedBox(
                    width: w,
                    child: _TodayTile(
                      label: 'Cash to collect',
                      value: '${_money(cashToCollect)} BDT',
                      icon: Icons.payments_outlined,
                      iconColor: const Color(0xFFFFC857),
                      sub: pendingCash.isEmpty
                          ? 'All cleared 🎉'
                          : '${pendingCash.length} booking${pendingCash.length == 1 ? "" : "s"} pending',
                      highlight: pendingCash.isNotEmpty,
                    )),
                SizedBox(
                    width: w,
                    child: _TodayTile(
                      label: 'Active pitches',
                      value: '${s['total_pitches'] ?? 0}',
                      icon: Icons.stadium_rounded,
                      iconColor: const Color(0xFF6FA8FF),
                    )),
                SizedBox(
                    width: w,
                    child: _TodayTile(
                      label: 'Upcoming this week',
                      value: '${s['upcoming_bookings'] ?? 0}',
                      icon: Icons.upcoming_rounded,
                      iconColor: const Color(0xFFB47AFF),
                    )),
              ],
            );
          }),
          const SizedBox(height: 24),
          // ── Pending cash alert ──
          if (pendingCash.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC857).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFFFC857).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active_rounded,
                      color: Color(0xFFFFC857), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${pendingCash.length} cash collection${pendingCash.length == 1 ? "" : "s"} pending today',
                            style: GoogleFonts.nunito(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(
                            'Mark each booking collected once the player pays cash at the venue.',
                            style: GoogleFonts.dmSans(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          // ── Today's schedule ──
          DataTableCard.rich(
            title: "Today's schedule (${today.length})",
            columns: const [
              TableColumn('Time', flex: 2),
              TableColumn('Pitch', flex: 3),
              TableColumn('Customer', flex: 3),
              TableColumn('Cash due', flex: 2, alignRight: true),
              TableColumn('Status', flex: 2),
            ],
            onRefresh: _load,
            rows: today.map((b) {
              final m = b as Map<String, dynamic>;
              final mode = (m['payment_mode'] as String?) ?? 'full_online';
              final due = (m['cash_due_paisa'] as num?)?.toInt() ?? 0;
              final collected = m['cash_collected_at'] as String?;
              final isPartial = mode == 'partial_online' && due > 0;
              Widget cashCell;
              if (!isPartial) {
                cashCell = CellText('—', muted: true);
              } else if (collected != null) {
                cashCell = StatusBadge(status: 'collected');
              } else {
                cashCell = CellText('${(due / 100).toStringAsFixed(0)} BDT',
                    bold: true);
              }
              final phone = (m['customer_phone'] as String?) ?? '';
              final name = m['customer_name']?.toString().isNotEmpty == true
                  ? m['customer_name']
                  : 'Walk-in guest';
              return [
                CellText(_timeOnly(m['starts_at']), bold: true),
                CellText(m['pitch_name'] ?? '—'),
                CellText(name, subtitle: phone.isEmpty ? null : phone),
                cashCell,
                StatusBadge(status: m['status'] ?? ''),
              ];
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _humanDate(DateTime d) {
    const months = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    const days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _timeOnly(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso).toLocal();
      final h = d.hour;
      final m = d.minute.toString().padLeft(2, '0');
      return '${h.toString().padLeft(2, '0')}:$m';
    } catch (_) {
      return iso;
    }
  }
}

class _TodayTile extends StatelessWidget {
  const _TodayTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.sub,
    this.highlight = false,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final String? sub;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: highlight
            ? iconColor.withValues(alpha: 0.08)
            : const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: highlight
                ? iconColor.withValues(alpha: 0.4)
                : AppColors.primaryDeep.withValues(alpha: 0.6),
            width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const Spacer(),
          ]),
          const SizedBox(height: 14),
          Text(value,
              style: GoogleFonts.nunito(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1.1)),
          const SizedBox(height: 4),
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          if (sub != null) ...[
            const SizedBox(height: 6),
            Text(sub!,
                style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: highlight
                        ? iconColor
                        : AppColors.textSecondary.withValues(alpha: 0.8),
                    fontWeight: highlight ? FontWeight.w700 : FontWeight.w500)),
          ],
        ],
      ),
    );
  }
}
