// SplitStatusScreen — captain's view after they pay their own share.
// Shows a live X-of-N counter, a copyable magic link, a one-tap WhatsApp
// share button with a pre-filled invite message, and a countdown to the
// deadline. Polls /split/:token every 8s for live updates.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/sources/remote/booking_remote_source.dart';

class SplitStatusScreen extends ConsumerStatefulWidget {
  const SplitStatusScreen({
    super.key,
    required this.token,
    required this.deadlineAt,
  });

  final String token;
  final DateTime deadlineAt;

  @override
  ConsumerState<SplitStatusScreen> createState() => _SplitStatusScreenState();
}

class _SplitStatusScreenState extends ConsumerState<SplitStatusScreen> {
  Map<String, dynamic>? _info;
  bool _loading = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await ref.read(bookingRemoteSourceProvider).getSplitByToken(widget.token);
      if (mounted) setState(() { _info = m; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _publicUrl {
    // The web bundle hosts /split/:token on the same origin as the API.
    // For Docker dev, this resolves to http://localhost:3000/split/:token.
    final base = AppConfig.apiBaseUrl;
    final origin = base.endsWith('/api/v1') ? base.substring(0, base.length - 7) : base;
    return '$origin/split/${widget.token}';
  }

  String get _whatsappMessage {
    final i = _info ?? {};
    final pitch = i['pitch_name'] ?? 'the pitch';
    final per = (i['per_share_bdt'] as num?)?.toStringAsFixed(0) ?? '0';
    final startsAtIso = i['starts_at'] as String? ?? '';
    final dt = DateTime.tryParse(startsAtIso)?.toLocal();
    final when = dt == null ? 'soon' : _shortWhen(dt);
    return '⚽ Match at $pitch, $when. Your share: ৳$per. Pay here: $_publicUrl';
  }

  Future<void> _shareWhatsApp() async {
    final encoded = Uri.encodeComponent(_whatsappMessage);
    final uri = Uri.parse('https://wa.me/?text=$encoded');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _publicUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => context.go('/home'),
        ),
        title: Text('Split status',
            style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      ),
      body: _loading && _info == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _Body(
              info: _info ?? {},
              publicUrl: _publicUrl,
              deadlineAt: widget.deadlineAt,
              onShareWhatsApp: _shareWhatsApp,
              onCopyLink: _copyLink,
              onRefresh: _load,
            ),
    );
  }

  static String _shortWhen(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '${months[dt.month - 1]} ${dt.day}, $h12:$m $period';
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.info,
    required this.publicUrl,
    required this.deadlineAt,
    required this.onShareWhatsApp,
    required this.onCopyLink,
    required this.onRefresh,
  });

  final Map<String, dynamic> info;
  final String publicUrl;
  final DateTime deadlineAt;
  final VoidCallback onShareWhatsApp;
  final VoidCallback onCopyLink;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final paid = (info['paid_count'] as num?)?.toInt() ?? 1;
    final total = (info['share_count'] as num?)?.toInt() ?? 1;
    final perShare = (info['per_share_bdt'] as num?)?.toDouble() ?? 0;
    final status = info['booking_status'] ?? 'pending_split';
    final pitch = info['pitch_name'] ?? '';
    final progress = total == 0 ? 0.0 : paid / total;
    final allDone = status == 'confirmed';
    final cancelled = status == 'cancelled';

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (allDone)
              _StatusBanner(
                icon: Icons.check_circle_rounded,
                color: AppColors.primary,
                title: 'Match locked!',
                subtitle: 'All shares paid. See you on the pitch.',
              )
            else if (cancelled)
              _StatusBanner(
                icon: Icons.cancel_rounded,
                color: Colors.redAccent,
                title: 'Split cancelled',
                subtitle: 'Deadline passed. Anyone who paid was refunded.',
              )
            else
              _StatusBanner(
                icon: Icons.pending_actions_rounded,
                color: Colors.orangeAccent,
                title: 'Waiting on $total - $paid friend${(total - paid) == 1 ? '' : 's'}',
                subtitle: 'Share the link below in your team chat',
              ),
            const SizedBox(height: 20),

            // Progress card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primaryDeep),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(pitch,
                    style: GoogleFonts.nunito(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text('৳${perShare.toStringAsFixed(0)} per person',
                    style: GoogleFonts.dmSans(
                        fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 18),
                Row(children: [
                  Text('$paid',
                      style: GoogleFonts.nunito(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
                  Text(' / $total paid',
                      style: GoogleFonts.dmSans(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: AppColors.background,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
                if (!allDone && !cancelled) ...[
                  const SizedBox(height: 12),
                  _Countdown(deadline: deadlineAt),
                ],
              ]),
            ),

            const SizedBox(height: 24),

            if (!allDone && !cancelled) ...[
              Text('Invite your team',
                  style: GoogleFonts.nunito(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onShareWhatsApp,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.chat_rounded, size: 18),
                  label: Text('Share on WhatsApp',
                      style: GoogleFonts.nunito(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),

              const SizedBox(height: 10),

              OutlinedButton.icon(
                onPressed: onCopyLink,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.primaryDeep),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: Text('Copy link',
                    style: GoogleFonts.dmSans(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),

              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primaryDeep),
                ),
                child: Text(publicUrl,
                    style: GoogleFonts.firaMono(
                        fontSize: 11.5, color: AppColors.textMuted)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 28),
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
              const SizedBox(height: 2),
              Text(subtitle,
                  style: GoogleFonts.dmSans(
                      fontSize: 12.5, color: AppColors.textSecondary, height: 1.4)),
            ],
          ),
        ),
      ]),
    );
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
              fontSize: 12.5, color: Colors.redAccent, fontWeight: FontWeight.w600));
    }
    final mins = _remaining.inMinutes;
    final secs = _remaining.inSeconds % 60;
    return Row(children: [
      const Icon(Icons.timer_outlined, size: 14, color: Colors.orangeAccent),
      const SizedBox(width: 6),
      Text('${mins}m ${secs.toString().padLeft(2, '0')}s left',
          style: GoogleFonts.dmSans(
              fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.orangeAccent)),
    ]);
  }
}
