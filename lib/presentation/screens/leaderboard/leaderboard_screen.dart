import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/gamification_models.dart';
import '../../providers/gamification_provider.dart';

class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lbAsync = ref.watch(leaderboardProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Leaderboard',
            style: GoogleFonts.nunito(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: lbAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not load leaderboard',
                  style: GoogleFonts.dmSans(
                      fontSize: 14, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(leaderboardProvider),
                child: Text('Retry',
                    style: GoogleFonts.dmSans(color: AppColors.primary)),
              ),
            ],
          ),
        ),
        data: (lb) => _buildContent(context, lb),
      ),
    );
  }

  Widget _buildContent(BuildContext context, LeaderboardResult lb) {
    return Column(
      children: [
        // Tier badge + rank
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _tierColor(lb.tier).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: _tierColor(lb.tier).withValues(alpha: 0.4)),
            ),
            child: Text(
              '${lb.tier[0].toUpperCase()}${lb.tier.substring(1)} Tier — Rank #${lb.yourRank}',
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _tierColor(lb.tier),
              ),
            ),
          ),
        ),

        // Top 10 list
        Expanded(
          child: lb.top.isEmpty
              ? Center(
                  child: Text('No entries yet this week',
                      style: GoogleFonts.dmSans(
                          fontSize: 14, color: AppColors.textSecondary)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: lb.top.length,
                  itemBuilder: (context, index) {
                    final entry = lb.top[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: index < 3
                            ? const Color(0xFF0A1F1A)
                            : const Color(0xFF071714),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: index < 3
                              ? AppColors.primaryDeep
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text(
                              '#${entry.rank}',
                              style: GoogleFonts.nunito(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: index < 3
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF0D2A22),
                            ),
                            child: Center(
                              child: Text(
                                entry.name.isNotEmpty
                                    ? entry.name[0].toUpperCase()
                                    : 'P',
                                style: GoogleFonts.nunito(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              entry.name.isNotEmpty ? entry.name : 'Player',
                              style: GoogleFonts.dmSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            '${entry.xpEarned} XP',
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryMid,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Color _tierColor(String tier) {
    switch (tier) {
      case 'gold':
        return const Color(0xFFFFD700);
      case 'silver':
        return const Color(0xFFC0C0C0);
      default:
        return const Color(0xFFCD7F32);
    }
  }
}
