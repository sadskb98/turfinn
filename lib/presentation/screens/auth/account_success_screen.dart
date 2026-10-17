import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../providers/profile_provider.dart';

class AccountSuccessScreen extends ConsumerStatefulWidget {
  const AccountSuccessScreen({super.key});

  @override
  ConsumerState<AccountSuccessScreen> createState() =>
      _AccountSuccessScreenState();
}

class _AccountSuccessScreenState extends ConsumerState<AccountSuccessScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnim = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();

    // Returning user with a populated profile → straight to home. New user →
    // profile setup. We give the welcome animation 1.5s either way so the
    // transition doesn't feel jarring.
    Future.delayed(const Duration(milliseconds: 1500), _routeNext);
  }

  Future<void> _routeNext() async {
    if (!mounted) return;
    try {
      final profile = await ref.read(profileNotifierProvider.future);
      if (!mounted) return;
      final hasProfile = profile != null &&
          profile.name.trim().isNotEmpty &&
          profile.position.trim().isNotEmpty;
      context.go(hasProfile ? AppRoutes.home : AppRoutes.profileSetup);
    } catch (_) {
      if (mounted) context.go(AppRoutes.profileSetup);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              decoration: BoxDecoration(
                color: const Color(0xFF051A14),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: AppColors.primaryDeep.withValues(alpha: 0.5), width: 0.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Celebration icon
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.15),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Green circle bg
                        Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary,
                          ),
                        ),
                        // Party hat / confetti icon
                        const Icon(Icons.celebration_rounded,
                            size: 40, color: Colors.black),
                        // Small sparkle dots
                        Positioned(
                          top: 8,
                          right: 12,
                          child: _Sparkle(size: 6),
                        ),
                        Positioned(
                          top: 16,
                          left: 8,
                          child: _Sparkle(size: 4),
                        ),
                        Positioned(
                          bottom: 14,
                          right: 6,
                          child: _Sparkle(size: 5),
                        ),
                        // Checkmark badge
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary,
                            ),
                            child: const Icon(Icons.check,
                                size: 14, color: Colors.black),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Text(
                    'Congratulations!!',
                    style: GoogleFonts.nunito(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'Your account has been Successfully\nCreated. Enjoy Your Game.',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
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

class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary,
      ),
    );
  }
}
