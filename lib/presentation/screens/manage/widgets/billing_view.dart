import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import 'billing_provider.dart';

/// Sidebar entry showing the manager's plan, trial countdown, premium
/// status, and per-pitch effective commission. Mostly read-only for v1 —
/// premium grant + add-on toggles are handled by the super-admin.
class BillingView extends ConsumerWidget {
  const BillingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billing = ref.watch(billingProvider);
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(billingProvider);
        await ref.read(billingProvider.future);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(28),
        child: billing.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
          ),
          error: (e, _) => _ErrorCard(message: e.toString()),
          data: (b) => _Body(b: b),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.b});
  final Map<String, dynamic> b;

  @override
  Widget build(BuildContext context) {
    final pitches = (b['pitches'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final premiumActive = b['premium_active'] == true;
    final monthlyBdt = (b['premium_monthly_bdt'] as num?)?.toInt() ?? 2000;
    final settlementBdt = (b['settlement_pending_bdt'] as num?)?.toDouble() ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Billing', style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text('Your plan, trial, and pending settlement', style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
        const SizedBox(height: 24),

        // Top KPIs
        LayoutBuilder(builder: (ctx, box) {
          final cols = box.maxWidth > 800 ? 3 : (box.maxWidth > 500 ? 2 : 1);
          final w = (box.maxWidth - (cols - 1) * 16) / cols;
          return Wrap(spacing: 16, runSpacing: 16, children: [
            SizedBox(width: w, child: _KpiCard(
              label: 'Premium ERP',
              value: premiumActive ? 'Active' : 'Inactive',
              icon: Icons.workspace_premium_rounded,
              accent: premiumActive ? AppColors.primary : AppColors.textMuted,
              hint: premiumActive ? 'All advanced screens unlocked' : '৳$monthlyBdt / month — contact us to upgrade',
            )),
            SizedBox(width: w, child: _KpiCard(
              label: 'Pending Settlement',
              value: '৳${settlementBdt.toStringAsFixed(0)}',
              icon: Icons.account_balance_wallet_rounded,
              accent: AppColors.primary,
              hint: 'Cleared every Monday morning',
            )),
            SizedBox(width: w, child: _KpiCard(
              label: 'My Pitches',
              value: '${pitches.length}',
              icon: Icons.stadium_rounded,
              accent: Colors.blueAccent,
              hint: 'On the marketplace plan unless noted',
            )),
          ]);
        }),

        const SizedBox(height: 32),
        Text('Per-pitch billing', style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 12),

        if (pitches.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primaryDeep),
            ),
            child: Text(
              'No pitches yet. Reach out to your account manager to onboard your turf.',
              style: GoogleFonts.dmSans(fontSize: 13.5, color: AppColors.textSecondary),
            ),
          )
        else
          ...pitches.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PitchBillingCard(p: p),
              )),

        const SizedBox(height: 24),
        _AvivExplainerCard(),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value, required this.icon, required this.accent, required this.hint});
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryDeep),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary))),
        ]),
        const SizedBox(height: 14),
        Text(value, style: GoogleFonts.nunito(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(hint, style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted, height: 1.4)),
      ]),
    );
  }
}

class _PitchBillingCard extends StatelessWidget {
  const _PitchBillingCard({required this.p});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    final name = p['pitch_name'] as String? ?? 'Pitch';
    final plan = (p['plan'] as String? ?? 'marketplace');
    final effectiveBps = (p['effective_commission_bps'] as num?)?.toInt() ?? 0;
    final monthlyVolume = (p['monthly_volume'] as num?)?.toInt() ?? 0;
    final boost = p['marketing_boost_active'] == true;
    final trialEndsAt = p['trial_ends_at'] as String?;
    final trialActive = p['trial_active'] == true;

    final pct = (effectiveBps / 100).toStringAsFixed(effectiveBps % 100 == 0 ? 0 : 2);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryDeep),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(name, style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
          _Chip(label: plan == 'erp_only' ? 'ERP Only' : 'Marketplace', color: plan == 'erp_only' ? Colors.purpleAccent : AppColors.primary),
          if (trialActive) ...[
            const SizedBox(width: 6),
            const _Chip(label: 'Trial', color: Colors.orangeAccent),
          ],
          if (boost) ...[
            const SizedBox(width: 6),
            const _Chip(label: 'Boost', color: Colors.amber),
          ],
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 32, runSpacing: 12, children: [
          _Stat(label: 'Effective commission', value: '$pct%'),
          _Stat(label: 'This month bookings', value: '$monthlyVolume'),
          if (trialEndsAt != null) _Stat(label: trialActive ? 'Trial ends' : 'Trial ended', value: _shortDate(trialEndsAt)),
        ]),
      ]),
    );
  }

  static String _shortDate(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted)),
      const SizedBox(height: 2),
      Text(value, style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: GoogleFonts.dmSans(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _AvivExplainerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryDeep),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('How marketplace commission works', style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        _bullet('60-day free trial — 0% commission while you ramp up'),
        _bullet('Volume tiers — 12% on the first 30 monthly bookings, 10% from 31, 8% from 101'),
        _bullet('Walk-ins are free — turn on cash-handling for 2% if you want us to collect via the app'),
      ]),
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.fiber_manual_record, color: AppColors.primary, size: 8),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary, height: 1.5))),
        ]),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Could not load billing', style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(message, style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted)),
      ]),
    );
  }
}
