import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'payment_webview_screen.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/match_post_model.dart';
import '../../../data/sources/remote/feed_remote_source.dart';
import '../../providers/feed_provider.dart';
import '../../widgets/state_views.dart';
import '../../widgets/toast.dart';
import 'widgets/match_post_card.dart';
import 'widgets/post_details_card.dart';
import 'widgets/schedule_match_sheet.dart';

enum _PlayFilter { all, openMatch, needTeammates }

class PlayScreen extends ConsumerStatefulWidget {
  const PlayScreen({super.key});

  @override
  ConsumerState<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends ConsumerState<PlayScreen> {
  double? _userLat;
  double? _userLng;
  _PlayFilter _filter = _PlayFilter.all;
  String _joiningId = '';
  MatchPost? _detailFor;

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  /// Read-only location check — never prompt the user. The map lives on the
  /// Explore tab (which prompts there); if Explore granted permission, we'll
  /// use it here for distance badges. If not, we just show matches without
  /// distance and that's fine.
  Future<void> _getLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.low),
      ).timeout(const Duration(seconds: 6));
      if (!mounted) return;
      setState(() {
        _userLat = pos.latitude;
        _userLng = pos.longitude;
      });
    } catch (_) {}
  }

  Future<void> _refresh() async {
    ref.invalidate(feedListProvider);
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  Future<void> _openSchedule() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ScheduleMatchSheet(
        userLat: _userLat,
        userLng: _userLng,
      ),
    );
    if (created == true && mounted) {
      ref.invalidate(feedListProvider);
      showToast(context, 'Match posted! Players can now join.');
    }
  }

  Future<void> _join(MatchPost post) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JoinConfirmSheet(post: post),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _joiningId = post.id);
    try {
      final session = await ref
          .read(feedRemoteSourceProvider)
          .initiateJoinPayment(post.id);

      // Open SSL gateway inside an in-app WebView so the user never leaves.
      // The WebView resolves with PaymentOutcome based on the backend's
      // return page (title TURFINN_PAYMENT_<status>) or the deep-link URL.
      final outcome = await Navigator.of(context).push<PaymentOutcome>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              PaymentWebViewScreen(gatewayUrl: session.redirectUrl),
        ),
      );

      if (!mounted) return;
      setState(() {
        _detailFor = null;
        _joiningId = '';
      });
      ref.invalidate(feedListProvider);

      switch (outcome) {
        case PaymentOutcome.success:
          showToast(context, "Payment received — you're in!");
          context.push('${AppRoutes.matchDetail}/${post.id}?joined=1');
        case PaymentOutcome.fail:
          showError(context, 'Payment failed. No charge made.');
        case PaymentOutcome.cancel:
          showInfo(context, 'Payment cancelled.');
        case PaymentOutcome.abandoned:
        case null:
          break;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _joiningId = '');
      showError(context, friendlyDioError(e, fallback: 'Could not start payment'));
    }
  }

  Future<void> _report(MatchPost post) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ReportSheet(),
    );
    if (reason == null || !mounted) return;
    try {
      await ref.read(feedRemoteSourceProvider).reportPost(post.id, reason: reason);
      if (!mounted) return;
      showToast(context, "Reported. Thanks — we'll review it.");
    } catch (_) {}
  }

  // ── Section grouping (Tonight / Tomorrow / This week / Later) ──────────
  Map<String, List<MatchPost>> _groupBySection(List<MatchPost> posts) {
    final now = DateTime.now();
    final endOfToday =
        DateTime(now.year, now.month, now.day, 23, 59, 59);
    final endOfTomorrow = endOfToday.add(const Duration(days: 1));
    final endOfWeek = endOfToday.add(const Duration(days: 7));

    final tonight = <MatchPost>[];
    final tomorrow = <MatchPost>[];
    final thisWeek = <MatchPost>[];
    final later = <MatchPost>[];

    for (final p in posts) {
      final m = p.matchDate.toLocal();
      if (m.isBefore(now)) continue; // past
      if (m.isBefore(endOfToday)) {
        tonight.add(p);
      } else if (m.isBefore(endOfTomorrow)) {
        tomorrow.add(p);
      } else if (m.isBefore(endOfWeek)) {
        thisWeek.add(p);
      } else {
        later.add(p);
      }
    }
    return {
      if (tonight.isNotEmpty) 'Tonight': tonight,
      if (tomorrow.isNotEmpty) 'Tomorrow': tomorrow,
      if (thisWeek.isNotEmpty) 'This week': thisWeek,
      if (later.isNotEmpty) 'Later': later,
    };
  }

  List<MatchPost> _applyFilter(List<MatchPost> posts) {
    switch (_filter) {
      case _PlayFilter.all:
        return posts;
      case _PlayFilter.openMatch:
        return posts.where((p) => p.postType == 'open_match').toList();
      case _PlayFilter.needTeammates:
        return posts.where((p) => p.postType == 'need_teammates').toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(feedListProvider(
      lat: _userLat,
      lng: _userLng,
      postType: null,
    ));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: feedAsync.when(
          data: (data) {
            final filtered = _applyFilter(data.posts);
            return Stack(
              children: [
                RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: const Color(0xFF0A1F1A),
                  onRefresh: _refresh,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _topBar()),
                      const SliverToBoxAdapter(child: SizedBox(height: 8)),
                      SliverToBoxAdapter(child: _scheduleCta()),
                      const SliverToBoxAdapter(child: SizedBox(height: 10)),
                      SliverToBoxAdapter(child: _myMatchesEntry()),
                      const SliverToBoxAdapter(child: SizedBox(height: 14)),
                      SliverToBoxAdapter(child: _filterChips()),
                      const SliverToBoxAdapter(child: SizedBox(height: 8)),
                      ..._buildSections(filtered),
                      const SliverToBoxAdapter(child: SizedBox(height: 120)),
                    ],
                  ),
                ),
                if (_detailFor != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      child: PostDetailsCard(
                        post: _detailFor!,
                        joining: _joiningId == _detailFor!.id,
                        onJoin: () => _join(_detailFor!),
                        onClose: () => setState(() => _detailFor = null),
                      ),
                    ),
                  ),
              ],
            );
          },
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(
            onRetry: () => ref.invalidate(feedListProvider),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          Text('Play',
              style: GoogleFonts.nunito(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const Spacer(),
          GestureDetector(
            onTap: () => context.go(AppRoutes.profile),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0A1F1A),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.6),
                    width: 1.2),
              ),
              child: const Icon(Icons.person_rounded,
                  color: AppColors.primary, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scheduleCta() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: InkWell(
        onTap: _openSchedule,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.18),
                AppColors.primary.withValues(alpha: 0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.5),
                width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add_rounded,
                    color: Colors.black, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Schedule a match',
                        style: GoogleFonts.nunito(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                        'Pick a Turfinn pitch · split the cost · fill the spots',
                        style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _myMatchesEntry() {
    final mineAsync = ref.watch(myMatchesProvider(scope: 'upcoming'));
    final count = mineAsync.maybeWhen(
      data: (d) => d.posts.length,
      orElse: () => 0,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: InkWell(
        onTap: () => context.push(AppRoutes.myMatches),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1F1A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.primaryDeep.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.event_note_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('My matches',
                        style: GoogleFonts.nunito(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                        count == 0
                            ? 'Track matches you\'ve hosted or joined'
                            : '$count upcoming · tap for details + refunds',
                        style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$count',
                      style: GoogleFonts.nunito(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.black)),
                ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChips() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _chip('All', _PlayFilter.all),
          const SizedBox(width: 6),
          _chip('Open match', _PlayFilter.openMatch),
          const SizedBox(width: 6),
          _chip('Need teammates', _PlayFilter.needTeammates),
        ],
      ),
    );
  }

  Widget _chip(String label, _PlayFilter value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.18)
              : const Color(0xFF0A1F1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.primaryDeep.withValues(alpha: 0.7),
          ),
        ),
        child: Text(label,
            style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected
                    ? AppColors.primary
                    : AppColors.textPrimary)),
      ),
    );
  }

  List<Widget> _buildSections(List<MatchPost> posts) {
    if (posts.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              children: [
                const Icon(Icons.sports_soccer_rounded,
                    size: 48, color: AppColors.textSecondary),
                const SizedBox(height: 12),
                Text('No matches yet — schedule one above.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                        fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ];
    }

    final grouped = _groupBySection(posts);
    final widgets = <Widget>[];
    grouped.forEach((label, items) {
      widgets.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Row(
            children: [
              Text(label,
                  style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(width: 8),
              Text('· ${items.length}',
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ));
      widgets.add(SliverList.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: MatchPostCard(
            post: items[i],
            joining: _joiningId == items[i].id,
            onTap: () => context.push('${AppRoutes.matchDetail}/${items[i].id}'),
            onJoin: () => _join(items[i]),
            onReport: () => _report(items[i]),
          ),
        ),
      ));
    });
    return widgets;
  }

}

// ── Join confirmation sheet ─────────────────────────────────────────────────

class _JoinConfirmSheet extends StatelessWidget {
  const _JoinConfirmSheet({required this.post});
  final MatchPost post;

  @override
  Widget build(BuildContext context) {
    final perHead = post.perHeadCostBDT ?? 0;
    final fee = post.joinFeeBDT;
    final total = perHead + fee;
    // Bottom safe-area + keyboard inset so the action buttons aren't clipped
    // behind the system gesture/nav bar.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF033640),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 14),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.primaryDeep,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('Join ${post.title.isEmpty ? "this match" : post.title}?',
              style: GoogleFonts.nunito(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          if (post.pitchName != null)
            _row(Icons.place_rounded, post.pitchName!),
          _row(Icons.schedule_rounded,
              '${DateFormat('EEE, MMM d · h:mm a').format(post.matchDate.toLocal())} · ${post.durationMinutes} min'),
          _row(Icons.people_alt_outlined,
              '${post.spotsTotal - post.spotsFilled} of ${post.spotsTotal} spots left'),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1F1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.primaryDeep.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                if (perHead > 0)
                  _money('Your share of the pitch', perHead),
                _money('Commitment fee (non-refundable)', fee),
                const Divider(height: 16, color: Color(0xFF0E2A24)),
                _money('Total to pay', total, highlight: true),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFC857).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_rounded,
                    size: 16, color: Color(0xFFFFC857)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pay securely via card / mobile banking. Your spot is held until payment completes.',
                    style: GoogleFonts.dmSans(
                        fontSize: 11,
                        color: AppColors.textPrimary,
                        height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primaryDeep),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Cancel',
                      style: GoogleFonts.dmSans(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                      total > 0
                          ? 'Pay $total BDT to join'
                          : 'Pay $fee BDT to join',
                      style: GoogleFonts.nunito(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _money(String label, int amount, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: highlight
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight:
                      highlight ? FontWeight.w700 : FontWeight.w500)),
          const Spacer(),
          Text('$amount BDT',
              style: GoogleFonts.nunito(
                  fontSize: highlight ? 16 : 13,
                  fontWeight: FontWeight.w800,
                  color: highlight
                      ? AppColors.primary
                      : AppColors.textPrimary)),
        ],
      ),
    );
  }
}

// ── Report sheet ────────────────────────────────────────────────────────────

class _ReportSheet extends StatelessWidget {
  const _ReportSheet();

  @override
  Widget build(BuildContext context) {
    const reasons = {
      'unsafe_location': 'Unsafe location',
      'no_show': 'Host or players didn\'t show up',
      'fake': 'Fake or misleading match',
      'spam': 'Spam',
      'other': 'Something else',
    };
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF033640),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 14),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.primaryDeep,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('Report this match',
              style: GoogleFonts.nunito(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('What went wrong?',
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          ...reasons.entries.map((e) => InkWell(
                onTap: () => Navigator.of(context).pop(e.key),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1F1A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.primaryDeep
                            .withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.flag_outlined,
                          color: AppColors.textSecondary, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(e.value,
                            style: GoogleFonts.dmSans(
                                fontSize: 14,
                                color: AppColors.textPrimary)),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: AppColors.textSecondary),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

