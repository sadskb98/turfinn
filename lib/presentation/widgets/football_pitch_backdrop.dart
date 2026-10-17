import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Renders a top-down football pitch with dark overlay —
/// matches the Figma "Gemini_Generated_Image" backdrop used
/// in the splash / welcome logo section.
class FootballPitchBackdrop extends StatelessWidget {
  const FootballPitchBackdrop({
    super.key,
    this.width = double.infinity,
    this.height = 220,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        child: CustomPaint(
          painter: _PitchPainter(),
          child: Container(
            // Dark green gradient overlay — matches Figma filters:
            // exposure +0.19, contrast -0.3, temperature -0.58
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xCC020E0B), // ~80% dark at top
                  Color(0x99021A10), // ~60% dark at bottom
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Alternating dark-green stripes (mown grass effect) ──
    final stripe1 = Paint()..color = const Color(0xFF0D3B20);
    final stripe2 = Paint()..color = const Color(0xFF0A2E18);
    const stripeCount = 12;
    final sw = w / stripeCount;
    for (int i = 0; i < stripeCount; i++) {
      canvas.drawRect(
        Rect.fromLTWH(i * sw, 0, sw, h),
        i.isEven ? stripe1 : stripe2,
      );
    }

    final linePaint = Paint()
      ..color = const Color(0xFF1A6B3A).withValues(alpha: 0.55)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    // ── Pitch boundary ──
    final margin = Size(w * 0.06, h * 0.09);
    final pitchRect = Rect.fromLTWH(
      margin.width, margin.height,
      w - margin.width * 2, h - margin.height * 2,
    );
    canvas.drawRect(pitchRect, linePaint);

    // ── Centre line ──
    canvas.drawLine(
      Offset(w / 2, pitchRect.top),
      Offset(w / 2, pitchRect.bottom),
      linePaint,
    );

    // ── Centre circle ──
    canvas.drawCircle(
      Offset(w / 2, h / 2),
      h * 0.18,
      linePaint,
    );

    // ── Centre spot ──
    canvas.drawCircle(
      Offset(w / 2, h / 2),
      2.5,
      linePaint..style = PaintingStyle.fill,
    );
    linePaint.style = PaintingStyle.stroke;

    // ── Penalty boxes (left & right) ──
    final boxW = w * 0.14;
    final boxH = h * 0.45;
    final boxTop = (h - boxH) / 2;

    // Left box
    canvas.drawRect(
      Rect.fromLTWH(pitchRect.left, boxTop, boxW, boxH),
      linePaint,
    );
    // Right box
    canvas.drawRect(
      Rect.fromLTWH(pitchRect.right - boxW, boxTop, boxW, boxH),
      linePaint,
    );

    // ── Goal areas ──
    final goalW = w * 0.055;
    final goalH = h * 0.22;
    final goalTop = (h - goalH) / 2;
    canvas.drawRect(
      Rect.fromLTWH(pitchRect.left, goalTop, goalW, goalH),
      linePaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(pitchRect.right - goalW, goalTop, goalW, goalH),
      linePaint,
    );

    // ── Penalty arcs ──
    canvas.drawArc(
      Rect.fromCircle(
          center: Offset(pitchRect.left + boxW, h / 2),
          radius: h * 0.11),
      -math.pi / 2.5,
      math.pi / 1.25,
      false,
      linePaint,
    );
    canvas.drawArc(
      Rect.fromCircle(
          center: Offset(pitchRect.right - boxW, h / 2),
          radius: h * 0.11),
      math.pi - math.pi / 2.5,
      math.pi / 1.25,
      false,
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
