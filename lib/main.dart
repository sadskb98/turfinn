import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ProviderScope(child: TurfinnApp()));
}

/// Max content width on web — mimics a phone-sized viewport.
const double kWebMaxWidth = 430;

class TurfinnApp extends StatelessWidget {
  const TurfinnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Turfinn',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: appRouter,
      // Bangla support — system locale wins by default. Strings.t() uses
      // the active locale to resolve translations.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('bn'),
      ],
      builder: (context, child) {
        if (!kIsWeb) return child!;
        return _WebShell(child: child!);
      },
    );
  }
}

/// Desktop web wrapper — phone-sized app centered inside a branded shell.
class _WebShell extends StatelessWidget {
  const _WebShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;

    // On narrow viewports (< 600px) just show the app full-width.
    if (screenW < 600) return child;

    // Just the phone-frame on wide screens. Brand and Download panels
    // were creating visual noise on auth/onboarding routes — looked like
    // duplicate "skip / description" blocks because of the surrounding
    // marketing copy. Plain centered frame is clearer.
    return ColoredBox(
      color: const Color(0xFF010A0A),
      child: Center(
        child: Container(
          width: kWebMaxWidth + 16,
          margin: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: AppColors.primaryDeep.withValues(alpha: 0.5),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.08),
                blurRadius: 60,
                spreadRadius: 10,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: child,
          ),
        ),
      ),
    );
  }
}

