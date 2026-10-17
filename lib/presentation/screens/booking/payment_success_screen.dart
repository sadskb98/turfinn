import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/booking_model.dart';

class PaymentSuccessScreen extends StatelessWidget {
  const PaymentSuccessScreen({super.key, this.booking});
  final BookingModel? booking;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF051210),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.primaryDeep, width: 0.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_outline,
                        color: Colors.black, size: 52),
                  ),
                  const SizedBox(height: 24),
                  Text('Payment Successful',
                      style: GoogleFonts.nunito(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Text(
                    'Your slot is confirmed &\nBooked. Get ready for kickoff.',
                    style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Check Booking Details
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: const StadiumBorder(),
                        elevation: 0,
                      ),
                      onPressed: () {
                        if (booking != null) {
                          context.go('/receipt', extra: booking!);
                        } else {
                          context.go('/home');
                        }
                      },
                      child: Text('Check Booking Details',
                          style: GoogleFonts.dmSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.black)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Build Your Team
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.primary),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => context.go('/home'),
                      child: Text('Build Your Team',
                          style: GoogleFonts.dmSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
