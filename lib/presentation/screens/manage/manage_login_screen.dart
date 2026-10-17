import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/sources/remote/manage_remote_source.dart';

class ManageLoginScreen extends ConsumerStatefulWidget {
  const ManageLoginScreen({super.key});

  @override
  ConsumerState<ManageLoginScreen> createState() => _ManageLoginScreenState();
}

class _ManageLoginScreenState extends ConsumerState<ManageLoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _otpSent = false;
  bool _loading = false;
  String? _error;
  String? _devOtp;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final src = ref.read(manageRemoteSourceProvider);
      final resp = await src.sendOtp(phone);
      setState(() { _otpSent = true; _devOtp = resp; });
    } catch (e) {
      setState(() => _error = 'Failed to send OTP. Check your number.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyOtp() async {
    final phone = _phoneCtrl.text.trim();
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) return;
    setState(() { _loading = true; _error = null; });
    try {
      final src = ref.read(manageRemoteSourceProvider);
      final data = await src.verifyOtp(phone, otp);
      final token = data['token'] as String;
      final prefs = await SharedPreferences.getInstance();
      // Both keys: manager_token for our own gate logic in main_manage.dart,
      // auth_token for the dio client interceptor (which is shared with
      // the player + super-admin builds).
      await prefs.setString('manager_token', token);
      await prefs.setString('auth_token', token);
      if (!mounted) return;
      context.go('/');
    } catch (e) {
      setState(() => _error = 'Invalid OTP. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Turf Manager', style: GoogleFonts.nunito(
                  fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.primary)),
                const SizedBox(height: 8),
                Text('Sign in to your dashboard', style: GoogleFonts.dmSans(
                  fontSize: 15, color: AppColors.textSecondary)),
                const SizedBox(height: 40),
                _field('Phone number', _phoneCtrl, enabled: !_otpSent,
                    hint: '+8801XXXXXXXXX', keyboardType: TextInputType.phone),
                if (_otpSent) ...[
                  const SizedBox(height: 16),
                  _field('OTP code', _otpCtrl, hint: '6-digit code',
                      keyboardType: TextInputType.number),
                  if (_devOtp != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Dev OTP: $_devOtp',
                          style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.primary)),
                    ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: GoogleFonts.dmSans(fontSize: 13, color: Colors.redAccent)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _loading ? null : (_otpSent ? _verifyOtp : _sendOtp),
                    child: _loading
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black))
                        : Text(_otpSent ? 'Verify OTP' : 'Send OTP',
                            style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {bool enabled = true, String? hint, TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          enabled: enabled,
          keyboardType: keyboardType,
          style: GoogleFonts.dmSans(fontSize: 15, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.surfaceDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primaryDeep),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primaryDeep),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}
