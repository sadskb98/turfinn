import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../widgets/turfinn_logo.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Corner glow blobs
          const Positioned(
            top: -60, right: -60,
            child: _GlowBlob(color: AppColors.primaryMid, size: 260),
          ),
          const Positioned(
            bottom: -60, left: -60,
            child: _GlowBlob(color: AppColors.primaryMid, size: 260),
          ),

          // Logo + tagline centred, buttons pinned to bottom
          Column(
            children: [
              const Spacer(flex: 3),
              const TurfinnLogo(fontSize: 52),
              const SizedBox(height: 10),
              Text(
                'The Home Ground of Local Legends',
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.primaryMid,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(flex: 4),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.background,
                          shape: const StadiumBorder(),
                          elevation: 0,
                        ),
                        onPressed: () => context.go(AppRoutes.signUp),
                        child: Text(
                          'Sign Up',
                          style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.background,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primary),
                          shape: const StadiumBorder(),
                          backgroundColor: AppColors.background,
                        ),
                        onPressed: () => context.go(AppRoutes.signIn),
                        child: Text(
                          'Sign in',
                          style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 120,
            spreadRadius: 60,
          ),
        ],
      ),
    );
  }
}
