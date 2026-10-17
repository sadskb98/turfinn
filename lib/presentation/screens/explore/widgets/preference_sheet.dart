import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';

class PreferenceSheet extends StatelessWidget {
  const PreferenceSheet({
    super.key,
    required this.onNearby,
    required this.onCity,
    this.onNearbyRadius,
  });
  final VoidCallback onNearby;
  final void Function(String city) onCity;
  final void Function(double km)? onNearbyRadius;

  static const _cities = [
    'Dhaka', 'Chittagong', 'Sylhet', 'Rajshahi',
    'Khulna', 'Barishal', 'Mymensingh', 'Comilla',
    'Narayanganj', 'Gazipur', 'Bogura', 'Rangpur',
  ];

  static const _radii = [3.0, 5.0, 10.0, 25.0];

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: Color(0xFF0A1F1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.primaryDeep,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text('How do you want to find turfs?',
                  style: GoogleFonts.nunito(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ),
            const SizedBox(height: 20),

            // ── Use my location ───────────────────────────────────────────
            _OptionTile(
              icon: Icons.my_location_rounded,
              title: 'Use my location',
              subtitle: 'See turfs near you',
              onTap: () { Navigator.pop(context); onNearby(); },
            ),
            const SizedBox(height: 10),

            // ── Radius quick picks ────────────────────────────────────────
            Text('  Search within a radius',
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Row(
              children: _radii.map((km) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        if (onNearbyRadius != null) onNearbyRadius!(km);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.primaryDeep),
                        ),
                        child: Center(
                          child: Text('${km.toInt()} km',
                              style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // ── City chips ────────────────────────────────────────────────
            Text('Browse by city',
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _cities.map((c) => GestureDetector(
                onTap: () { Navigator.pop(context); onCity(c); },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primaryDeep),
                  ),
                  child: Text(c,
                      style: GoogleFonts.dmSans(
                          fontSize: 13, color: AppColors.textPrimary)),
                ),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primaryDeep.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primaryDeep),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.nunito(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.dmSans(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}
