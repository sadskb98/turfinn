import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/booking_model.dart';

class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key, required this.booking});
  final BookingModel booking;

  String _fmtDate(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const weekdays = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[dt.weekday]}, ${dt.day} ${months[dt.month]}';
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $s';
  }

  @override
  Widget build(BuildContext context) {
    final shortId = '#TF-${booking.id.substring(0, 5).toUpperCase()}';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      GestureDetector(
                        onTap: () => context.go('/home'),
                        child: const Icon(Icons.arrow_back,
                            color: AppColors.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text('Booking Receipt',
                          style: GoogleFonts.nunito(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ]),

                    const SizedBox(height: 24),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF051210),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: AppColors.primaryDeep, width: 0.5),
                      ),
                      child: Column(
                        children: [
                          Text('Check In QR Code',
                              style: GoogleFonts.nunito(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                          const SizedBox(height: 16),

                          Container(
                            padding: const EdgeInsets.all(16),
                            color: Colors.white,
                            child: QrImageView(
                              data: booking.id,
                              version: QrVersions.auto,
                              size: 180,
                              backgroundColor: Colors.white,
                            ),
                          ),

                          const SizedBox(height: 16),
                          Text(
                            'Show this QR code at the turf for quick entry.\nNo paperwork. No waiting.',
                            style: GoogleFonts.dmSans(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                                height: 1.5),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF051210),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: AppColors.primaryDeep, width: 0.5),
                      ),
                      child: Column(
                        children: [
                          _ReceiptRow(
                              label: 'BOOKING ID',
                              value: shortId,
                              valueStyle: GoogleFonts.nunito(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                          _Divider(),
                          _ReceiptRow(label: 'Turf', value: booking.pitchName),
                          _Divider(),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Date',
                                        style: GoogleFonts.dmSans(
                                            fontSize: 11,
                                            color: AppColors.textSecondary)),
                                    Text(_fmtDate(booking.startsAt),
                                        style: GoogleFonts.dmSans(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Time',
                                        style: GoogleFonts.dmSans(
                                            fontSize: 11,
                                            color: AppColors.textSecondary)),
                                    Text(
                                        '${_fmtTime(booking.startsAt)} to ${_fmtTime(booking.endsAt)}',
                                        style: GoogleFonts.dmSans(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: const StadiumBorder(),
                        elevation: 0,
                      ),
                      onPressed: () {},
                      child: Text('Download PDF',
                          style: GoogleFonts.dmSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.black)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => context.go('/home'),
                    child: Text('Explore More Arenas',
                        style: GoogleFonts.dmSans(
                            fontSize: 14,
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.primary)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.label, required this.value, this.valueStyle});
  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: GoogleFonts.dmSans(
                fontSize: 11,
                color: AppColors.textSecondary,
                letterSpacing: 0.5)),
        const Spacer(),
        Text(value,
            style: valueStyle ??
                GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(height: 0.5, color: AppColors.primaryDeep,
          margin: const EdgeInsets.symmetric(vertical: 12));
}
