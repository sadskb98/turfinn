import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/match_post_model.dart';

class PostDetailsCard extends StatelessWidget {
  const PostDetailsCard({
    super.key,
    required this.post,
    required this.onJoin,
    required this.onClose,
    this.joining = false,
  });

  final MatchPost post;
  final VoidCallback onJoin;
  final VoidCallback onClose;
  final bool joining;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d · h:mm a');
    final spotsLeft = post.spotsTotal - post.spotsFilled;
    final isTeammates = post.postType == 'need_teammates';
    final typeLabel = isTeammates ? 'Need teammates' : 'Open match';
    final typeColor =
        isTeammates ? const Color(0xFFFFC857) : Colors.white;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryDeep.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  typeLabel,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: typeColor,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: AppColors.textSecondary),
                onPressed: onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: 20,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            post.title.isEmpty ? 'Match' : post.title,
            style: GoogleFonts.nunito(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'by ${post.authorName.isEmpty ? "Player" : post.authorName}',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.event_rounded,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                fmt.format(post.matchDate.toLocal()),
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: AppColors.textPrimary),
              ),
              const SizedBox(width: 14),
              const Icon(Icons.timer_outlined,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                '${post.durationMinutes} min',
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.people_alt_outlined,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                '$spotsLeft / ${post.spotsTotal} spots left',
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: AppColors.textPrimary),
              ),
              if (post.format.isNotEmpty) ...[
                const SizedBox(width: 14),
                const Icon(Icons.sports_soccer_rounded,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  post.format,
                  style: GoogleFonts.dmSans(
                      fontSize: 13, color: AppColors.textPrimary),
                ),
              ],
            ],
          ),
          if (post.distanceKm != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.place_outlined,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  '${post.distanceKm!.toStringAsFixed(1)} km away',
                  style: GoogleFonts.dmSans(
                      fontSize: 13, color: AppColors.textPrimary),
                ),
              ],
            ),
          ],
          if (post.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              post.description,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (spotsLeft <= 0 || joining) ? null : onJoin,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primaryDeep,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: joining
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Text(
                      spotsLeft <= 0 ? 'Full' : 'Join match',
                      style: GoogleFonts.nunito(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
