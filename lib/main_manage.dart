// Manager web entry. Login goes straight to the dashboard — the
// previous in-app KYC flow (NID upload, selfie, business name) was
// removed because:
//   1. Storing NID photos + selfies in our DB requires a Bangladesh PII
//      handling licence we don't have.
//   2. Real KYC happens offline before super-admin registers the manager
//      via /super-admin/managers, so the in-app step was redundant.
// We keep the backend KYC tables in place for now (no migration drop) so
// they're available if/when we obtain the licence — they're just
// unreachable from the app.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_colors.dart';
import 'presentation/screens/manage/manage_login_screen.dart';
import 'presentation/screens/manage/manage_panel_screen.dart';

Future<String> _resolveStartRoute() async {
  final prefs = await SharedPreferences.getInstance();
  // Both keys for safety — manager_token (legacy) + auth_token (current
  // dio interceptor reads this one).
  final token =
      prefs.getString('auth_token') ?? prefs.getString('manager_token');
  if (token == null || token.isEmpty) return '/login';
  return '/';
}

final _manageRouter = GoRouter(
  initialLocation: '/loading',
  routes: [
    GoRoute(path: '/loading', builder: (_, __) => const _LoadingScreen()),
    GoRoute(path: '/login', builder: (_, __) => const ManageLoginScreen()),
    GoRoute(path: '/', builder: (_, __) => const ManagePanelScreen()),
  ],
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final startRoute = await _resolveStartRoute();
  _manageRouter.go(startRoute);
  runApp(
    ProviderScope(
      child: MaterialApp.router(
        title: 'Turfinn Turf Manager',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: AppColors.background,
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            surface: AppColors.background,
          ),
          textTheme: GoogleFonts.dmSansTextTheme(ThemeData.dark().textTheme),
        ),
        routerConfig: _manageRouter,
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
