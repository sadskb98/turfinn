import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';

enum FeedFilter { all, live, news, fixtures, standings }

extension FeedFilterX on FeedFilter {
  String get label {
    switch (this) {
      case FeedFilter.all:
        return 'All';
      case FeedFilter.live:
        return 'Live';
      case FeedFilter.news:
        return 'News';
      case FeedFilter.fixtures:
        return 'Fixtures';
      case FeedFilter.standings:
        return 'Standings';
    }
  }
}

class FeedFilterChips extends StatelessWidget {
  const FeedFilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final FeedFilter selected;
  final ValueChanged<FeedFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: FeedFilter.values
            .map((f) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Chip(
                    label: f.label,
                    selected: selected == f,
                    onTap: () => onChanged(f),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : const Color(0xFF0A1F1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.primaryDeep),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.black : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
