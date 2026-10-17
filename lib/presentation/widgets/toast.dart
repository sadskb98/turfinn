// Themed snackbar helpers. Replaces the default white-rectangle Material
// snackbar that clashes with our dark theme. One import, three call sites:
//
//   showToast(context, 'Match posted!');
//   showError(context, 'Could not load matches');
//   showInfo(context, 'Refund queued — 3-7 business days');
//
// Each variant: rounded floating shape, themed background, larger touch
// area to dismiss, slightly longer duration so users in low-bandwidth
// markets have time to read before it auto-hides.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';

enum _ToastKind { success, error, info }

void showToast(BuildContext context, String message) =>
    _show(context, message, _ToastKind.success);

void showError(BuildContext context, String message) =>
    _show(context, message, _ToastKind.error);

void showInfo(BuildContext context, String message) =>
    _show(context, message, _ToastKind.info);

void _show(BuildContext context, String message, _ToastKind kind) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  late final Color bg;
  late final Color fg;
  late final IconData icon;
  switch (kind) {
    case _ToastKind.success:
      bg = AppColors.primaryDeep;
      fg = AppColors.primary;
      icon = Icons.check_circle_rounded;
    case _ToastKind.error:
      bg = const Color(0xFF2A0F0F);
      fg = const Color(0xFFFF8A80);
      icon = Icons.error_outline_rounded;
    case _ToastKind.info:
      bg = const Color(0xFF1F1B0A);
      fg = const Color(0xFFFFC857);
      icon = Icons.info_outline_rounded;
  }
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: fg.withValues(alpha: 0.3)),
      ),
      duration: const Duration(seconds: 4),
      content: Row(
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
        ],
      ),
    ),
  );
}
