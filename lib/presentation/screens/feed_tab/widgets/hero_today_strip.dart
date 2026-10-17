import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/match_event_model.dart';
import '../../../providers/sports_provider.dart';
import 'pulsing_dot.dart';

class HeroTodayStrip extends ConsumerWidget {
  const HeroTodayStrip({super.key, this.leagueId});

  final int? leagueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(heroStripMatchesProvider(leagueId: leagueId));
    return SizedBox(
      height: 116,
      child: async.when(
        data: (matches) {
          if (matches.isEmpty) {
            return Center(
              child: Text(
                'No live or upcoming matches',
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: matches.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _HeroChip(match: matches[i]),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 2),
        ),
        error: (_, __) => const SizedBox.shrink(),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.match});
  final MatchEvent match;

  @override
  Widget build(BuildContext context) {
    final isLive = match.status == 'live';
    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLive
              ? const Color(0xFFFF3B30).withValues(alpha: 0.5)
              : AppColors.primaryDeep.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isLive) ...[
                const PulsingDot(color: Color(0xFFFF3B30), size: 7),
                const SizedBox(width: 5),
                Text(
                  match.minutePlayed != null ? "${match.minutePlayed}'" : 'LIVE',
                  style: GoogleFonts.dmSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFFF3B30),
                  ),
                ),
              ] else ...[
                const Icon(Icons.schedule_rounded,
                    size: 11, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  DateFormat('h:mm a').format(match.kickoffAt.toLocal()),
                  style: GoogleFonts.dmSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
              const Spacer(),
              Flexible(
                child: Text(
                  match.league,
                  style: GoogleFonts.dmSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _row(match.homeTeam, match.homeLogo,
              isLive ? '${match.homeScore ?? 0}' : null),
          const SizedBox(height: 4),
          _row(match.awayTeam, match.awayLogo,
              isLive ? '${match.awayScore ?? 0}' : null),
        ],
      ),
    );
  }

  Widget _row(String name, String logoURL, String? score) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: logoURL.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: logoURL,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => const Icon(
                      Icons.shield_outlined,
                      size: 14,
                      color: AppColors.textSecondary),
                )
              : const Icon(Icons.shield_outlined,
                  size: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (score != null) ...[
          const SizedBox(width: 6),
          Text(
            score,
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ],
    );
  }
}
