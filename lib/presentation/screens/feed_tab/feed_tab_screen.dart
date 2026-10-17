import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/match_event_model.dart';
import '../../../data/models/sports_feed_item_model.dart';
import '../../providers/sports_provider.dart';
import 'widgets/feed_filter_chips.dart';
import 'widgets/fixture_card.dart';
import 'widgets/hero_today_strip.dart';
import 'widgets/league_selector.dart';
import 'widgets/live_match_card.dart';
import 'widgets/news_article_card.dart';
import 'widgets/standings_table.dart';

class FeedTabScreen extends ConsumerStatefulWidget {
  const FeedTabScreen({super.key});

  @override
  ConsumerState<FeedTabScreen> createState() => _FeedTabScreenState();
}

class _FeedTabScreenState extends ConsumerState<FeedTabScreen> {
  FeedFilter _filter = FeedFilter.all;
  int? _leagueId;
  String _search = '';
  Timer? _liveTicker;

  static const _liveRefreshInterval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _restartLiveTicker();
  }

  @override
  void dispose() {
    _liveTicker?.cancel();
    super.dispose();
  }

  /// Auto-refresh live data when the filter is one that shows live scores.
  /// 30s on the client × 15s on the backend cron = freshness ≤ 45s.
  void _restartLiveTicker() {
    _liveTicker?.cancel();
    final wantsLive = _filter == FeedFilter.live || _filter == FeedFilter.all;
    if (!wantsLive) return;
    _liveTicker = Timer.periodic(_liveRefreshInterval, (_) {
      if (!mounted) return;
      ref
        ..invalidate(sportsMatchesProvider)
        ..invalidate(sportsFeedProvider)
        ..invalidate(heroStripMatchesProvider);
    });
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(sportsFeedProvider)
      ..invalidate(sportsNewsProvider)
      ..invalidate(sportsMatchesProvider)
      ..invalidate(heroStripMatchesProvider)
      ..invalidate(sportsStandingsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  void _openSearch() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchSheet(initial: _search),
    );
    if (result == null) return;
    setState(() => _search = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: const Color(0xFF0A1F1A),
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _topBar()),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverToBoxAdapter(
                child: LeagueSelector(
                  selected: _leagueId,
                  onChanged: (id) => setState(() => _leagueId = id),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(
                    'Today',
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(child: HeroTodayStrip(leagueId: _leagueId)),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyFilters(
                  child: Container(
                    color: AppColors.background,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: FeedFilterChips(
                      selected: _filter,
                      onChanged: (f) {
                        setState(() => _filter = f);
                        _restartLiveTicker();
                      },
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              _bodySliver(),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Text(
            'Feed',
            style: GoogleFonts.nunito(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          if (_search.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _search = ''),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '"$_search"',
                        style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.close_rounded,
                          size: 14, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            ),
          IconButton(
            onPressed: _openSearch,
            icon: const Icon(Icons.search_rounded,
                color: AppColors.textPrimary),
          ),
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
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _bodySliver() {
    if (_search.isNotEmpty) {
      return _newsSliver(search: _search);
    }
    switch (_filter) {
      case FeedFilter.all:
        return _mergedSliver();
      case FeedFilter.live:
        return _matchesSliver(status: 'live');
      case FeedFilter.news:
        return _newsSliver();
      case FeedFilter.fixtures:
        return _matchesSliver(status: 'scheduled');
      case FeedFilter.standings:
        return _standingsSliver();
    }
  }

  Widget _standingsSliver() {
    if (_leagueId == null) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              const Icon(Icons.leaderboard_rounded,
                  size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text(
                'Pick a league above to see its points table.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return SliverToBoxAdapter(child: StandingsTable(leagueId: _leagueId!));
  }

  Widget _mergedSliver() {
    final async = ref.watch(sportsFeedProvider(limit: 30, leagueId: _leagueId));
    return async.when(
      data: (data) {
        if (data.items.isEmpty) return const _EmptyState();
        return SliverList.separated(
          itemCount: data.items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _renderItem(data.items[i]),
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(
          child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary)))),
      error: (e, _) => SliverToBoxAdapter(child: _Error(e.toString())),
    );
  }

  Widget _newsSliver({String? search}) {
    final async = ref.watch(sportsNewsProvider(limit: 30, search: search, leagueId: _leagueId));
    return async.when(
      data: (data) {
        if (data.items.isEmpty) return const _EmptyState();
        return SliverList.separated(
          itemCount: data.items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: NewsArticleCard(article: data.items[i]),
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(
          child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary)))),
      error: (e, _) => SliverToBoxAdapter(child: _Error(e.toString())),
    );
  }

  Widget _matchesSliver({required String status}) {
    final async = ref.watch(sportsMatchesProvider(limit: 30, status: status, leagueId: _leagueId));
    return async.when(
      data: (data) {
        if (data.items.isEmpty) return const _EmptyState();
        return SliverList.separated(
          itemCount: data.items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _matchCard(data.items[i]),
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(
          child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary)))),
      error: (e, _) => SliverToBoxAdapter(child: _Error(e.toString())),
    );
  }

  Widget _renderItem(SportsFeedItem item) {
    if (item.kind == 'news' && item.news != null) {
      return NewsArticleCard(article: item.news!);
    }
    if (item.kind == 'match' && item.match != null) {
      return _matchCard(item.match!);
    }
    return const SizedBox.shrink();
  }

  Widget _matchCard(MatchEvent m) =>
      m.status == 'live' ? LiveMatchCard(match: m) : FixtureCard(match: m);
}

// ── Sticky filter chip header ────────────────────────────────────────────────

class _StickyFilters extends SliverPersistentHeaderDelegate {
  _StickyFilters({required this.child});
  final Widget child;

  @override
  double get minExtent => 50;

  @override
  double get maxExtent => 50;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      child;

  @override
  bool shouldRebuild(_StickyFilters old) => old.child != child;
}

// ── Empty / error / search sheet ─────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            const Icon(Icons.sports_soccer_rounded,
                size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              'Nothing here yet — pull to refresh.',
              style: GoogleFonts.dmSans(
                  fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error(this.message);
  final String message;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.error_outline,
              color: AppColors.textSecondary, size: 36),
          const SizedBox(height: 8),
          Text(
            'Could not load: $message',
            style: GoogleFonts.dmSans(
                fontSize: 12, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.initial});
  final String initial;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF033640),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.primaryDeep,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _ctrl,
              autofocus: true,
              style: GoogleFonts.dmSans(
                  fontSize: 14, color: AppColors.textPrimary),
              onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
              decoration: InputDecoration(
                hintText: 'Search news...',
                hintStyle: GoogleFonts.dmSans(
                    fontSize: 14, color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppColors.textSecondary),
                filled: true,
                fillColor: const Color(0xFF0A1F1A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(''),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primaryDeep),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Clear',
                        style: GoogleFonts.dmSans(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_ctrl.text.trim()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Search',
                        style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
