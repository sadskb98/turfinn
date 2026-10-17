import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/pitch_model.dart';

// This screen is referenced by router but booking now handled inside TurfDetailScreen
// Keeping as a stub to satisfy imports
class BookingCalendarScreen extends StatelessWidget {
  const BookingCalendarScreen({
    super.key,
    required this.pitch,
    required this.selectedSlotStart,
    required this.selectedSlotEnd,
  });
  final PitchModel pitch;
  final DateTime selectedSlotStart;
  final DateTime selectedSlotEnd;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Text('Calendar',
            style: GoogleFonts.nunito(color: AppColors.textPrimary)),
      ),
    );
  }
}
