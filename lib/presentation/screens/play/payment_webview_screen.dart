import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/theme/app_colors.dart';

/// Outcome the WebView returns to its caller. The Play screen uses this
/// to refresh state and pick the right snackbar.
enum PaymentOutcome { success, fail, cancel, abandoned }

/// Hosts the SSLCommerz gateway inside the app so the user never leaves.
///
/// Detection strategy: SSL eventually redirects to our backend success/fail/
/// cancel endpoints. Each of those returns an HTML page whose <title> is
/// `TURFINN_PAYMENT_<status>` and whose meta-refresh points at a
/// `turfinn://payment/match/<status>` deep link. We listen for both —
/// title changes AND navigation to the deep-link scheme — so whichever
/// fires first gets us out of the WebView with the right outcome.
class PaymentWebViewScreen extends StatefulWidget {
  const PaymentWebViewScreen({super.key, required this.gatewayUrl});

  final String gatewayUrl;

  @override
  State<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<PaymentWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.background)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (_) {},
        onPageStarted: (_) {
          if (!mounted) return;
          setState(() => _loading = true);
        },
        onPageFinished: (url) async {
          if (!mounted) return;
          setState(() => _loading = false);
          // Check the title — backend's return page sets it to
          // TURFINN_PAYMENT_<status>. This is the most reliable signal.
          final title = await _controller.getTitle();
          _maybeFinish(title: title, url: url);
        },
        onNavigationRequest: (req) {
          // Intercept the meta-refresh to the custom-scheme deep link.
          if (req.url.startsWith('turfinn://payment/match/')) {
            _resolveFromUrl(req.url);
            return NavigationDecision.prevent;
          }
          // Also catch direct hits to our backend callback URLs in case the
          // gateway redirects through them with a 302 instead of HTML.
          if (req.url.contains('/api/v1/payment/match/')) {
            _maybeFinish(url: req.url);
            // Allow navigation so the backend can render the success/fail
            // HTML — its title-changed event is what actually closes us.
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.gatewayUrl));
  }

  void _maybeFinish({String? title, String? url}) {
    if (_resolved) return;
    PaymentOutcome? outcome;
    if (title != null) {
      if (title.contains('TURFINN_PAYMENT_success')) {
        outcome = PaymentOutcome.success;
      } else if (title.contains('TURFINN_PAYMENT_fail')) {
        outcome = PaymentOutcome.fail;
      } else if (title.contains('TURFINN_PAYMENT_cancel')) {
        outcome = PaymentOutcome.cancel;
      }
    }
    if (outcome == null && url != null) {
      if (url.contains('/payment/match/success')) {
        outcome = PaymentOutcome.success;
      } else if (url.contains('/payment/match/fail')) {
        outcome = PaymentOutcome.fail;
      } else if (url.contains('/payment/match/cancel')) {
        outcome = PaymentOutcome.cancel;
      }
    }
    if (outcome != null) {
      _resolveOutcome(outcome);
    }
  }

  void _resolveFromUrl(String url) {
    final segs = Uri.parse(url).pathSegments;
    final last = segs.isNotEmpty ? segs.last : '';
    final outcome = switch (last) {
      'success' => PaymentOutcome.success,
      'fail' => PaymentOutcome.fail,
      'cancel' => PaymentOutcome.cancel,
      _ => PaymentOutcome.abandoned,
    };
    _resolveOutcome(outcome);
  }

  void _resolveOutcome(PaymentOutcome outcome) {
    if (_resolved) return;
    _resolved = true;
    if (!mounted) return;
    Navigator.of(context).pop(outcome);
  }

  Future<bool> _confirmAbandon() async {
    if (_resolved) return true;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1F1A),
        title: Text('Abandon payment?',
            style: GoogleFonts.nunito(
                fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        content: Text(
          'If you leave now your spot won\'t be reserved. You can try again from the match details.',
          style: GoogleFonts.dmSans(
              fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB00020),
                foregroundColor: Colors.white),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return yes ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmAbandon() && mounted) {
          _resolveOutcome(PaymentOutcome.abandoned);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: const Color(0xFF051210),
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          title: Text('Secure payment',
              style: GoogleFonts.nunito(
                  fontSize: 16, fontWeight: FontWeight.w800)),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () async {
              if (await _confirmAbandon() && mounted) {
                _resolveOutcome(PaymentOutcome.abandoned);
              }
            },
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
          ],
        ),
      ),
    );
  }
}
