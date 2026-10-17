import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/match_post_model.dart';
import '../../providers/feed_provider.dart';
import '../../widgets/state_views.dart';

/// "My matches" — shows matches the user is involved in. Tabs split by:
///   • Upcoming: ahead in time
///   • Past: kickoff already passed
class MyMatchesScreen extends ConsumerStatefulWidget {
  const MyMatchesScreen({super.key});

  @override
  ConsumerState<MyMatchesScreen> createState() => _MyMatchesScreenState();
}

class _MyMatchesScreenState extends ConsumerState<MyMatchesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            TabBar(
              controller: _tab,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2.5,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: GoogleFonts.nunito(
                  fontSize: 13, fontWeight: FontWeight.w800),
              tabs: const [
                Tab(text: 'Upcoming'),
                Tab(text: 'Past'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _MatchList(scope: 'upcoming'),
                  _MatchList(scope: 'past'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.textPrimary),
          ),
          const SizedBox(width: 4),
          Text('My matches',
              style: GoogleFonts.nunito(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _MatchList extends ConsumerWidget {
  const _MatchList({required this.scope});
  final String scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myMatchesProvider(scope: scope));
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: const Color(0xFF0A1F1A),
      onRefresh: () async {
        ref.invalidate(myMatchesProvider);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      },
      child: async.when(
        data: (data) => data.posts.isEmpty
            ? EmptyView(
                title: scope == 'past'
                    ? 'No past matches yet'
                    : 'No upcoming matches',
                subtitle: scope == 'past'
                    ? 'Matches you join will land here once they\'re played.'
                    : 'Find or post a match on the Play tab.',
                icon: Icons.sports_soccer_rounded,
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                itemCount: data.posts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _MatchRow(post: data.posts[i]),
              ),
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          onRetry: () => ref.invalidate(myMatchesProvider),
        ),
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.post});
  final MatchPost post;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('EEE, MMM d · h:mm a');
    final spotsLeft = post.spotsTotal - post.spotsFilled;
    final isFull = spotsLeft <= 0;
    final perHead = post.perHeadCostBDT ?? 0;

    return InkWell(
      onTap: () => context.push('${AppRoutes.matchDetail}/${post.id}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1F1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppColors.primaryDeep.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    post.title.isEmpty ? 'Match' : post.title,
                    style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _statusChip(post, isFull),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.schedule_rounded,
                    size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(dateFmt.format(post.matchDate.toLocal()),
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
            if (post.pitchName != null && post.pitchName!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.place_outlined,
                      size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(post.pitchName!,
                        style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                _badge(
                  '${post.format.isEmpty ? "Match" : post.format} · ${post.spotsFilled}/${post.spotsTotal}',
                  bg: AppColors.primary.withValues(alpha: 0.15),
                  fg: AppColors.primary,
                ),
                if (perHead > 0) ...[
                  const SizedBox(width: 6),
                  _badge('$perHead BDT/head',
                      bg: const Color(0xFFFFC857).withValues(alpha: 0.15),
                      fg: const Color(0xFFFFC857)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(MatchPost post, bool isFull) {
    String label;
    Color color;
    if (post.myRefundStatus == 'refunded') {
      label = 'Refunded';
      color = AppColors.primary;
    } else if (post.myRefundStatus == 'requested') {
      label = 'Refund queued';
      color = const Color(0xFFFFC857);
    } else if (post.myRefundStatus == 'refund_failed') {
      label = 'Refund failed';
      color = const Color(0xFFFF8A80);
    } else if (post.status == 'cancelled') {
      label = 'Cancelled';
      color = const Color(0xFFFF8A80);
    } else if (post.status == 'completed') {
      label = 'Completed';
      color = AppColors.textSecondary;
    } else if (isFull) {
      label = 'Full';
      color = AppColors.primary;
    } else {
      label = '${post.spotsTotal - post.spotsFilled} spots left';
      color = AppColors.primary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: GoogleFonts.dmSans(
              fontSize: 10, fontWeight: FontWeight.w800, color: color)),
    );
  }

  Widget _badge(String text, {required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: GoogleFonts.dmSans(
              fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}
