import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/standings_model.dart';
import '../../../providers/sports_provider.dart';

class StandingsTable extends ConsumerWidget {
  const StandingsTable({super.key, required this.leagueId});
  final int leagueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sportsStandingsProvider(leagueId: leagueId));
    return async.when(
      data: (data) => _build(context, data),
      loading: () => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Could not load standings: $e',
            style: GoogleFonts.dmSans(color: AppColors.textSecondary),
            textAlign: TextAlign.center),
      ),
    );
  }

  Widget _build(BuildContext context, StandingsResponse data) {
    final groups = data.standings;
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            const Icon(Icons.leaderboard_rounded,
                size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              'No standings available for this league.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    final firstGroup = groups.first as List;
    final rows = firstGroup
        .whereType<Map>()
        .map((m) => StandingRow.fromMap(Map<String, dynamic>.from(m)))
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A1F1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppColors.primaryDeep.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _header(data),
            const Divider(height: 1, color: Color(0xFF0E2A24)),
            ...rows.map((r) => _row(r, isLast: r == rows.last)),
          ],
        ),
      ),
    );
  }

  Widget _header(StandingsResponse d) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Row(
        children: [
          if (d.leagueLogo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CachedNetworkImage(
                    imageUrl: d.leagueLogo, fit: BoxFit.contain),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.leagueName,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Season ${d.season}-${(d.season + 1) % 100}',
                  style: GoogleFonts.dmSans(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          _colHead('P'),
          _colHead('W'),
          _colHead('D'),
          _colHead('L'),
          _colHead('GD'),
          _colHead('Pts', highlight: true),
        ],
      ),
    );
  }

  Widget _colHead(String s, {bool highlight = false}) {
    return SizedBox(
      width: 24,
      child: Text(
        s,
        textAlign: TextAlign.center,
        style: GoogleFonts.dmSans(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: highlight ? AppColors.primary : AppColors.textSecondary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _row(StandingRow r, {required bool isLast}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom:
                    BorderSide(color: Color(0xFF0E2A24), width: 0.6)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '${r.rank}',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (r.teamLogo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CachedNetworkImage(
                  imageUrl: r.teamLogo,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => const Icon(
                      Icons.shield_outlined,
                      size: 16,
                      color: AppColors.textSecondary),
                ),
              ),
            ),
          Expanded(
            child: Text(
              r.teamName,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _cell('${r.played}'),
          _cell('${r.win}'),
          _cell('${r.draw}'),
          _cell('${r.lose}'),
          _cell('${r.goalsDiff > 0 ? "+" : ""}${r.goalsDiff}'),
          _cell('${r.points}', highlight: true),
        ],
      ),
    );
  }

  Widget _cell(String s, {bool highlight = false}) {
    return SizedBox(
      width: 24,
      child: Text(
        s,
        textAlign: TextAlign.center,
        style: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: highlight ? FontWeight.w800 : FontWeight.w500,
          color: highlight ? AppColors.primary : AppColors.textPrimary,
        ),
      ),
    );
  }
}
