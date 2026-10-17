import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/pitch_model.dart';
import '../../../data/sources/remote/dio_client.dart';
import '../../providers/booking_provider.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({
    super.key,
    required this.pitch,
    required this.startsAt,
    required this.endsAt,
    required this.method,
    required this.totalCost,
  });
  final PitchModel pitch;
  final DateTime startsAt;
  final DateTime endsAt;
  final String method;
  final double totalCost;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  final _ctrl = TextEditingController();

  /// Selected payment mode. Initialised to the pitch's default; user can
  /// override via the toggle if both modes are allowed by the pitch.
  late String _mode = widget.pitch.defaultPaymentMode.isEmpty
      ? 'partial_online'
      : widget.pitch.defaultPaymentMode;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _isSSL => widget.method == 'bank';

  /// Amount the gateway charges. Equals the full cost in full_online mode,
  /// or just the platform commission (15% by default) in partial_online.
  /// Mirrors the backend's payment_service split — must stay in lockstep.
  double _onlineAmount() {
    if (_mode == 'partial_online') {
      return widget.totalCost * 0.15;
    }
    return widget.totalCost;
  }

  Future<void> _pay() async {
    // Mode is whatever the user picked on the toggle (or the pitch's
    // default if no toggle was shown). The breakdown card below the button
    // shows the exact split so the user knows what they're committing to.
    await ref.read(bookingNotifierProvider.notifier).create(
          pitchId: widget.pitch.id,
          startsAt: widget.startsAt,
          endsAt: widget.endsAt,
          paymentMode: _mode,
        );
    final state = ref.read(bookingNotifierProvider);
    if (!mounted) return;
    if (state is! BookingSuccess) return;

    if (_isSSL) {
      try {
        final dio = ref.read(dioProvider);
        final res = await dio.post('/bookings/${state.booking.id}/pay');
        final gatewayUrl = res.data['data']['redirect_url'] as String?;
        if (gatewayUrl != null && gatewayUrl.isNotEmpty) {
          await launchUrl(Uri.parse(gatewayUrl), mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open payment gateway. Try again.')),
        );
      }
      return;
    }

    // bKash / Nagad — not yet integrated, go to success for now
    context.go('/payment/success', extra: state.booking);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookingNotifierProvider);
    final isLoading = state is BookingLoading;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back + title
              Row(children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: const Icon(Icons.arrow_back, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Text('Payment',
                    style: GoogleFonts.nunito(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ]),
              const SizedBox(height: 28),

              if (_isSSL) ...[
                // ── SSLCommerz gateway card ──────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1F1A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF1E88E5).withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    children: [
                      // SSLCommerz brand badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E88E5).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_outline,
                                size: 18, color: Color(0xFF1E88E5)),
                            const SizedBox(width: 8),
                            Text('SSLCommerz',
                                style: GoogleFonts.nunito(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1E88E5))),
                            const SizedBox(width: 6),
                            Text('Secure',
                                style: GoogleFonts.dmSans(
                                    fontSize: 13, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'You\'ll be redirected to SSLCommerz\'s secure checkout page to complete your payment.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(
                            fontSize: 13, color: AppColors.textSecondary, height: 1.5),
                      ),
                      const SizedBox(height: 16),
                      // Accepted methods row
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: const [
                          _MethodBadge(label: 'Visa'),
                          _MethodBadge(label: 'Mastercard'),
                          _MethodBadge(label: 'Amex'),
                          _MethodBadge(label: 'bKash'),
                          _MethodBadge(label: 'Nagad'),
                          _MethodBadge(label: 'Net Banking'),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // ── bKash / Nagad phone input ────────────────────────────
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: _methodColor(widget.method).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        widget.method == 'bkash' ? 'bK' : 'N',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _methodColor(widget.method)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text('${widget.method.toUpperCase()} Number',
                    style: GoogleFonts.dmSans(
                        fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF051210),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppColors.primaryDeep),
                  ),
                  child: TextField(
                    controller: _ctrl,
                    keyboardType: TextInputType.phone,
                    style: GoogleFonts.dmSans(fontSize: 15, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: '01xxxxxxxxx',
                      hintStyle: GoogleFonts.dmSans(
                          fontSize: 15, color: AppColors.textSecondary),
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Total row
              // Payment-mode toggle. Hidden when the pitch only allows one
              // mode (no choice = no toggle). The default state matches
              // pitch.defaultPaymentMode.
              if (widget.pitch.allowsPartialPayment &&
                  widget.pitch.allowsFullPayment) ...[
                _ModeToggle(
                  selected: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                ),
                const SizedBox(height: 10),
              ],
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF051210),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primaryDeep, width: 0.5),
                ),
                child: _PaymentBreakdown(
                  totalBDT: widget.totalCost,
                  mode: _mode,
                ),
              ),
              const SizedBox(height: 8),
              // Refund policy — single sentence, easy to find.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.security_rounded,
                        color: AppColors.primary, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Cancel 6+ hours before kickoff = full refund. Payment processed securely by SSLCommerz.',
                        style: GoogleFonts.dmSans(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              if (state is BookingError)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(state.message,
                      style: GoogleFonts.dmSans(
                          fontSize: 13, color: Colors.redAccent),
                      textAlign: TextAlign.center),
                ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isSSL
                        ? const Color(0xFF1E88E5)
                        : AppColors.primary,
                    shape: const StadiumBorder(),
                    elevation: 0,
                  ),
                  onPressed: isLoading ? null : _pay,
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isSSL) ...[
                              const Icon(Icons.lock_outline,
                                  size: 16, color: Colors.white),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              _isSSL
                                  ? 'Pay ${_onlineAmount().toInt()} BDT via SSLCommerz'
                                  : 'Pay ${_onlineAmount().toInt()} BDT',
                              style: GoogleFonts.dmSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white),
                            ),
                          ],
                        ),
                ),
              ),

              if (_isSSL) ...[
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    '🔒  256-bit SSL encryption · PCI-DSS compliant',
                    style: GoogleFonts.dmSans(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _methodColor(String method) {
    switch (method) {
      case 'bkash':
        return const Color(0xFFE2136E);
      case 'nagad':
        return const Color(0xFFFF6600);
      default:
        return const Color(0xFF1E88E5);
    }
  }
}

class _MethodBadge extends StatelessWidget {
  const _MethodBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryDeep.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.primaryDeep),
      ),
      child: Text(label,
          style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textSecondary)),
    );
  }
}

/// Toggle between full_online and partial_online. Only shown when the
/// pitch allows both. Visually a 2-up segmented pill — easy thumb target.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF051210),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryDeep, width: 0.5),
      ),
      child: Row(
        children: [
          _seg(label: 'Pay only commission', sub: 'Rest cash at venue', value: 'partial_online'),
          _seg(label: 'Pay full online', sub: 'Skip cash', value: 'full_online'),
        ],
      ),
    );
  }

  Widget _seg({required String label, required String sub, required String value}) {
    final active = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.black : AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(sub,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                      fontSize: 10,
                      color: active
                          ? Colors.black.withValues(alpha: 0.7)
                          : AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders the price breakdown. In partial_online mode the user sees both
/// the online portion and the cash-at-venue portion as separate lines with
/// a clear total. In full_online mode it's just one line.
class _PaymentBreakdown extends StatelessWidget {
  const _PaymentBreakdown({required this.totalBDT, required this.mode});
  final double totalBDT;
  final String mode;

  bool get _partial => mode == 'partial_online';
  double get _online => _partial ? totalBDT * 0.15 : totalBDT;
  double get _cash => _partial ? totalBDT - _online : 0;

  @override
  Widget build(BuildContext context) {
    if (!_partial) {
      return Row(children: [
        Text('Total',
            style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
        const Spacer(),
        Text('${totalBDT.toInt()} BDT',
            style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.primary)),
      ]);
    }
    return Column(
      children: [
        _row('Pay online now', _online, highlight: true),
        const SizedBox(height: 6),
        _row('Pay cash at venue', _cash),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1, color: Color(0xFF0E2A24)),
        ),
        _row('Total', totalBDT, bold: true),
        const SizedBox(height: 6),
        Text(
          'Online portion is the platform fee. Bring the cash share to the pitch on match day.',
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(
              fontSize: 11, color: AppColors.textSecondary, height: 1.4),
        ),
      ],
    );
  }

  Widget _row(String label, double bdt,
      {bool highlight = false, bool bold = false}) {
    return Row(
      children: [
        Text(label,
            style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: bold ? AppColors.textPrimary : AppColors.textSecondary)),
        const Spacer(),
        Text('${bdt.toInt()} BDT',
            style: GoogleFonts.nunito(
                fontSize: highlight || bold ? 16 : 14,
                fontWeight: FontWeight.w800,
                color: highlight ? AppColors.primary : AppColors.textPrimary)),
      ],
    );
  }
}
