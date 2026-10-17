import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import 'billing_provider.dart';

/// Wraps a premium-only manager screen. If the manager doesn't currently
/// have an active premium grant on at least one of their pitches, the
/// child is replaced with an upgrade CTA. We treat premium as account-wide
/// (any pitch with active premium unlocks everything) — keeps v1 simple
/// and matches how the super-admin grants the toggle.
class PremiumGateView extends ConsumerWidget {
  const PremiumGateView({
    super.key,
    required this.featureName,
    required this.featureBlurb,
    required this.child,
  });

  final String featureName;
  final String featureBlurb;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billing = ref.watch(billingProvider);
    return billing.when(
      data: (b) {
        final active = b['premium_active'] == true;
        if (active) return child;
        return _UpgradeCard(
          featureName: featureName,
          featureBlurb: featureBlurb,
          monthlyBdt: (b['premium_monthly_bdt'] as num?)?.toInt() ?? 2000,
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (_, __) => _UpgradeCard(
        featureName: featureName,
        featureBlurb: featureBlurb,
        monthlyBdt: 2000,
      ),
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard({
    required this.featureName,
    required this.featureBlurb,
    required this.monthlyBdt,
  });

  final String featureName;
  final String featureBlurb;
  final int monthlyBdt;

  Future<void> _openWhatsApp() async {
    // Public Turfinn support number — same one used elsewhere in the app.
    final uri = Uri.parse('https://wa.me/8801XXXXXXXXX?text=I%20want%20to%20upgrade%20to%20Premium%20ERP');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF04404A), Color(0xFF022026)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primaryDark),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.workspace_premium_rounded, color: AppColors.primary, size: 26),
                ),
                const SizedBox(width: 12),
                Text('Premium ERP', style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ]),
              const SizedBox(height: 20),
              Text(
                'Unlock $featureName',
                style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),
              Text(
                featureBlurb,
                style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primaryDeep),
                ),
                child: Row(children: [
                  Text('৳$monthlyBdt', style: GoogleFonts.nunito(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('/ month', style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
                  ),
                  const Spacer(),
                  Text('Premium ERP', style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted)),
                ]),
              ),
              const SizedBox(height: 18),
              _bullet('Analytics Pro — heatmaps, peak-hour pricing, customer LTV'),
              _bullet('Financials Pro — P&L, VAT report, ledger export'),
              _bullet('Smart Pricing — dynamic rules engine'),
              _bullet('Campaigns — promo codes, broadcast SMS'),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openWhatsApp,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.chat_rounded, size: 18),
                  label: Text('Contact us to upgrade', style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Premium is granted manually for v1 — your account manager will activate within 1 business day.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: GoogleFonts.dmSans(fontSize: 13.5, color: AppColors.textPrimary, height: 1.5))),
        ]),
      );
}
