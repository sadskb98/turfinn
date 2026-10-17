import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_colors.dart';
import 'presentation/screens/superadmin/superadmin_login_screen.dart';
import 'presentation/screens/superadmin/superadmin_panel_screen.dart';

/// Resolve the start route based on whether we have a token. The dio
/// interceptor reads `auth_token`; we set it on successful super-admin
/// login. No token → land on login.
Future<String> _resolveStartRoute() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('auth_token');
  if (token == null || token.isEmpty) return '/login';
  return '/';
}

final _superAdminRouter = GoRouter(
  initialLocation: '/loading',
  routes: [
    GoRoute(path: '/loading', builder: (_, __) => const _LoadingScreen()),
    GoRoute(path: '/login', builder: (_, __) => const SuperAdminLoginScreen()),
    GoRoute(path: '/', builder: (_, __) => const SuperAdminPanelScreen()),
  ],
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final start = await _resolveStartRoute();
  _superAdminRouter.go(start);
  runApp(
    ProviderScope(
      child: MaterialApp.router(
        title: 'Turfinn Super Admin',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: AppColors.background,
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            surface: AppColors.background,
          ),
          textTheme: GoogleFonts.dmSansTextTheme(ThemeData.dark().textTheme),
        ),
        routerConfig: _superAdminRouter,
      ),
    ),
  );
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      );
}
