import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/match_post_model.dart';
import '../../../data/sources/remote/feed_remote_source.dart';
import '../../providers/feed_provider.dart';
import '../../widgets/toast.dart';
import 'payment_webview_screen.dart';

/// Standalone screen shown after a player joins (or when they tap a match
/// from the list). Gives the player the "what next" — full match details,
/// directions to the pitch, host info, and a way back to the feed.
class MatchDetailScreen extends ConsumerWidget {
  const MatchDetailScreen({
    super.key,
    required this.matchId,
    this.justJoined = false,
  });

  final String matchId;

  /// When true, the screen renders a "You're in!" hero band so the user
  /// knows their join succeeded.
  final bool justJoined;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(matchPostProvider(matchId));
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: async.when(
          data: (m) => _content(context, m),
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Could not load match: $e',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.dmSans(
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => context.pop(),
                    child: const Text('Back'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, MatchPost m) {
    final dateFmt = DateFormat('EEE, MMM d · h:mm a');
    final spotsLeft = m.spotsTotal - m.spotsFilled;
    final perHead = m.perHeadCostBDT ?? 0;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _topBar(context)),
        if (justJoined) SliverToBoxAdapter(child: _joinedBanner()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: m.postType == 'need_teammates'
                        ? const Color(0xFFFFC857).withValues(alpha: 0.18)
                        : AppColors.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    m.postType == 'need_teammates'
                        ? 'Need teammates'
                        : 'Open match',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: m.postType == 'need_teammates'
                          ? const Color(0xFFFFC857)
                          : AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  m.title.isEmpty ? 'Match' : m.title,
                  style: GoogleFonts.nunito(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text('Hosted by ${m.authorName.isEmpty ? "Player" : m.authorName}',
                    style: GoogleFonts.dmSans(
                        fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: _infoBlock(m, dateFmt, spotsLeft, perHead),
          ),
        ),
        if (m.description.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1F1A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.primaryDeep.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Notes from host',
                        style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    Text(m.description,
                        style: GoogleFonts.dmSans(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                            height: 1.4)),
                  ],
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: _whatsNextSection(),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            child: _CtaButtons(match: m),
          ),
        ),
      ],
    );
  }

  Widget _topBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.textPrimary),
          ),
          const SizedBox(width: 4),
          Text('Match details',
              style: GoogleFonts.nunito(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _joinedBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.22),
            AppColors.primary.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.6), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.check_rounded,
                color: Colors.black, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("You're in!",
                    style: GoogleFonts.nunito(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                    'Save the time and head to the pitch — see you there.',
                    style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBlock(MatchPost m, DateFormat dateFmt, int spotsLeft, int perHead) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.primaryDeep.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          _row(Icons.event_rounded, 'When',
              dateFmt.format(m.matchDate.toLocal())),
          _row(Icons.timer_outlined, 'Duration', '${m.durationMinutes} min'),
          if (m.format.isNotEmpty)
            _row(Icons.sports_soccer_rounded, 'Format', m.format),
          _row(Icons.people_alt_outlined, 'Players',
              '${m.spotsFilled} confirmed · $spotsLeft / ${m.spotsTotal} spots'),
          if (m.pitchName != null)
            _row(Icons.place_rounded, 'Pitch', m.pitchName!),
          if (perHead > 0)
            _row(Icons.payments_outlined, 'Per-player share',
                '$perHead BDT'),
          _row(Icons.shield_outlined, 'Commitment fee',
              '${m.joinFeeBDT} BDT'),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(k,
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: AppColors.textSecondary)),
          const Spacer(),
          Flexible(
            child: Text(v,
                textAlign: TextAlign.right,
                style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _whatsNextSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.primaryDeep.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline,
                  color: Color(0xFFFFC857), size: 18),
              const SizedBox(width: 8),
              Text("What's next",
                  style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 10),
          _next('1', 'Show up 10 minutes before kickoff'),
          _next('2', 'Bring sport shoes — turf shoes recommended'),
          _next('3', 'Settle the pitch fee with your group at the venue'),
        ],
      ),
    );
  }

  Widget _next(String n, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(n,
                  style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    height: 1.4)),
          ),
        ],
      ),
    );
  }

  Future<void> _openDirections(MatchPost m) async {
    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${m.latitude},${m.longitude}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}

// ── CTA buttons block ───────────────────────────────────────────────────────
//
// Renders the right primary action for the user's relationship to the match:
//   - Host: just "Get directions" + "Back" (no Pay — they're already in)
//   - Joined: "Get directions" + "Back" (already paid)
//   - Stranger + has spots: "Pay X BDT to join" → opens SSL gateway URL
//   - Stranger + match full: disabled "Match full" tag
class _CtaButtons extends ConsumerStatefulWidget {
  const _CtaButtons({required this.match});
  final MatchPost match;

  @override
  ConsumerState<_CtaButtons> createState() => _CtaButtonsState();
}

class _CtaButtonsState extends ConsumerState<_CtaButtons> {
  bool _busy = false;

  Future<void> _payAndJoin() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = await ref
          .read(feedRemoteSourceProvider)
          .initiateJoinPayment(widget.match.id);
      final outcome = await Navigator.of(context).push<PaymentOutcome>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              PaymentWebViewScreen(gatewayUrl: session.redirectUrl),
        ),
      );
      if (!mounted) return;
      // Refresh providers in all cases — backend state may have changed.
      ref.invalidate(matchPostProvider(widget.match.id));
      ref.invalidate(feedListProvider);
      ref.invalidate(myMatchesProvider);
      switch (outcome) {
        case PaymentOutcome.success:
          showToast(context, "Payment received — you're in!");
        case PaymentOutcome.fail:
          showError(context, 'Payment failed. No charge made.');
        case PaymentOutcome.cancel:
          showInfo(context, 'Payment cancelled.');
        case PaymentOutcome.abandoned:
        case null:
          break;
      }
    } catch (e) {
      if (!mounted) return;
      showError(context, friendlyDioError(e, fallback: 'Could not start payment'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leaveMatch() async {
    final m = widget.match;
    final hoursToKickoff =
        m.matchDate.toLocal().difference(DateTime.now()).inMinutes / 60;
    final willRefund = hoursToKickoff > 1; // matches backend default
    final body = willRefund
        ? "We'll release your seat and queue an SSL refund — money returns to your card / mobile banking in 3-7 business days."
        : "Kickoff is less than 60 minutes away — your seat will be released, but the commitment fee won't be auto-refunded. The host can still refund manually if they wish.";

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1F1A),
        title: Text('Cancel your spot?',
            style: GoogleFonts.nunito(
                fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        content: Text(body,
            style: GoogleFonts.dmSans(
                fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay in'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB00020),
                foregroundColor: Colors.white),
            child: const Text('Cancel my spot'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final res =
          await ref.read(feedRemoteSourceProvider).leaveMatch(widget.match.id);
      if (!mounted) return;
      if (res.refundQueued) {
        showToast(context, 'Spot released — refund queued.');
      } else {
        showInfo(context, 'Spot released. Refund window has passed.');
      }
      ref.invalidate(matchPostProvider(widget.match.id));
      ref.invalidate(feedListProvider);
      ref.invalidate(myMatchesProvider);
    } catch (e) {
      if (!mounted) return;
      showError(context, friendlyDioError(e, fallback: 'Could not cancel'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelMatch() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1F1A),
        title: Text('Cancel this match?',
            style: GoogleFonts.nunito(
                fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        content: Text(
          'All joiners will be auto-refunded to their card or mobile banking. This can\'t be undone.',
          style: GoogleFonts.dmSans(
              fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep match'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB00020),
                foregroundColor: Colors.white),
            child: const Text('Cancel match'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final n = await ref
          .read(feedRemoteSourceProvider)
          .cancelMatch(widget.match.id);
      if (!mounted) return;
      showToast(context, n > 0
          ? 'Match cancelled — $n joiner refund${n == 1 ? "" : "s"} queued.'
          : 'Match cancelled.');
      ref.invalidate(matchPostProvider(widget.match.id));
      ref.invalidate(feedListProvider);
      ref.invalidate(myMatchesProvider);
    } catch (e) {
      if (!mounted) return;
      showError(context, 'Could not cancel: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDirections() async {
    final m = widget.match;
    if (m.latitude == 0 && m.longitude == 0) return;
    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${m.latitude},${m.longitude}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final spotsLeft = m.spotsTotal - m.spotsFilled;
    final isFull = spotsLeft <= 0;
    final perHead = m.perHeadCostBDT ?? 0;
    final fee = m.joinFeeBDT;
    final total = perHead + fee;

    final canPay = !m.isHost && !m.isJoined && !isFull;

    return Column(
      children: [
        if (canPay)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _payAndJoin,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.lock_rounded, size: 18),
              label: Text(
                _busy
                    ? 'Opening payment…'
                    : (total > 0
                        ? 'Pay $total BDT to join'
                        : 'Pay $fee BDT to join'),
                style: GoogleFonts.nunito(
                    fontSize: 15, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        if (canPay) const SizedBox(height: 10),
        if (m.isHost) ...[
          _statePill(
            icon: Icons.verified_user_rounded,
            text: "You're hosting this match",
          ),
          const SizedBox(height: 8),
          if (m.status != 'cancelled')
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _cancelMatch,
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: Text('Cancel match · refund all joiners',
                    style: GoogleFonts.nunito(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF8A80),
                  side: const BorderSide(
                      color: Color(0xFFFF8A80), width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
        ],
        if (m.isJoined && !m.isHost) ...[
          _statePill(
            icon: Icons.check_circle_rounded,
            text: "You're in — see you at the pitch",
          ),
          if (m.myRefundStatus != null) ...[
            const SizedBox(height: 8),
            _refundPill(m.myRefundStatus!),
          ],
          if (m.status != 'cancelled' && m.myRefundStatus == null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _leaveMatch,
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: Text('Cancel my spot · request refund',
                    style: GoogleFonts.nunito(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF8A80),
                  side: const BorderSide(
                      color: Color(0xFFFF8A80), width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
        if (isFull && !m.isHost && !m.isJoined)
          _statePill(
            icon: Icons.do_not_disturb_on_outlined,
            text: 'Match is full',
            muted: true,
          ),
        if (m.isHost || m.isJoined || isFull) const SizedBox(height: 10),
        if (m.latitude != 0 && m.longitude != 0)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openDirections,
              icon: const Icon(Icons.directions_rounded, size: 18),
              label: Text('Get directions',
                  style: GoogleFonts.nunito(
                      fontSize: 14, fontWeight: FontWeight.w800)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side:
                    const BorderSide(color: AppColors.primary, width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => context.pop(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text('Back to matches',
                style: GoogleFonts.dmSans(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _refundPill(String status) {
    late final IconData icon;
    late final String text;
    late final Color c;
    switch (status) {
      case 'refunded':
        icon = Icons.task_alt_rounded;
        text = 'Refund completed — money returned';
        c = AppColors.primary;
      case 'refund_failed':
        icon = Icons.error_outline_rounded;
        text = 'Refund failed — support is on it';
        c = const Color(0xFFFF8A80);
      case 'requested':
      default:
        icon = Icons.hourglass_top_rounded;
        text = 'Refund queued — 3-7 business days';
        c = const Color(0xFFFFC857);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c)),
          ),
        ],
      ),
    );
  }

  Widget _statePill(
      {required IconData icon, required String text, bool muted = false}) {
    final c = muted ? AppColors.textSecondary : AppColors.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 6),
          Text(text,
              style: GoogleFonts.nunito(
                  fontSize: 13, fontWeight: FontWeight.w800, color: c)),
        ],
      ),
    );
  }
}
