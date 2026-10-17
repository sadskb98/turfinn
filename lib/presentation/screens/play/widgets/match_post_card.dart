import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/match_post_model.dart';

/// Rich match-post card used in the Play screen sectioned list.
/// Shows pitch, time, format, spots-left, per-head cost + Join button.
class MatchPostCard extends StatelessWidget {
  const MatchPostCard({
    super.key,
    required this.post,
    required this.onTap,
    required this.onJoin,
    required this.onReport,
    this.joining = false,
  });

  final MatchPost post;
  final VoidCallback onTap;
  final VoidCallback onJoin;
  final VoidCallback onReport;
  final bool joining;

  @override
  Widget build(BuildContext context) {
    final spotsLeft = post.spotsTotal - post.spotsFilled;
    final isTeammates = post.postType == 'need_teammates';
    final isFull = spotsLeft <= 0;
    final dateFmt = DateFormat('h:mm a');

    final perHead = post.perHeadCostBDT;
    final fee = post.joinFeeBDT;
    final totalDue = (perHead ?? 0) + fee;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A1F1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.primaryDeep.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _avatar(),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.authorName.isEmpty ? 'Player' : post.authorName,
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        isTeammates
                            ? 'Looking for teammates'
                            : 'Open match',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: isTeammates
                              ? const Color(0xFFFFC857)
                              : AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onReport,
                  iconSize: 18,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.flag_outlined,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              post.title,
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.25,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            _infoRow(Icons.schedule_rounded,
                '${dateFmt.format(post.matchDate.toLocal())} · ${post.durationMinutes} min'),
            if (post.pitchName != null && post.pitchName!.isNotEmpty)
              _infoRow(Icons.place_rounded,
                  '${post.pitchName}${post.distanceKm != null ? " · ${post.distanceKm!.toStringAsFixed(1)} km" : ""}'),
            const SizedBox(height: 10),
            Row(
              children: [
                _badge(
                  '${post.format.isEmpty ? "Open" : post.format} · $spotsLeft / ${post.spotsTotal} spots',
                  bg: isFull
                      ? AppColors.textSecondary.withValues(alpha: 0.15)
                      : AppColors.primary.withValues(alpha: 0.15),
                  fg: isFull
                      ? AppColors.textSecondary
                      : AppColors.primary,
                ),
                if (perHead != null && perHead > 0) ...[
                  const SizedBox(width: 8),
                  _badge(
                    '${perHead} BDT/head',
                    bg: const Color(0xFFFFC857).withValues(alpha: 0.15),
                    fg: const Color(0xFFFFC857),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _ctaButton(context),
          ],
        ),
      ),
    );
  }

  Widget _ctaButton(BuildContext context) {
    final spotsLeft = post.spotsTotal - post.spotsFilled;
    final isFull = spotsLeft <= 0;
    final perHead = post.perHeadCostBDT ?? 0;
    final fee = post.joinFeeBDT;
    final totalDue = perHead + fee;

    if (post.isHost) {
      // Host can't join their own match — show a clear "Your match" tag.
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.verified_user_rounded,
                size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text('You\'re hosting this match',
                style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
          ],
        ),
      );
    }

    if (post.isJoined) {
      // Already paid + joined — let them open detail to see what's next.
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.check_circle_rounded, size: 18),
          label: Text('You\'re in — view details',
              style: GoogleFonts.nunito(
                  fontSize: 13, fontWeight: FontWeight.w800)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary, width: 1.2),
            padding: const EdgeInsets.symmetric(vertical: 11),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: (isFull || joining) ? null : onJoin,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor:
              AppColors.primaryDeep.withValues(alpha: 0.6),
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        child: joining
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.black))
            : Text(
                isFull
                    ? 'Match full'
                    : (totalDue > 0
                        ? 'Pay $totalDue BDT to join'
                        : 'Pay $fee BDT to join'),
                style: GoogleFonts.nunito(
                    fontSize: 14, fontWeight: FontWeight.w800),
              ),
      ),
    );
  }

  Widget _avatar() {
    final letter = post.authorName.isEmpty
        ? '?'
        : post.authorName.substring(0, 1).toUpperCase();
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryMid],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF051210),
          ),
          child: Center(
            child: Text(
              letter,
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: AppColors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, {required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
