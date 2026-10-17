import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/sources/remote/manage_remote_source.dart';

class ManageKycPendingScreen extends ConsumerStatefulWidget {
  const ManageKycPendingScreen({super.key});

  @override
  ConsumerState<ManageKycPendingScreen> createState() => _ManageKycPendingScreenState();
}

class _ManageKycPendingScreenState extends ConsumerState<ManageKycPendingScreen> {
  bool _checking = false;

  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    try {
      final kyc = await ref.read(manageRemoteSourceProvider).getMyKyc();
      if (!mounted) return;
      final status = kyc?['status'] as String? ?? 'none';
      if (status == 'approved') {
        context.go('/');
      } else if (status == 'rejected') {
        context.go('/kyc', extra: kyc);
      }
    } catch (_) {}
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hourglass_top_rounded, size: 64, color: AppColors.primary),
                const SizedBox(height: 24),
                Text('Application Submitted', style: GoogleFonts.nunito(
                  fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                Text(
                  "We'll review your KYC documents and notify you once approved. This usually takes 1–2 business days.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary, height: 1.6),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _checking ? null : _checkStatus,
                    child: _checking
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                        : Text('Check Status', style: GoogleFonts.dmSans(
                            fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
