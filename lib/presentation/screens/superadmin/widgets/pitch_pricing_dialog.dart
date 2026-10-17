import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/sources/remote/superadmin_remote_source.dart';

/// Per-pitch pricing controls for the super-admin: plan switch, fee
/// overrides, trial extension, premium grant, marketing-boost toggle.
/// Submits any subset of fields that the operator actually changed.
class PitchPricingDialog extends ConsumerStatefulWidget {
  const PitchPricingDialog({super.key, required this.pitch});
  final Map<String, dynamic> pitch;

  @override
  ConsumerState<PitchPricingDialog> createState() => _PitchPricingDialogState();
}

class _PitchPricingDialogState extends ConsumerState<PitchPricingDialog> {
  late String _plan;
  late TextEditingController _marketplaceCtl;
  late TextEditingController _walkinCtl;
  late TextEditingController _trialDaysCtl;
  DateTime? _premiumUntil;
  late bool _boost;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.pitch;
    _plan = (p['plan'] as String?) ?? 'marketplace';
    final mFee = p['marketplace_fee_bps_override'];
    final wFee = p['walkin_fee_bps_override'];
    _marketplaceCtl = TextEditingController(text: mFee == null ? '' : '$mFee');
    _walkinCtl = TextEditingController(text: wFee == null ? '' : '$wFee');
    _trialDaysCtl = TextEditingController();
    _boost = p['marketing_boost_active'] == true;
    final pa = p['premium_active_until'] as String?;
    if (pa != null && pa.isNotEmpty) {
      _premiumUntil = DateTime.tryParse(pa)?.toLocal();
    }
  }

  @override
  void dispose() {
    _marketplaceCtl.dispose();
    _walkinCtl.dispose();
    _trialDaysCtl.dispose();
    super.dispose();
  }

  Future<void> _pickPremiumDate() async {
    final now = DateTime.now();
    final initial = _premiumUntil ?? now.add(const Duration(days: 30));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: AppColors.background,
            surface: AppColors.surfaceDark,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _premiumUntil = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final src = ref.read(superAdminRemoteSourceProvider);
    final pitchId = widget.pitch['id'] as String;
    final original = widget.pitch;
    try {
      // Plan + fee overrides + trial extension
      final body = <String, dynamic>{};
      if (_plan != (original['plan'] ?? 'marketplace')) body['plan'] = _plan;

      final mText = _marketplaceCtl.text.trim();
      final origM = original['marketplace_fee_bps_override'];
      final mDesired = mText.isEmpty ? null : int.tryParse(mText);
      if (mDesired != origM) {
        body['marketplace_fee_bps_override'] = mDesired;
      }

      final wText = _walkinCtl.text.trim();
      final origW = original['walkin_fee_bps_override'];
      final wDesired = wText.isEmpty ? null : int.tryParse(wText);
      if (wDesired != origW) {
        body['walkin_fee_bps_override'] = wDesired;
      }

      final trialDays = int.tryParse(_trialDaysCtl.text.trim()) ?? 0;
      if (trialDays > 0) body['trial_extension_days'] = trialDays;

      if (body.isNotEmpty) {
        await src.setPitchPricing(
          pitchId,
          plan: body['plan'] as String?,
          marketplaceFeeBpsOverride: body.containsKey('marketplace_fee_bps_override')
              ? (body['marketplace_fee_bps_override'] as int?)
              : null,
          walkinFeeBpsOverride: body.containsKey('walkin_fee_bps_override')
              ? (body['walkin_fee_bps_override'] as int?)
              : null,
          trialExtensionDays: trialDays > 0 ? trialDays : null,
        );
      }

      // Premium grant — only call if changed.
      final origPremium = original['premium_active_until'] as String?;
      final origPremiumDt = origPremium == null ? null : DateTime.tryParse(origPremium)?.toLocal();
      final premiumChanged = (_premiumUntil?.toIso8601String() ?? '') !=
          (origPremiumDt?.toIso8601String() ?? '');
      if (premiumChanged) {
        await src.setPitchPremium(pitchId, until: _premiumUntil);
      }

      // Marketing boost toggle.
      if (_boost != (original['marketing_boost_active'] == true)) {
        await src.togglePitchAddon(
          pitchId,
          'marketing_boost',
          _boost ? 'enable' : 'disable',
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Save failed: $e'),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pitch;
    final name = p['name'] as String? ?? 'Pitch';
    final effectiveBps = (p['effective_commission_bps'] as num?)?.toInt() ?? 0;
    final effectivePct = (effectiveBps / 100).toStringAsFixed(effectiveBps % 100 == 0 ? 0 : 2);
    final trialEndsAt = p['trial_ends_at'] as String?;
    final trialDt = trialEndsAt == null ? null : DateTime.tryParse(trialEndsAt)?.toLocal();
    final trialActive = trialDt != null && trialDt.isAfter(DateTime.now());

    return Dialog(
      backgroundColor: const Color(0xFF0A1F1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: GoogleFonts.nunito(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Pricing & Premium',
                  style: GoogleFonts.dmSans(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 18),

              _ContextRow(label: 'Effective commission', value: '$effectivePct%'),
              if (trialDt != null)
                _ContextRow(
                  label: trialActive ? 'Trial ends' : 'Trial ended',
                  value: _shortDate(trialDt),
                ),
              const SizedBox(height: 18),

              _SectionLabel('Plan'),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'marketplace', label: Text('Marketplace')),
                  ButtonSegment(value: 'erp_only', label: Text('ERP-only')),
                ],
                selected: {_plan},
                onSelectionChanged: (s) => setState(() => _plan = s.first),
                style: SegmentedButton.styleFrom(
                  backgroundColor: AppColors.background,
                  foregroundColor: AppColors.textSecondary,
                  selectedBackgroundColor: AppColors.primary,
                  selectedForegroundColor: AppColors.background,
                ),
              ),
              const SizedBox(height: 16),

              _SectionLabel('Marketplace fee override (bps)'),
              const SizedBox(height: 6),
              _bpsField(
                  controller: _marketplaceCtl,
                  hint: 'blank = volume-tier default'),
              const SizedBox(height: 16),

              _SectionLabel('Walk-in fee override (bps)'),
              const SizedBox(height: 6),
              _bpsField(
                  controller: _walkinCtl,
                  hint: 'blank = config default (0)'),
              const SizedBox(height: 16),

              _SectionLabel('Extend trial by (days)'),
              const SizedBox(height: 6),
              _bpsField(
                  controller: _trialDaysCtl,
                  hint: 'e.g. 30 — leave blank for no change'),
              const SizedBox(height: 20),

              _SectionLabel('Premium ERP'),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primaryDeep),
                    ),
                    child: Text(
                      _premiumUntil == null
                          ? 'Inactive'
                          : 'Active until ${_shortDate(_premiumUntil!)}',
                      style: GoogleFonts.dmSans(
                          fontSize: 13.5, color: AppColors.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _pickPremiumDate,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDeep,
                    foregroundColor: AppColors.textPrimary,
                  ),
                  child: const Text('Pick date'),
                ),
                if (_premiumUntil != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.clear, color: AppColors.textMuted),
                    tooltip: 'Revoke premium',
                    onPressed: () => setState(() => _premiumUntil = null),
                  ),
                ],
              ]),

              const SizedBox(height: 16),
              SwitchListTile(
                value: _boost,
                onChanged: (v) => setState(() => _boost = v),
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.primary,
                title: Text('Marketing boost (500 BDT/mo)',
                    style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'Pitch ranks higher in the player app',
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: AppColors.textMuted),
                ),
              ),

              const SizedBox(height: 24),
              Row(children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background))
                      : Text('Save',
                          style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bpsField({required TextEditingController controller, required String hint}) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }

  static String _shortDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.4));
  }
}

class _ContextRow extends StatelessWidget {
  const _ContextRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Text(label, style: GoogleFonts.dmSans(fontSize: 12.5, color: AppColors.textMuted)),
        const SizedBox(width: 8),
        Text(value,
            style: GoogleFonts.dmSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      ]),
    );
  }
}
