// SplitInitiateSheet — bottom-sheet shown from the checkout flow when the
// captain chooses "Split with friends". Captures the team size, calls
// /bookings/split, and hands off to SSL Commerz for the captain's own
// share. After payment, the captain lands on SplitStatusScreen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/pitch_model.dart';
import '../../../data/sources/remote/booking_remote_source.dart';
import 'split_status_screen.dart';

class SplitInitiateSheet extends ConsumerStatefulWidget {
  const SplitInitiateSheet({
    super.key,
    required this.pitch,
    required this.startsAt,
    required this.endsAt,
  });

  final PitchModel pitch;
  final DateTime startsAt;
  final DateTime endsAt;

  static Future<void> show(BuildContext context, {
    required PitchModel pitch,
    required DateTime startsAt,
    required DateTime endsAt,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SplitInitiateSheet(
        pitch: pitch,
        startsAt: startsAt,
        endsAt: endsAt,
      ),
    );
  }

  @override
  ConsumerState<SplitInitiateSheet> createState() => _SplitInitiateSheetState();
}

class _SplitInitiateSheetState extends ConsumerState<SplitInitiateSheet> {
  int _players = 6;
  bool _submitting = false;

  double get _totalCost {
    final hours = widget.endsAt.difference(widget.startsAt).inHours.clamp(1, 24);
    return hours * widget.pitch.pricePerHour;
  }

  double get _perShare => _totalCost / _players;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final res = await ref.read(bookingRemoteSourceProvider).initiateSplit(
            pitchId: widget.pitch.id,
            startsAt: widget.startsAt,
            endsAt: widget.endsAt,
            totalShares: _players,
          );
      if (!mounted) return;

      // Push to status screen first so when the captain bounces back from
      // the gateway the UI is already there waiting.
      Navigator.of(context).pop();
      final ctx = context;
      Navigator.of(ctx, rootNavigator: true).push(MaterialPageRoute(
        builder: (_) => SplitStatusScreen(
          token: res.token,
          deadlineAt: res.deadlineAt,
        ),
      ));
      // Open SSL gateway. webOnlyWindowName _self keeps web bundles
      // single-tab; on mobile it opens the system browser.
      await launchUrl(
        Uri.parse(res.gatewayUrl),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_self',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not start split: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.primaryDeep,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Text('Split with friends',
                style: GoogleFonts.nunito(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('You pay your share now, we send the rest a magic link',
                style: GoogleFonts.dmSans(
                    fontSize: 13.5, color: AppColors.textSecondary)),
            const SizedBox(height: 22),

            Text('How many players?',
                style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Row(children: [
              _StepperButton(
                icon: Icons.remove_rounded,
                onTap: _players > 2 ? () => setState(() => _players--) : null,
              ),
              Expanded(
                child: Center(
                  child: Text('$_players',
                      style: GoogleFonts.nunito(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
                ),
              ),
              _StepperButton(
                icon: Icons.add_rounded,
                onTap: _players < 30 ? () => setState(() => _players++) : null,
              ),
            ]),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primaryDeep),
              ),
              child: Row(children: [
                Expanded(
                  child: Text('Your share (paid now)',
                      style: GoogleFonts.dmSans(
                          fontSize: 13.5, color: AppColors.textSecondary)),
                ),
                Text('৳${_perShare.toStringAsFixed(0)}',
                    style: GoogleFonts.nunito(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
              ]),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primaryDeep),
              ),
              child: Row(children: [
                Expanded(
                  child: Text('Total booking',
                      style: GoogleFonts.dmSans(
                          fontSize: 13.5, color: AppColors.textSecondary)),
                ),
                Text('৳${_totalCost.toStringAsFixed(0)}',
                    style: GoogleFonts.dmSans(
                        fontSize: 13.5,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(height: 22),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.background,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.background))
                    : Text('Pay my share & invite friends',
                        style: GoogleFonts.nunito(
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Slot held for 30 min. Refunded if everyone doesn\'t pay.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                    fontSize: 11.5, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap == null ? null : () {
        HapticFeedback.lightImpact();
        onTap!();
      },
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primaryDeep),
        ),
        child: Icon(icon,
            color: disabled ? AppColors.textDisabled : AppColors.primary, size: 22),
      ),
    );
  }
}
