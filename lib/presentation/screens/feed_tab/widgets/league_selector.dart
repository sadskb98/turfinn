import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../providers/sports_provider.dart';

/// Horizontal chip row of followed leagues. `null` = "All".
class LeagueSelector extends ConsumerWidget {
  const LeagueSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  /// `null` = All leagues
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sportsLeaguesProvider);
    return SizedBox(
      height: 36,
      child: async.when(
        data: (leagues) => ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _chip(label: 'All', selected: selected == null, onTap: () => onChanged(null)),
            const SizedBox(width: 6),
            ...leagues.map((l) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _chip(
                    label: l.shortName,
                    selected: selected == l.id,
                    onTap: () => onChanged(l.id),
                  ),
                )),
          ],
        ),
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.18)
              : const Color(0xFF0A1F1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.primaryDeep.withValues(alpha: 0.7),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
