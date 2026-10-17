import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/match_event_model.dart';

class FixtureCard extends StatelessWidget {
  const FixtureCard({super.key, required this.match});
  final MatchEvent match;

  @override
  Widget build(BuildContext context) {
    final isFinished = match.status == 'finished';
    final score = isFinished
        ? '${match.homeScore ?? 0} - ${match.awayScore ?? 0}'
        : DateFormat('h:mm a').format(match.kickoffAt.toLocal());

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryDeep.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isFinished
                      ? AppColors.textSecondary.withValues(alpha: 0.18)
                      : AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isFinished ? 'FT' : DateFormat('MMM d').format(match.kickoffAt.toLocal()),
                  style: GoogleFonts.dmSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isFinished
                        ? AppColors.textSecondary
                        : AppColors.primary,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  match.league,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _TeamRow(
                    name: match.homeTeam, logoURL: match.homeLogo),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  score,
                  style: GoogleFonts.nunito(
                    fontSize: isFinished ? 20 : 14,
                    fontWeight:
                        isFinished ? FontWeight.w800 : FontWeight.w600,
                    color: isFinished
                        ? AppColors.textPrimary
                        : AppColors.primary,
                  ),
                ),
              ),
              Expanded(
                child: _TeamRow(
                    name: match.awayTeam,
                    logoURL: match.awayLogo,
                    reverse: true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({
    required this.name,
    required this.logoURL,
    this.reverse = false,
  });

  final String name;
  final String logoURL;
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    final logo = SizedBox(
      width: 28,
      height: 28,
      child: logoURL.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: logoURL,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => const Icon(Icons.shield_outlined,
                  color: AppColors.textSecondary, size: 22),
            )
          : const Icon(Icons.shield_outlined,
              color: AppColors.textSecondary, size: 22),
    );
    final label = Expanded(
      child: Text(
        name,
        style: GoogleFonts.dmSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: reverse ? TextAlign.right : TextAlign.left,
      ),
    );
    return Row(
      children: reverse
          ? [label, const SizedBox(width: 8), logo]
          : [logo, const SizedBox(width: 8), label],
    );
  }
}
