import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/match_event_model.dart';
import 'pulsing_dot.dart';

class LiveMatchCard extends StatelessWidget {
  const LiveMatchCard({super.key, required this.match});
  final MatchEvent match;

  @override
  Widget build(BuildContext context) {
    final score =
        '${match.homeScore ?? 0}  -  ${match.awayScore ?? 0}';
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryDeep.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Faint league logo watermark
          if (match.leagueLogo.isNotEmpty)
            Positioned(
              right: 12,
              top: 12,
              child: Opacity(
                opacity: 0.06,
                child: CachedNetworkImage(
                  imageUrl: match.leagueLogo,
                  width: 60,
                  height: 60,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const PulsingDot(color: Color(0xFFFF3B30), size: 8),
                    const SizedBox(width: 6),
                    Text(
                      match.minutePlayed != null
                          ? "LIVE · ${match.minutePlayed}'"
                          : 'LIVE',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFFF3B30),
                        letterSpacing: 0.6,
                      ),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        match.league,
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
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
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _TeamColumn(
                          name: match.homeTeam, logoURL: match.homeLogo),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        score,
                        style: GoogleFonts.nunito(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _TeamColumn(
                          name: match.awayTeam, logoURL: match.awayLogo),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamColumn extends StatelessWidget {
  const _TeamColumn({required this.name, required this.logoURL});
  final String name;
  final String logoURL;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: logoURL.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: logoURL,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const SizedBox(),
                  errorWidget: (_, __, ___) => const Icon(
                      Icons.shield_outlined,
                      color: AppColors.textSecondary,
                      size: 32),
                )
              : const Icon(Icons.shield_outlined,
                  color: AppColors.textSecondary, size: 32),
        ),
        const SizedBox(height: 6),
        Text(
          name,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
