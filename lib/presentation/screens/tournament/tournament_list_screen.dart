import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../data/models/tournament_model.dart';
import '../../providers/tournament_provider.dart';

class TournamentListScreen extends ConsumerStatefulWidget {
  const TournamentListScreen({super.key});

  @override
  ConsumerState<TournamentListScreen> createState() =>
      _TournamentListScreenState();
}

class _TournamentListScreenState extends ConsumerState<TournamentListScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(tournamentListProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tournamentsAsync = ref.watch(tournamentListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Tournaments',
          style: GoogleFonts.nunito(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () => context.push(AppRoutes.tournamentCreate),
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: tournamentsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 48,
                    color: AppColors.textSecondary.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Text(
                  'Could not load tournaments',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => ref.invalidate(tournamentListProvider),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Retry',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        data: (tournaments) {
          if (tournaments.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emoji_events_outlined,
                      size: 56,
                      color: AppColors.primaryDeep),
                  const SizedBox(height: 12),
                  Text(
                    'No tournaments yet',
                    style: GoogleFonts.nunito(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap + to create the first one',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          final hasMore =
              ref.read(tournamentListProvider.notifier).hasMore;
          return RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: AppColors.background,
            onRefresh: () async =>
                ref.invalidate(tournamentListProvider),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
              itemCount: tournaments.length + (hasMore ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= tournaments.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TournamentCard(
                    tournament: tournaments[i],
                    onTap: () =>
                        context.push('/tournaments/${tournaments[i].id}'),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tournament Card
// ─────────────────────────────────────────────────────────────────────────────
class _TournamentCard extends StatelessWidget {
  const _TournamentCard({required this.tournament, required this.onTap});

  final TournamentModel tournament;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final formatLabel = _formatLabel(tournament.format);
    final statusColor = _statusColor(tournament.status);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1F1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primaryDeep, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name + badges row
            Row(
              children: [
                Expanded(
                  child: Text(
                    tournament.name,
                    style: GoogleFonts.nunito(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _Badge(label: formatLabel, color: AppColors.primaryMid),
                const SizedBox(width: 6),
                _Badge(label: tournament.status, color: statusColor),
              ],
            ),
            const SizedBox(height: 8),

            // Creator + team count
            Row(
              children: [
                Icon(Icons.person_outline,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  tournament.creatorName.isNotEmpty
                      ? tournament.creatorName
                      : 'Unknown',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                Icon(Icons.groups_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '${tournament.teamCount} / ${tournament.maxTeams} teams',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Entry fee + Prize pool
            Row(
              children: [
                _InfoChip(
                  icon: Icons.toll_outlined,
                  label: tournament.entryFee > 0
                      ? 'Entry: ${tournament.entryFee} coins'
                      : 'Free Entry',
                  highlight: tournament.entryFee == 0,
                ),
                if (tournament.prizePool > 0) ...[
                  const SizedBox(width: 8),
                  _InfoChip(
                    icon: Icons.emoji_events_outlined,
                    label: 'Prize: ${tournament.prizePool} coins',
                    highlight: true,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatLabel(String format) {
    // format stored as "5v5", "7v7", "11v11"
    final parts = format.replaceAll('v', ' vs ');
    return parts;
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'registration_open':
        return AppColors.primary;
      case 'in_progress':
        return Colors.orange;
      case 'completed':
        return AppColors.primaryMid;
      case 'cancelled':
        return Colors.red;
      default:
        return AppColors.textSecondary;
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label.replaceAll('_', ' '),
        style: GoogleFonts.dmSans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.primary.withValues(alpha: 0.1)
            : AppColors.primaryDeep.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 13,
              color: highlight ? AppColors.primary : AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: highlight ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
