import 'package:flutter/material.dart';

/// Turfinn brand logo — the yellow "T" mark with the TURFINN wordmark.
/// Renders the canonical logo asset; the JPEG already includes the dark
/// teal backdrop (#022026) which matches [AppColors.background], so it
/// drops onto any dark surface seamlessly.
class TurfinnLogo extends StatelessWidget {
  const TurfinnLogo({
    super.key,
    this.fontSize = 48,
    this.height,
  });

  /// Kept for backwards compatibility with the old gradient-text logo —
  /// callers passed `fontSize`. Used as a height fallback when [height]
  /// is null so existing screens keep the same visual weight.
  final double fontSize;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/turfinn_logo.png',
      height: height ?? (fontSize * 2.4),
      fit: BoxFit.contain,
    );
  }
}
