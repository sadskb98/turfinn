// Super-admin login. Email + password (NOT phone OTP) — operator
// credentials live in Consul under SUPER_ADMIN_EMAIL / SUPER_ADMIN_PASSWORD
// and are validated server-side.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/sources/remote/dio_client.dart';

class SuperAdminLoginScreen extends ConsumerStatefulWidget {
  const SuperAdminLoginScreen({super.key});

  @override
  ConsumerState<SuperAdminLoginScreen> createState() =>
      _SuperAdminLoginScreenState();
}

class _SuperAdminLoginScreenState extends ConsumerState<SuperAdminLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _passwordVisible = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email and password are required.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post('/auth/super-admin-login', data: {
        'email': email,
        'password': password,
      });
      final data = resp.data['data'] as Map<String, dynamic>;
      final token = data['token'] as String;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
      await prefs.setString('superadmin_token', token);
      if (!mounted) return;
      context.go('/');
    } catch (_) {
      // Server returns 401 on bad creds — never expose the actual reason.
      setState(() => _error = 'Invalid email or password.');
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
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded,
                      color: Colors.black, size: 30),
                ),
                const SizedBox(height: 20),
                Text('Turfinn Super Admin',
                    style: GoogleFonts.nunito(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
                const SizedBox(height: 6),
                Text('Restricted access — email + password.',
                    style: GoogleFonts.dmSans(
                        fontSize: 14, color: AppColors.textSecondary)),
                const SizedBox(height: 36),
                _label('Email'),
                _textField(
                  controller: _emailCtrl,
                  hint: 'admin@turfinn.com',
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username, AutofillHints.email],
                ),
                const SizedBox(height: 18),
                _label('Password'),
                _textField(
                  controller: _passwordCtrl,
                  hint: 'Enter your password',
                  obscure: !_passwordVisible,
                  onSubmit: (_) => _submit(),
                  suffix: IconButton(
                    icon: Icon(
                      _passwordVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _passwordVisible = !_passwordVisible),
                  ),
                  autofillHints: const [AutofillHints.password],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: GoogleFonts.dmSans(
                                  fontSize: 13, color: Colors.redAccent)),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black))
                        : Text('Sign in',
                            style: GoogleFonts.nunito(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s,
            style: GoogleFonts.dmSans(
                fontSize: 13, color: AppColors.textSecondary)),
      );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    TextInputType? keyboardType,
    Widget? suffix,
    Iterable<String>? autofillHints,
    ValueChanged<String>? onSubmit,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      onSubmitted: onSubmit,
      style:
          GoogleFonts.dmSans(fontSize: 15, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary),
        filled: true,
        fillColor: const Color(0xFF0A1F1A),
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primaryDeep),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primaryDeep),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
