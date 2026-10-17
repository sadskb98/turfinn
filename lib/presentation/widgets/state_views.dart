// Reusable empty / error / loading state widgets. Designed for the
// Bangladesh market: short copy, an actionable retry button, friendly
// illustration via Material icons (no asset weight). Use these everywhere
// instead of raw CircularProgressIndicator + ad-hoc error Text widgets.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';

/// Shown when an async fetch returned no data.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4)),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown when an async fetch failed (network, server, parse). The retry
/// callback is mandatory because users in low-connectivity markets retry
/// far more than they bug-report — make it obvious.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.onRetry,
    this.title = 'Connection issue',
    this.subtitle = 'Check your network and try again.',
  });

  final VoidCallback onRetry;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Default loading spinner — themed, cheap to use.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(color: AppColors.primary));
}
