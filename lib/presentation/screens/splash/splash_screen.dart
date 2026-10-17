import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/router/app_router.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _dropFraction;
  late final Animation<double> _scale;

  static const _ballDiameter = 48.0;
  static const _expandScale = 35.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _dropFraction = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _scale = Tween<double>(begin: 1.0, end: _expandScale).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
      ),
    );

    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _navigate();
    });

    _ctrl.forward();
  }

  Future<void> _navigate() async {
    if (!mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final onboardingDone = prefs.getBool('onboarding_done') ?? false;
      if (!mounted) return;
      if (token != null && token.isNotEmpty) {
        context.go(AppRoutes.home);
      } else if (onboardingDone) {
        context.go(AppRoutes.welcome);
      } else {
        context.go(AppRoutes.onboarding);
      }
    } catch (_) {
      if (mounted) context.go(AppRoutes.onboarding);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dropDistance = size.height / 2 + _ballDiameter / 2;

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final dy = _dropFraction.value * dropDistance;
          final scale = _scale.value;
          return Center(
            child: Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: _ballDiameter,
                  height: _ballDiameter,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.black,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
