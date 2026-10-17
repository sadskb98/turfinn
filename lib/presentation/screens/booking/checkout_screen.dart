import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/pitch_model.dart';
import '../split/split_initiate_sheet.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.pitch,
    required this.startsAt,
    required this.endsAt,
  });
  final PitchModel pitch;
  final DateTime startsAt;
  final DateTime endsAt;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _selectedMethod = '';
  final _promoCtrl = TextEditingController();

  double get _totalCost {
    final hours = widget.endsAt.difference(widget.startsAt).inHours.clamp(1, 24);
    return hours * widget.pitch.pricePerHour;
  }

  String _fmtDate(DateTime dt) {
    const days = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[dt.weekday]}, ${dt.day} ${months[dt.month]}';
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${dt.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  void dispose() {
    _promoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hours = widget.endsAt.difference(widget.startsAt).inHours.clamp(1, 24);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: const Icon(Icons.arrow_back_ios_new,
                        color: AppColors.textPrimary, size: 18),
                  ),
                  const SizedBox(width: 14),
                  Text('Checkout',
                      style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Booking Summary Card ──────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A1F1A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primaryDeep, width: 0.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('Booking Summary',
                                  style: GoogleFonts.nunito(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary)),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => context.pop(),
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined,
                                        size: 13, color: AppColors.primary),
                                    const SizedBox(width: 3),
                                    Text('Edit',
                                        style: GoogleFonts.dmSans(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.primary)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _InfoRow(label: 'Turf', value: widget.pitch.name),
                          const SizedBox(height: 14),
                          _InfoRow(
                            label: 'Date & Time',
                            value: '${_fmtDate(widget.startsAt)} • ${_fmtTime(widget.startsAt)} — ${_fmtTime(widget.endsAt)}',
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _InfoRow(label: 'Duration', value: '$hours Hour'),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('Price per Hour',
                                      style: GoogleFonts.dmSans(
                                          fontSize: 11,
                                          color: AppColors.textSecondary)),
                                  const SizedBox(height: 2),
                                  Text('${widget.pitch.pricePerHour.toInt()} BDT',
                                      style: GoogleFonts.nunito(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary)),
                                ],
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Container(height: 0.5, color: AppColors.primaryDeep),
                          ),
                          Row(
                            children: [
                              Text('Total Amount',
                                  style: GoogleFonts.dmSans(
                                      fontSize: 13,
                                      color: AppColors.textSecondary)),
                              const Spacer(),
                              Text('${_totalCost.toInt()} BDT',
                                  style: GoogleFonts.nunito(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Please confirm your details before proceeding.',
                              style: GoogleFonts.dmSans(
                                  fontSize: 11,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Payment Methods ───────────────────────────────────
                    Text('Choose Payment Method',
                        style: GoogleFonts.nunito(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 14),

                    _PaymentTile(
                      icon: '🔴',
                      iconColor: const Color(0xFFE2136E),
                      label: 'Bkash',
                      selected: _selectedMethod == 'bkash',
                      onTap: () => setState(() => _selectedMethod = 'bkash'),
                    ),
                    const SizedBox(height: 10),
                    _PaymentTile(
                      icon: '🟠',
                      iconColor: const Color(0xFFFF6600),
                      label: 'Nagad',
                      selected: _selectedMethod == 'nagad',
                      onTap: () => setState(() => _selectedMethod = 'nagad'),
                    ),
                    const SizedBox(height: 10),
                    _PaymentTile(
                      icon: '💳',
                      iconColor: const Color(0xFF1E88E5),
                      label: 'Card / Net Banking',
                      sublabel: 'via SSLCommerz · Visa, Mastercard, bKash',
                      selected: _selectedMethod == 'bank',
                      onTap: () => setState(() => _selectedMethod = 'bank'),
                    ),

                    const SizedBox(height: 24),

                    // ── Promo code ────────────────────────────────────────
                    Text('Promo Code/ Voucher',
                        style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A1F1A),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.primaryDeep),
                            ),
                            child: TextField(
                              controller: _promoCtrl,
                              style: GoogleFonts.dmSans(
                                  fontSize: 14, color: AppColors.textPrimary),
                              decoration: InputDecoration(
                                hintText: 'Enter Promo Code',
                                hintStyle: GoogleFonts.dmSans(
                                    fontSize: 14, color: AppColors.textSecondary),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text('Submit',
                                style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Bottom confirm ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
              child: Column(children: [
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedMethod.isNotEmpty
                          ? AppColors.primary
                          : const Color(0xFF0A1F1A),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: _selectedMethod.isEmpty
                        ? null
                        : () => context.push('/payment', extra: {
                              'pitch': widget.pitch,
                              'startsAt': widget.startsAt,
                              'endsAt': widget.endsAt,
                              'method': _selectedMethod,
                              'totalCost': _totalCost,
                            }),
                    child: Text('Confirm',
                        style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _selectedMethod.isNotEmpty
                                ? Colors.black
                                : AppColors.textSecondary)),
                  ),
                ),
                const SizedBox(height: 10),
                // Split-pay entry — secondary CTA. Only visible until the
                // captain has selected a payment method (then Confirm wins).
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => SplitInitiateSheet.show(
                      context,
                      pitch: widget.pitch,
                      startsAt: widget.startsAt,
                      endsAt: widget.endsAt,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary, width: 1.2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.groups_rounded, size: 18),
                    label: Text('Split with friends',
                        style: GoogleFonts.dmSans(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value,
              style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
      );
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.selected,
    required this.onTap,
    this.sublabel,
  });
  final String icon;
  final Color iconColor;
  final String label;
  final String? sublabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1F1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.primaryDeep,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(icon, style: const TextStyle(fontSize: 14)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary)),
                  if (sublabel != null) ...[
                    const SizedBox(height: 2),
                    Text(sublabel!,
                        style: GoogleFonts.dmSans(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
            // Radio circle
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.primaryDeep,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
