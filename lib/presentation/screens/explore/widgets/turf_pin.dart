import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';

/// Map marker showing a stadium icon + price.
/// White pill with downward pointer by default; green when selected.
class TurfPin extends StatelessWidget {
  const TurfPin({
    super.key,
    required this.price,
    this.isSelected = false,
  });

  final double price;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final bg = isSelected ? AppColors.primary : AppColors.white;
    final fg = isSelected ? AppColors.black : AppColors.background;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withValues(alpha: 0.30),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.stadium_rounded, size: 13, color: fg),
              const SizedBox(width: 4),
              Text(
                '\u09F3${price.round()}',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: fg,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
        CustomPaint(
          size: const Size(12, 7),
          painter: _PointerPainter(color: bg),
        ),
      ],
    );
  }
}

class _PointerPainter extends CustomPainter {
  const _PointerPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PointerPainter old) => old.color != color;
}
