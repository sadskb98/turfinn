import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';

class MapTopBar extends StatelessWidget {
  const MapTopBar({
    super.key,
    required this.locationLabel,
    required this.onLocationTap,
    required this.onSearchTap,
    this.radiusKm,
    this.onRadiusChanged,
  });

  final String locationLabel;
  final VoidCallback onLocationTap;
  final VoidCallback onSearchTap;
  final double? radiusKm;
  final ValueChanged<double>? onRadiusChanged;

  static const _options = [3.0, 5.0, 10.0, 25.0, 0.0];

  String _label(double km) => km <= 0 ? 'All' : '${km.round()} km';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            GestureDetector(
              onTap: onLocationTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xE6040E0E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primaryDeep),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      locationLabel == 'Nearby' ? Icons.my_location : Icons.location_city,
                      size: 14,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(locationLabel,
                        style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(width: 2),
                    const Icon(Icons.keyboard_arrow_down,
                        size: 16, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (radiusKm != null && onRadiusChanged != null)
              PopupMenuButton<double>(
                initialValue: radiusKm,
                onSelected: onRadiusChanged,
                color: const Color(0xFF033640),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.primaryDeep),
                ),
                itemBuilder: (_) => _options
                    .map((km) => PopupMenuItem<double>(
                          value: km,
                          child: Text(
                            _label(km),
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: radiusKm == km
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ))
                    .toList(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xE6040E0E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primaryDeep),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _label(radiusKm!),
                        style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.keyboard_arrow_down,
                          size: 16, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
            const Spacer(),
            GestureDetector(
              onTap: onSearchTap,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xE6040E0E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primaryDeep),
                ),
                child: const Icon(Icons.search, color: AppColors.primary, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
