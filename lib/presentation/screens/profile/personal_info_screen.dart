import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../providers/profile_provider.dart';

class PersonalInfoScreen extends ConsumerWidget {
  const PersonalInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileNotifierProvider).valueOrNull;
    final phone = profile?.phone ?? '+880 1712-345678';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: const Icon(Icons.arrow_back_ios_new,
                        color: AppColors.primary, size: 18),
                  ),
                  const SizedBox(width: 14),
                  Text('Personal Information',
                      style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel('Accounts'),
                    const SizedBox(height: 10),
                    _InfoTile(
                        icon: Icons.phone_outlined,
                        title: 'Phone Number',
                        subtitle: phone),
                    const SizedBox(height: 8),
                    _InfoTile(
                        icon: Icons.email_outlined,
                        title: 'Email',
                        subtitle: 'rakib@example.com'),
                    const SizedBox(height: 8),
                    _InfoTile(
                        icon: Icons.location_on_outlined,
                        title: 'Primary Location',
                        subtitle: 'Bashundhara'),

                    const SizedBox(height: 28),
                    _SectionLabel('Safety'),
                    const SizedBox(height: 10),
                    _NavTile(icon: Icons.report_outlined, title: 'Report Issue'),

                    const SizedBox(height: 28),
                    _SectionLabel('Support'),
                    const SizedBox(height: 10),
                    _NavTile(icon: Icons.help_outline, title: 'Help Center & FAQ'),
                    const SizedBox(height: 8),
                    _NavTile(icon: Icons.headset_mic_outlined, title: 'Contact Support'),

                    const SizedBox(height: 28),
                    _SectionLabel('Legal'),
                    const SizedBox(height: 10),
                    _NavTile(icon: Icons.description_outlined, title: 'Terms of Service'),
                    const SizedBox(height: 8),
                    _NavTile(icon: Icons.receipt_long_outlined, title: 'Refund Policy'),
                    const SizedBox(height: 8),
                    _NavTile(icon: Icons.privacy_tip_outlined, title: 'Privacy Policy'),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.nunito(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary));
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryDeep, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryDeep,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 1),
                Text(subtitle,
                    style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
              ],
            ),
          ),
          Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryDeep, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryDeep,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary)),
          ),
          const Icon(Icons.chevron_right,
              size: 18, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}
