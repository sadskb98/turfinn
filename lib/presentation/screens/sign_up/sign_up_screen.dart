import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../providers/auth_provider.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;
    ref.read(authProvider.notifier).sendOTP('+88$phone');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    // Navigate to OTP screen once OTP is sent, or home on Google sign-in success
    ref.listen(authProvider, (_, next) {
      if (next is AuthOTPSent) {
        context.push(AppRoutes.otp, extra: next.phone);
      } else if (next is AuthAuthenticated) {
        context.go(AppRoutes.accountSuccess);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Glow blobs
          Positioned(
              top: -60, right: -60,
              child: _GlowBlob(color: AppColors.primaryMid, size: 260)),
          Positioned(
              bottom: -60, left: -60,
              child: _GlowBlob(color: AppColors.primaryMid, size: 260)),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Back arrow
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back,
                          color: AppColors.primary, size: 22),
                      onPressed: () => context.pop(),
                    ),
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 20),

                        // Heading
                        Text(
                          'Sign Up',
                          style: GoogleFonts.nunito(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Manage Your Matches and Compete\nwith Other Teams',
                          style: GoogleFonts.dmSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 40),

                        // Phone input
                        _PhoneInput(controller: _phoneController),

                        const SizedBox(height: 24),

                        // Sign Up button — dark green fill, calls API
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryDark,
                              foregroundColor: AppColors.background,
                              shape: const StadiumBorder(),
                              elevation: 0,
                            ),
                            onPressed: authState is AuthLoading ? null : _submit,
                            child: authState is AuthLoading
                                ? const SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primary,
                                    ))
                                : Text(
                                    'Sign Up',
                                    style: GoogleFonts.dmSans(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                          ),
                        ),

                        // Error message
                        if (authState is AuthError) ...[
                          const SizedBox(height: 8),
                          Text(
                            authState.message,
                            style: GoogleFonts.dmSans(
                                fontSize: 13, color: Colors.redAccent),
                            textAlign: TextAlign.center,
                          ),
                        ],

                        const SizedBox(height: 14),

                        // "Don't have an account? Sign In"
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Don't have an account? ",
                              style: GoogleFonts.dmSans(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => context.go(AppRoutes.signIn),
                              child: Text(
                                'Sign In',
                                style: GoogleFonts.dmSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 28),

                        // "Or" divider
                        Row(
                          children: [
                            Expanded(
                                child: Container(
                                    height: 1,
                                    color: AppColors.primaryDeep)),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'Or',
                                style: GoogleFonts.nunito(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.primaryDeep,
                                ),
                              ),
                            ),
                            Expanded(
                                child: Container(
                                    height: 1,
                                    color: AppColors.primaryDeep)),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Continue with Google
                        _SocialButton(
                          label: 'Continue with Google',
                          icon: const _GoogleIcon(),
                          onTap: authState is AuthLoading
                              ? null
                              : () => ref.read(authProvider.notifier).signInWithGoogle(),
                        ),

                        const SizedBox(height: 16),

                        // Continue with Apple
                        _SocialButton(
                          label: 'Continue with Apple',
                          icon: const Icon(Icons.apple,
                              color: AppColors.textPrimary, size: 22),
                          onTap: () {},
                        ),

                        const SizedBox(height: 40),

                        // Privacy notice
                        Text(
                          'Your data is secure with us. By continuing, you agree to our Terms & Privacy Policy.',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phone input — Bangladesh flag, dropdown chevron, divider, +88 code
// ─────────────────────────────────────────────────────────────────────────────
class _PhoneInput extends StatelessWidget {
  const _PhoneInput({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0x0D00DF82), // ~5% primary tint
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.primaryDeep, width: 1),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          // Flag + chevron
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: Container(
                  width: 26,
                  height: 26,
                  color: const Color(0xFF006A4E), // Bangladesh green
                  alignment: Alignment.center,
                  child: const Text('🇧🇩',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down,
                  color: Color(0xFF353F3F), size: 18),
            ],
          ),
          const SizedBox(width: 10),
          // Vertical divider
          Container(width: 1, height: 22, color: AppColors.primaryDeep),
          const SizedBox(width: 12),
          // Country code
          Text(
            '+88',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          // Phone number field
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Phone number',
                hintStyle: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 14),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Social button — outlined pill
// ─────────────────────────────────────────────────────────────────────────────
class _SocialButton extends StatelessWidget {
  const _SocialButton(
      {required this.label, required this.icon, required this.onTap});
  final String label;
  final Widget icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0x40009E5C)),
          shape: const StadiumBorder(),
          backgroundColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24),
        ),
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 24, height: 24, child: icon),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.primaryMid,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Google G icon
// ─────────────────────────────────────────────────────────────────────────────
class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GooglePainter());
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.38;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.17;

    final segments = [
      (color: const Color(0xFFFBC02D), start: -0.52, sweep: 1.6),
      (color: const Color(0xFFE53935), start: 1.08, sweep: 1.6),
      (color: const Color(0xFF43A047), start: 2.68, sweep: 1.6),
      (color: const Color(0xFF1E88E5), start: 4.28, sweep: 1.6),
    ];

    for (final s in segments) {
      paint.color = s.color;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        s.start,
        s.sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Glow blob helper (same as other screens)
// ─────────────────────────────────────────────────────────────────────────────
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
              spreadRadius: 60),
        ],
      ),
    );
  }
}
