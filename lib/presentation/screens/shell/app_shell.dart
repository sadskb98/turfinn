import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../presentation/providers/gamification_provider.dart';
import '../../../presentation/providers/profile_provider.dart';
import '../home/home_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  Offset _fabOffset = const Offset(16, 300);
  bool _fabDragging = false;

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    if (loc.startsWith(AppRoutes.explore)) return 1;
    if (loc.startsWith(AppRoutes.teams)) return 2;
    if (loc.startsWith(AppRoutes.feed)) return 3;
    if (loc.startsWith(AppRoutes.sports)) return 4;
    return 0;
  }

  bool _showFab(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    return !loc.startsWith(AppRoutes.explore) &&
        !loc.startsWith(AppRoutes.teams) &&
        !loc.startsWith(AppRoutes.sports);
  }

  void _showGamification() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _GamificationSheet(ref: ref),
    );
  }

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);
    final showFab = _showFab(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: Stack(
        children: [
          widget.child,

          // ── Draggable cup FAB ─────────────────────────────────────────
          if (showFab)
            AnimatedPositioned(
              duration: _fabDragging
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              left: _fabOffset.dx,
              top: _fabOffset.dy,
              child: GestureDetector(
                onPanStart: (_) => setState(() => _fabDragging = true),
                onPanUpdate: (d) {
                  final size = MediaQuery.of(context).size;
                  setState(() {
                    _fabOffset = Offset(
                      (_fabOffset.dx + d.delta.dx).clamp(0, size.width - 56),
                      (_fabOffset.dy + d.delta.dy).clamp(0, size.height - 140),
                    );
                  });
                },
                onPanEnd: (_) {
                  final size = MediaQuery.of(context).size;
                  const pad = 16.0;
                  final cx = _fabOffset.dx + 26;
                  setState(() {
                    _fabDragging = false;
                    _fabOffset = Offset(
                      cx < size.width / 2 ? pad : size.width - 56 - pad,
                      _fabOffset.dy.clamp(pad, size.height - 140 - pad),
                    );
                  });
                },
                onTap: _showGamification,
                // Smaller + dimmer than before — gamification is opt-in, not
                // a primary action. Users who want it can still drag it
                // around; new users barely notice it.
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1F1A).withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.25),
                        width: 1),
                  ),
                  child: const Icon(Icons.emoji_events_outlined,
                      color: Color(0xFFFFD700), size: 18),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF040E0E),
          border: Border(
              top: BorderSide(
                  color: AppColors.primaryDeep.withValues(alpha: 0.5),
                  width: 0.5)),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                _NavTab(
                    icon: Icons.home_rounded,
                    label: tr(context, 'nav.home'),
                    active: idx == 0,
                    onTap: () => context.go(AppRoutes.home)),
                _NavTab(
                    icon: Icons.explore_outlined,
                    label: tr(context, 'nav.explore'),
                    active: idx == 1,
                    onTap: () => context.go(AppRoutes.explore)),
                // Teams center tab — visually distinct (raised + glow) for
                // prominence as the team-building + matchmaking hub.
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      onTap: () => context.go(AppRoutes.teams),
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: idx == 2
                              ? AppColors.primary
                              : const Color(0xFF0A1F1A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppColors.primary,
                              width: idx == 2 ? 0 : 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.groups_2_rounded,
                          color: idx == 2
                              ? Colors.black
                              : AppColors.primary,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
                _NavTab(
                    icon: Icons.sports_soccer_rounded,
                    label: tr(context, 'nav.play'),
                    active: idx == 3,
                    onTap: () => context.go(AppRoutes.feed)),
                _NavTab(
                    icon: Icons.article_outlined,
                    label: tr(context, 'nav.feed'),
                    active: idx == 4,
                    onTap: () => context.go(AppRoutes.sports)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gamification bottom sheet (moved from HomeScreen)
// ─────────────────────────────────────────────────────────────────────────────
class _GamificationSheet extends ConsumerWidget {
  const _GamificationSheet({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef wRef) {
    final challengesAsync = wRef.watch(weeklyChallengesProvider);
    final gameProfileAsync = wRef.watch(playerProfileProvider);
    final checkinAsync = wRef.watch(checkinStatusProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF033640),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(
              top: BorderSide(color: AppColors.primaryDeep, width: 0.5)),
        ),
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.primaryDeep,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.emoji_events_rounded,
                    color: Color(0xFFFFD700), size: 20),
                const SizedBox(width: 8),
                Text('Your Progress',
                    style: GoogleFonts.nunito(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const Spacer(),
                gameProfileAsync.when(
                  data: (p) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${p.xp} XP · ${p.levelTitle}',
                        style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Leaderboard
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.leaderboard);
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1F1A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.primaryDeep.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Icon(Icons.leaderboard_rounded,
                            size: 22, color: Color(0xFFFFD700)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Weekly Leaderboard',
                              style: GoogleFonts.nunito(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                          const SizedBox(height: 2),
                          Text(
                            gameProfileAsync.when(
                              data: (p) =>
                                  'You have ${p.xp} XP — see your rank',
                              loading: () => 'Earn XP to climb the ranks',
                              error: (_, __) => 'Earn XP to climb the ranks',
                            ),
                            style: GoogleFonts.dmSans(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondary, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Daily check-in
            DailyCheckinCard(
              checkinAsync: checkinAsync,
              onCheckin: () =>
                  wRef.read(checkinNotifierProvider.notifier).checkin(),
            ),
            const SizedBox(height: 20),
            const SizedBox(height: 10),
            WeeklyChallengesSection(challengesAsync: challengesAsync),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nav tab
// ─────────────────────────────────────────────────────────────────────────────
class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textSecondary;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(label,
                style: GoogleFonts.dmSans(
                  color: color,
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                )),
            if (active)
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 16,
                height: 2,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
