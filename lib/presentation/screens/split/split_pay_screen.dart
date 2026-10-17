// SplitPayScreen renders the public magic-link page that friends land on
// from a WhatsApp invite. No auth required — it fetches /api/v1/split/:token,
// captures a phone number, and hands off to SSL Commerz.
//
// This screen is rendered on the player web bundle, so it must be
// responsive enough for WhatsApp's in-app browser on mobile devices.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';

class SplitPayScreen extends ConsumerStatefulWidget {
  const SplitPayScreen({super.key, required this.token});
  final String token;

  @override
  ConsumerState<SplitPayScreen> createState() => _SplitPayScreenState();
}

class _SplitPayScreenState extends ConsumerState<SplitPayScreen> {
  Map<String, dynamic>? _info;
  String? _error;
  bool _loading = true;
  bool _submitting = false;
  Timer? _refreshTimer;
  final _phoneCtl = TextEditingController();

  // Fresh Dio with no interceptors — guests have no auth token, and the
  // shared dio_client adds a Bearer header that would just be ignored
  // here anyway.
  final _dio = Dio(BaseOptions(
    receiveTimeout: const Duration(seconds: 12),
    sendTimeout: const Duration(seconds: 12),
    validateStatus: (s) => s != null && s < 500,
  ));

  @override
  void initState() {
    super.initState();
    _load();
    // Refresh paid_count every 8s so the captain's link viewers see
    // their teammates' payments in near-real-time.
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _phoneCtl.dispose();
    super.dispose();
  }

  String get _baseUrl {
    // Reuse the same host as the player app's API base — strip /api/v1.
    final base = AppConfig.apiBaseUrl;
    return base.endsWith('/api/v1') ? base.substring(0, base.length - 7) : base;
  }

  Future<void> _load() async {
    try {
      final resp = await _dio.get('$_baseUrl/api/v1/split/${widget.token}');
      if (resp.statusCode == 200) {
        final body = resp.data as Map<String, dynamic>;
        if (mounted) setState(() { _info = body['data'] as Map<String, dynamic>; _error = null; _loading = false; });
      } else {
        final body = resp.data as Map<String, dynamic>;
        if (mounted) setState(() { _error = body['error']?.toString() ?? 'Not found'; _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Network error'; _loading = false; });
    }
  }

  Future<void> _payShare() async {
    final phone = _phoneCtl.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your phone number to claim a share')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final resp = await _dio.post(
        '$_baseUrl/api/v1/split/${widget.token}/claim',
        data: {'phone': phone},
        options: Options(contentType: Headers.jsonContentType),
      );
      final body = resp.data as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        final url = (body['data'] as Map<String, dynamic>)['gateway_url'] as String;
        // Full-page redirect so the SSL session cookie carries through.
        await launchUrl(Uri.parse(url), webOnlyWindowName: '_self');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(body['error']?.toString() ?? 'Could not start payment'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 80),
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : _error != null
                      ? _ErrorState(message: _error!)
                      : _SplitBody(
                          info: _info!,
                          phoneCtl: _phoneCtl,
                          submitting: _submitting,
                          onPay: _payShare,
                        ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SplitBody extends StatelessWidget {
  const _SplitBody({
    required this.info,
    required this.phoneCtl,
    required this.submitting,
    required this.onPay,
  });

  final Map<String, dynamic> info;
  final TextEditingController phoneCtl;
  final bool submitting;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final captainName = info['captain_name'] ?? 'A friend';
    final pitchName = info['pitch_name'] ?? '';
    final pitchCity = info['pitch_city'] ?? '';
    final perShare = (info['per_share_bdt'] as num?)?.toDouble() ?? 0;
    final shareCount = (info['share_count'] as num?)?.toInt() ?? 0;
    final paidCount = (info['paid_count'] as num?)?.toInt() ?? 0;
    final hasOpen = info['has_open_share'] == true;
    final status = info['booking_status'] ?? 'pending_split';
    final startsAtIso = info['starts_at'] as String? ?? '';
    final deadlineIso = info['deadline_at'] as String? ?? '';
    final startsAt = DateTime.tryParse(startsAtIso)?.toLocal();
    final deadline = DateTime.tryParse(deadlineIso)?.toLocal();

    final allDone = status == 'confirmed';
    final cancelled = status == 'cancelled';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header — branded but minimal so it loads fast on slow networks.
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.sports_soccer_rounded, color: AppColors.background),
          ),
          const SizedBox(width: 10),
          Text('Turfinn',
              style: GoogleFonts.nunito(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 28),

        Text('$captainName invited you to split a match',
            style: GoogleFonts.nunito(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                height: 1.3)),
        const SizedBox(height: 6),
        Text(pitchCity.isEmpty ? pitchName : '$pitchName · $pitchCity',
            style: GoogleFonts.dmSans(
                fontSize: 14, color: AppColors.textSecondary)),
        if (startsAt != null) ...[
          const SizedBox(height: 4),
          Text(_fmtDateTime(startsAt),
              style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
        const SizedBox(height: 24),

        // Big share amount card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primaryDeep),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your share',
                  style: GoogleFonts.dmSans(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Text('৳${perShare.toStringAsFixed(0)}',
                  style: GoogleFonts.nunito(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
              const SizedBox(height: 12),
              Row(children: [
                Icon(Icons.groups_rounded, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text('$paidCount of $shareCount paid',
                    style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ]),
              if (deadline != null && !allDone && !cancelled) ...[
                const SizedBox(height: 8),
                _Countdown(deadline: deadline),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        if (allDone)
          _BannerCard(
            icon: Icons.check_circle_rounded,
            color: AppColors.primary,
            title: 'Match locked!',
            body: 'Everyone paid. See you on the pitch.',
          )
        else if (cancelled)
          _BannerCard(
            icon: Icons.cancel_rounded,
            color: Colors.redAccent,
            title: 'Split cancelled',
            body: 'The deadline passed before everyone paid. Anyone who paid was refunded.',
          )
        else if (!hasOpen)
          _BannerCard(
            icon: Icons.hourglass_top_rounded,
            color: Colors.orangeAccent,
            title: 'All shares claimed',
            body: 'Waiting for the last few payments to clear. Refresh in a moment.',
          )
        else ...[
          Text('Pay your share',
              style: GoogleFonts.nunito(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text('Enter your phone number — we use it only to track your share and so the captain can see who paid.',
              style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.5)),
          const SizedBox(height: 14),
          TextField(
            controller: phoneCtl,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d+\s\-]')),
              LengthLimitingTextInputFormatter(20),
            ],
            style: GoogleFonts.dmSans(fontSize: 16, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: '01XXXXXXXXX',
              hintStyle: GoogleFonts.dmSans(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surfaceDark,
              prefixIcon: const Icon(Icons.phone_rounded, color: AppColors.primary),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primaryDeep),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primaryDeep),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: submitting ? null : onPay,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.background,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.background))
                  : Text('Pay ৳${perShare.toStringAsFixed(0)} via SSL Commerz',
                      style: GoogleFonts.nunito(
                          fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'Pay via card / bKash / Nagad / Rocket — no Turfinn account needed.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
        ],

        const SizedBox(height: 28),
        Center(
          child: Text(
            '🔒 Refunded automatically if everyone doesn\'t pay before the deadline.',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
                fontSize: 12, color: AppColors.textMuted, height: 1.5),
          ),
        ),
      ],
    );
  }

  static String _fmtDateTime(DateTime dt) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $h12:$m $period';
  }
}

class _Countdown extends StatefulWidget {
  const _Countdown({required this.deadline});
  final DateTime deadline;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  late Timer _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _remaining = widget.deadline.difference(DateTime.now()));
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining.isNegative) {
      return Text('Deadline passed',
          style: GoogleFonts.dmSans(
              fontSize: 13, color: Colors.redAccent, fontWeight: FontWeight.w600));
    }
    final mins = _remaining.inMinutes;
    final secs = _remaining.inSeconds % 60;
    return Row(children: [
      Icon(Icons.timer_outlined, size: 14, color: Colors.orangeAccent),
      const SizedBox(width: 6),
      Text('${mins}m ${secs.toString().padLeft(2, '0')}s left',
          style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.orangeAccent)),
    ]);
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(body,
                    style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Icon(Icons.link_off_rounded,
              color: AppColors.textMuted, size: 64),
        ),
        Text('Link not found',
            style: GoogleFonts.nunito(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text(message,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
                fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
      ],
    );
  }
}
