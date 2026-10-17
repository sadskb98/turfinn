import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../providers/auth_provider.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phone});
  final String phone;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final List<TextEditingController> _ctrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    for (final n in _nodes) n.dispose();
    super.dispose();
  }

  String get _otp => _ctrls.map((c) => c.text).join();

  void _onDigitEntered(int index, String val) {
    if (val.isNotEmpty && index < 5) {
      _nodes[index + 1].requestFocus();
    }
    setState(() {});
  }

  void _verify() {
    if (_otp.length == 6) {
      ref.read(authProvider.notifier).verifyOTP(widget.phone, _otp);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen(authProvider, (_, next) {
      if (next is AuthAuthenticated) {
        context.go(AppRoutes.accountSuccess);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(top: -60, right: -60,
              child: _GlowBlob(color: AppColors.primaryMid, size: 260)),
          Positioned(bottom: -60, left: -60,
              child: _GlowBlob(color: AppColors.primaryMid, size: 260)),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  // Back
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back,
                          color: AppColors.primary, size: 22),
                      onPressed: () => context.pop(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Text('Enter OTP',
                      style: GoogleFonts.nunito(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'We sent a 6-digit code to ${widget.phone}',
                    style: GoogleFonts.dmSans(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                        height: 1.4),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 40),

                  // 6-box OTP input
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(6, (i) => _OtpBox(
                      controller: _ctrls[i],
                      focusNode: _nodes[i],
                      onChanged: (v) => _onDigitEntered(i, v),
                      onBackspace: () {
                        if (_ctrls[i].text.isEmpty && i > 0) {
                          _nodes[i - 1].requestFocus();
                          _ctrls[i - 1].clear();
                          setState(() {});
                        }
                      },
                    )),
                  ),

                  const SizedBox(height: 36),

                  if (authState is AuthError)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(authState.message,
                          style: GoogleFonts.dmSans(
                              fontSize: 13, color: Colors.redAccent),
                          textAlign: TextAlign.center),
                    ),

                  // Verify button
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _otp.length == 6
                            ? AppColors.primary
                            : AppColors.primaryDark,
                        foregroundColor: AppColors.background,
                        shape: const StadiumBorder(),
                        elevation: 0,
                      ),
                      onPressed: authState is AuthLoading ? null : _verify,
                      child: authState is AuthLoading
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ))
                          : Text('Verify',
                              style: GoogleFonts.dmSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.background)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspace,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 56,
      child: RawKeyboardListener(
        focusNode: FocusNode(),
        onKey: (event) {
          if (event is RawKeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace) {
            onBackspace();
          }
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: GoogleFonts.nunito(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          onChanged: onChanged,
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: const Color(0x0D00DF82),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primaryDeep),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
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
              spreadRadius: 60),
        ],
      ),
    );
  }
}
