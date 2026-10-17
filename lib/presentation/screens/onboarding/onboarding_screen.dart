import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/router/app_router.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = PageController();
  int _page = 0;

  // Onboarding messaging maps to the actual core loop: find pitch → pay
  // small online deposit → bring cash to the venue → play. Trust signal on
  // slide 2 is critical for low-online-payment-trust markets like Bangladesh.
  static const _slides = [
    _Slide(
      image: 'assets/images/backdrop-1.png',
      heading: 'Find a turf near you',
      sub: 'Pitches in your area, on a map.\nPick a slot, book in 2 taps.',
    ),
    _Slide(
      image: 'assets/images/backdrop-2.png',
      heading: 'Pay only Turfinn online',
      sub: 'Just the platform fee on the app.\nPay the rest as cash at the venue.',
    ),
    _Slide(
      image: 'assets/images/backdrop-3.png',
      heading: 'Need players? Find them.',
      sub: 'Post a match, players nearby join.\nCancelled? Auto refund.',
    ),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (mounted) context.go(AppRoutes.welcome);
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _ctrl.nextPage(
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    } else {
      _finish();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _ctrl,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: _slides.length,
            itemBuilder: (context, i) => _SlideView(slide: _slides[i]),
          ),

          // Dark gradient at bottom for text readability
          Positioned(
            left: 0, right: 0, bottom: 0,
            height: MediaQuery.sizeOf(context).height * 0.45,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.92)],
                ),
              ),
            ),
          ),

          // Content
          Positioned(
            left: 28, right: 28, bottom: 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _slides[_page].heading,
                  style: GoogleFonts.nunito(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _slides[_page].sub,
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    color: Colors.white70,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 36),
                Row(
                  children: [
                    // Dot indicators
                    Row(
                      children: List.generate(_slides.length, (i) {
                        final active = i == _page;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.only(right: 6),
                          width: active ? 24 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: active ? AppColors.primary : Colors.white30,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                    const Spacer(),
                    // Skip
                    if (_page < _slides.length - 1)
                      GestureDetector(
                        onTap: _finish,
                        child: Text(
                          'Skip',
                          style: GoogleFonts.dmSans(
                            fontSize: 15,
                            color: Colors.white54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    const SizedBox(width: 20),
                    // Next button
                    GestureDetector(
                      onTap: _next,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _page == _slides.length - 1
                              ? Icons.check
                              : Icons.chevron_right,
                          color: Colors.black,
                          size: 28,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide {
  const _Slide({required this.image, required this.heading, required this.sub});
  final String image;
  final String heading;
  final String sub;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});
  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      slide.image,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (ctx, _, __) => Container(
        color: const Color(0xFF051210),
        child: const Center(
          child: Icon(Icons.sports_soccer, color: Colors.white24, size: 80),
        ),
      ),
    );
  }
}
