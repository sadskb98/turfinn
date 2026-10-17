import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart' show Share;
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../providers/gamification_provider.dart';
import '../../../data/models/gamification_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameProfileAsync = ref.watch(playerProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: gameProfileAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (err, __) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Failed to load profile',
                    style: GoogleFonts.dmSans(
                        fontSize: 14, color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: () => ref.invalidate(playerProfileProvider),
                  child: Text('Retry',
                      style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black)),
                ),
              ],
            ),
          ),
          data: (profile) => _buildContent(context, ref, profile),
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, WidgetRef ref, PlayerProfile profile) {
    final name = profile.name.isNotEmpty ? profile.name : 'Player';
    final isMaxLevel = profile.level >= 10;
    final xpProgress = profile.xpToNextLevel > 0
        ? (profile.xp / profile.xpToNextLevel).clamp(0.0, 1.0)
        : 1.0;

    return SingleChildScrollView(
      child: Column(
        children: [
          // -- Profile header ------------------------------------------------
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF033640), Color(0xFF022026)],
              ),
            ),
            child: Column(
              children: [
                // Avatar with gradient ring
                Stack(
                  children: [
                    Container(
                      width: 82,
                      height: 82,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryMid],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF051210),
                          ),
                          child: Center(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'P',
                              style: GoogleFonts.nunito(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('Lv${profile.level}',
                            style: GoogleFonts.dmSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.black)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(name,
                    style: GoogleFonts.nunito(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                    'Level ${profile.level} — ${profile.levelTitle}',
                    style: GoogleFonts.dmSans(
                        fontSize: 13, color: AppColors.primaryMid)),

                // -- XP progress bar ----------------------------------------
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: isMaxLevel ? 1.0 : xpProgress,
                          minHeight: 6,
                          backgroundColor: AppColors.primaryDeep,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isMaxLevel
                            ? 'MAX LEVEL'
                            : '${profile.xp} / ${profile.xpToNextLevel} XP',
                        style: GoogleFonts.dmSans(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // -- Stats row (4 items) ------------------------------------
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1F1A),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: AppColors.primaryDeep, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      _StatCell(
                          value: '${profile.totalBookings}',
                          label: 'Bookings',
                          icon: Icons.sports_soccer),
                      _StatDivider(),
                      _StatCell(
                          value: '${profile.currentStreak}w',
                          label: 'Streak',
                          icon: Icons.local_fire_department_outlined),
                      _StatDivider(),
                      _StatCell(
                          value: '${profile.coinsBalance}',
                          label: 'Coins',
                          icon: Icons.monetization_on_outlined),
                      _StatDivider(),
                      _StatCell(
                          value: '${profile.level}',
                          label: 'Level',
                          icon: Icons.emoji_events_outlined),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // -- Badges section ------------------------------------------------
          if (profile.badges.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Badges',
                      style: GoogleFonts.nunito(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: profile.badges.map((badge) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.primaryDeep, width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_badgeIcon(badge.key),
                                size: 16, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text(badge.name,
                                style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],

          // -- Referral card (collapsed by default — opt-in feature) -------
          if (profile.referralCode.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  iconColor: AppColors.textSecondary,
                  collapsedIconColor: AppColors.textSecondary,
                  leading: const Icon(Icons.card_giftcard_rounded, color: AppColors.primary, size: 20),
                  title: Text('Invite friends · earn coins',
                      style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0A1F1A), Color(0xFF071714)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primaryDeep, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.card_giftcard_rounded,
                            size: 20, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text('Invite Friends',
                            style: GoogleFonts.nunito(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('+50 coins each',
                              style: GoogleFonts.dmSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Share your code — you both earn coins!',
                        style: GoogleFonts.dmSans(
                            fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 14),
                    // Code display
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryDeep.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.2)),
                      ),
                      child: Center(
                        child: SelectableText(
                          profile.referralCode,
                          style: GoogleFonts.dmSans(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4,
                              color: AppColors.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Action buttons row
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.primaryDeep),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () {
                                final code = profile.referralCode;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Code "$code" copied!'),
                                    backgroundColor: AppColors.primaryDeep,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded,
                                  size: 15, color: AppColors.textSecondary),
                              label: Text('Copy',
                                  style: GoogleFonts.dmSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                              ),
                              onPressed: () {
                                Share.share(
                                    'Join me on Turfinn! Use code ${profile.referralCode} for bonus coins. ${AppConfig.referralUrl(profile.referralCode)}');
                              },
                              icon: const Icon(Icons.share_rounded,
                                  size: 15, color: Colors.black),
                              label: Text('Share',
                                  style: GoogleFonts.dmSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 8),

          // -- Menu items ----------------------------------------------------
          _MenuItem(
            icon: Icons.person_outline_rounded,
            label: 'Personal Information',
            onTap: () => context.push(AppRoutes.personalInfo),
          ),
          _MenuItem(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Financial Information',
            onTap: () => context.push(AppRoutes.financialInfo),
          ),
          _MenuItem(
            icon: Icons.sports_soccer_rounded,
            label: 'My Matches',
            onTap: () => context.push(AppRoutes.myMatches),
          ),
          _MenuItem(
            icon: Icons.history_rounded,
            label: 'Activity & History',
            onTap: () => context.push(AppRoutes.activity),
          ),
          _MenuItem(
            icon: Icons.help_outline_rounded,
            label: 'Support & Help',
            onTap: () => _showSupportSheet(context),
          ),
          _MenuItem(
            icon: Icons.logout_rounded,
            label: 'Log Out',
            onTap: () => _confirmLogout(context),
            isDestructive: true,
          ),

          const SizedBox(height: 20),

          // -- Action buttons ------------------------------------------------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _ActionBtn(
                  label: 'Share Profile',
                  outlined: true,
                  onTap: () {
                    Share.share(
                        'Check out my Turfinn profile! ${profile.totalBookings} bookings, Level ${profile.level} ${profile.levelTitle}');
                  },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      elevation: 0,
                    ),
                    onPressed: () => context.push(AppRoutes.profileSetup),
                    child: Text('Edit Profile',
                        style: GoogleFonts.dmSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  IconData _badgeIcon(String key) {
    switch (key) {
      case 'first_booking':
        return Icons.sports_soccer;
      case 'streak_3':
      case 'streak_master':
        return Icons.local_fire_department_outlined;
      case 'social_butterfly':
        return Icons.group_outlined;
      case 'early_bird':
        return Icons.wb_sunny_outlined;
      case 'night_owl':
        return Icons.nightlight_outlined;
      default:
        return Icons.emoji_events_outlined;
    }
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1F1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Log Out',
            style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        content: Text('Are you sure you want to log out?',
            style: GoogleFonts.dmSans(
                fontSize: 14, color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('auth_token');
              if (context.mounted) context.go(AppRoutes.welcome);
            },
            child: Text('Log Out',
                style: GoogleFonts.dmSans(
                    color: Colors.redAccent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showSupportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A1F1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.primaryDeep,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Support & Help',
                style: GoogleFonts.nunito(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            _SupportTile(
              icon: Icons.chat_rounded,
              iconColor: const Color(0xFF25D366),
              label: 'WhatsApp Support',
              subtitle: 'Tap to message · fastest reply',
              onTap: () => _launchWhatsApp(ctx),
            ),
            _SupportTile(
              icon: Icons.email_outlined,
              label: 'Email Support',
              subtitle: 'support@turfinn.app',
              onTap: () => _launchEmail(ctx),
            ),
            _SupportTile(
              icon: Icons.phone_rounded,
              label: 'Call us',
              subtitle: '+880 1700-000000 · 9AM-10PM',
              onTap: () => _launchPhone(ctx),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
class _StatCell extends StatelessWidget {
  const _StatCell(
      {required this.value, required this.label, required this.icon});
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(height: 4),
          Text(value,
              style: GoogleFonts.nunito(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 9, color: AppColors.textSecondary),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 0.5, height: 40, color: AppColors.primaryDeep);
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? Colors.redAccent : AppColors.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.primary.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDestructive
                      ? Colors.redAccent.withValues(alpha: 0.1)
                      : AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    color: isDestructive ? Colors.redAccent : AppColors.primary,
                    size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label,
                    style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: color)),
              ),
              if (!isDestructive)
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn(
      {required this.label, required this.outlined, required this.onTap});
  final String label;
  final bool outlined;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.primaryDeep),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30)),
        ),
        onPressed: onTap,
        child: Text(label,
            style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary)),
      ),
    );
  }
}

class _SupportTile extends StatelessWidget {
  const _SupportTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.iconColor,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = iconColor ?? AppColors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: c, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  Text(subtitle,
                      style: GoogleFonts.dmSans(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Support launchers — fire-and-forget. We never throw on failure (e.g. no
/// dialer / no email client) because this is auxiliary tooling; failure
/// shows a snackbar and leaves the user where they were.
Future<void> _launchWhatsApp(BuildContext ctx) async {
  // Pre-filled greeting so the user doesn't have to think about what to type.
  final url = Uri.parse(
      'https://wa.me/8801700000000?text=${Uri.encodeComponent("Hi Turfinn support, I need help with: ")}');
  if (await canLaunchUrl(url)) {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  } else if (ctx.mounted) {
    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('Install WhatsApp to use this option.')));
  }
}

Future<void> _launchEmail(BuildContext ctx) async {
  final url = Uri.parse(
      'mailto:support@turfinn.app?subject=${Uri.encodeComponent("App support")}');
  if (await canLaunchUrl(url)) {
    await launchUrl(url);
  } else if (ctx.mounted) {
    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('No email app available on this device.')));
  }
}

Future<void> _launchPhone(BuildContext ctx) async {
  final url = Uri.parse('tel:+8801700000000');
  if (await canLaunchUrl(url)) {
    await launchUrl(url);
  } else if (ctx.mounted) {
    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('Could not open dialer.')));
  }
}
