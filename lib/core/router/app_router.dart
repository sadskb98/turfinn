import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/screens/splash/splash_screen.dart';
import '../../presentation/screens/onboarding/onboarding_screen.dart';
import '../../presentation/screens/welcome/welcome_screen.dart';
import '../../presentation/screens/sign_up/sign_up_screen.dart';
import '../../presentation/screens/sign_in/sign_in_screen.dart';
import '../../presentation/screens/auth/account_success_screen.dart';
import '../../presentation/screens/otp/otp_screen.dart';
import '../../presentation/screens/shell/app_shell.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/explore/explore_screen.dart';
import '../../presentation/screens/search/search_screen.dart';
import '../../presentation/screens/play/play_screen.dart';
import '../../presentation/screens/play/match_detail_screen.dart';
import '../../presentation/screens/play/my_matches_screen.dart';
import '../../presentation/screens/feed_tab/feed_tab_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';
import '../../presentation/screens/profile/profile_setup_screen.dart';
import '../../presentation/screens/profile/activity_screen.dart';
import '../../presentation/screens/profile/personal_info_screen.dart';
import '../../presentation/screens/profile/financial_info_screen.dart';
import '../../presentation/screens/booking/turf_detail_screen.dart';
import '../../presentation/screens/booking/booking_calendar_screen.dart';
import '../../presentation/screens/booking/checkout_screen.dart';
import '../../presentation/screens/booking/payment_screen.dart';
import '../../presentation/screens/booking/payment_success_screen.dart';
import '../../presentation/screens/booking/receipt_screen.dart';
import '../../presentation/screens/split/split_pay_screen.dart';
import '../../presentation/screens/teams/teams_screen.dart';
import '../../presentation/screens/teams/team_management_screen.dart';
import '../../presentation/screens/leaderboard/leaderboard_screen.dart';
import '../../presentation/screens/tournament/tournament_list_screen.dart';
import '../../presentation/screens/tournament/tournament_create_screen.dart';
import '../../presentation/screens/tournament/tournament_detail_screen.dart';
import '../../data/models/pitch_model.dart';
import '../../data/models/booking_model.dart';

abstract final class AppRoutes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  // Deep link paths — match /.well-known/apple-app-site-association paths
  static const pitchDeepLink = '/pitch/:id';
  static const bookingDeepLink = '/booking/:id';
  static const feedDeepLink = '/feed';
  static const teamsDeepLink = '/teams';
  static const welcome = '/welcome';
  static const signUp = '/sign-up';
  static const signIn = '/sign-in';
  static const otp = '/otp';
  static const home = '/home';
  static const explore = '/explore';
  static const search = '/search';
  static const feed = '/feed';
  static const sports = '/sports';
  static const matchDetail = '/match'; // /match/:id?joined=1
  static const myMatches = '/my-matches';
  static const profile = '/profile';
  static const profileSetup = '/profile/setup';
  static const personalInfo = '/profile/personal';
  static const financialInfo = '/profile/financial';
  static const activity = '/activity';
  static const leaderboard = '/leaderboard';
  static const teams = '/teams';
  static const teamManage = '/teams/manage';
  static const tournaments = '/tournaments';
  static const tournamentCreate = '/tournaments/create';
  static const checkout = '/checkout';
  static const payment = '/payment';
  static const paymentSuccess = '/payment/success';
  static const receipt = '/receipt';
  static const accountSuccess = '/account-success';

  // Public split-pay magic link — no auth.
  static const splitPay = '/split/:token';
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: AppRoutes.splash,
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.welcome,
      builder: (context, state) => const WelcomeScreen(),
    ),
    // Public split-pay magic link — friends drop in here from a WhatsApp
    // invite without an account. Pre-empts every auth-redirecting screen
    // because go_router matches paths in order.
    GoRoute(
      path: AppRoutes.splitPay,
      builder: (context, state) {
        final token = state.pathParameters['token'] ?? '';
        return SplitPayScreen(token: token);
      },
    ),
    GoRoute(
      path: AppRoutes.signUp,
      builder: (context, state) => const SignUpScreen(),
    ),
    GoRoute(
      path: AppRoutes.signIn,
      builder: (context, state) => const SignInScreen(),
    ),
    GoRoute(
      path: AppRoutes.accountSuccess,
      builder: (context, state) => const AccountSuccessScreen(),
    ),
    GoRoute(
      path: AppRoutes.otp,
      builder: (context, state) {
        final phone = state.extra as String? ?? '';
        return OtpScreen(phone: phone);
      },
    ),
    GoRoute(
      path: AppRoutes.profileSetup,
      builder: (context, state) => const ProfileSetupScreen(),
    ),
    GoRoute(
      path: AppRoutes.personalInfo,
      builder: (context, state) => const PersonalInfoScreen(),
    ),
    GoRoute(
      path: AppRoutes.financialInfo,
      builder: (context, state) => const FinancialInfoScreen(),
    ),
    GoRoute(
      path: AppRoutes.search,
      builder: (context, state) => const SearchScreen(),
    ),
    GoRoute(
      path: AppRoutes.activity,
      builder: (context, state) => const ActivityScreen(),
    ),
    GoRoute(
      path: AppRoutes.leaderboard,
      builder: (context, state) => const LeaderboardScreen(),
    ),
    GoRoute(
      path: AppRoutes.teamManage,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return TeamManagementScreen(
          team: extra['team'] as String,
          format: extra['format'] as String,
          teamId: extra['teamId'] as String?,
          teamCode: extra['teamCode'] as String?,
        );
      },
    ),
    GoRoute(
      path: AppRoutes.tournaments,
      builder: (context, state) => const TournamentListScreen(),
    ),
    GoRoute(
      path: AppRoutes.tournamentCreate,
      builder: (context, state) => const TournamentCreateScreen(),
    ),
    GoRoute(
      path: '/tournaments/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return TournamentDetailScreen(tournamentId: id);
      },
    ),
    // Deep link entry point: https://turfinn.app/pitch/<id>
    // extra is null when arriving via universal/app link — TurfDetailScreen handles that.
    GoRoute(
      path: '/pitch/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return TurfDetailScreen(pitchId: id, pitch: null);
      },
    ),
    // Deep link entry point: https://turfinn.app/booking/<id>
    GoRoute(
      path: '/booking/:id',
      redirect: (context, state) {
        // Bookings require auth; redirect to home and let the app handle navigation.
        return AppRoutes.home;
      },
    ),
    GoRoute(
      path: '/pitches/:id',
      builder: (context, state) {
        final pitch = state.extra as PitchModel?;
        final id = state.pathParameters['id']!;
        return TurfDetailScreen(pitchId: id, pitch: pitch);
      },
    ),
    GoRoute(
      path: '/pitches/:id/calendar',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return BookingCalendarScreen(
          pitch: extra['pitch'] as PitchModel,
          selectedSlotStart: extra['slotStart'] as DateTime,
          selectedSlotEnd: extra['slotEnd'] as DateTime,
        );
      },
    ),
    GoRoute(
      path: '${AppRoutes.matchDetail}/:id',
      builder: (context, state) {
        final id = state.pathParameters['id'] ?? '';
        final justJoined = state.uri.queryParameters['joined'] == '1';
        return MatchDetailScreen(matchId: id, justJoined: justJoined);
      },
    ),
    GoRoute(
      path: AppRoutes.myMatches,
      builder: (context, state) => const MyMatchesScreen(),
    ),
    GoRoute(
      path: AppRoutes.checkout,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return CheckoutScreen(
          pitch: extra['pitch'] as PitchModel,
          startsAt: extra['startsAt'] as DateTime,
          endsAt: extra['endsAt'] as DateTime,
        );
      },
    ),
    GoRoute(
      path: AppRoutes.payment,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return PaymentScreen(
          pitch: extra['pitch'] as PitchModel,
          startsAt: extra['startsAt'] as DateTime,
          endsAt: extra['endsAt'] as DateTime,
          method: extra['method'] as String,
          totalCost: extra['totalCost'] as double,
        );
      },
    ),
    GoRoute(
      path: AppRoutes.paymentSuccess,
      builder: (context, state) {
        final booking = state.extra as BookingModel?;
        return PaymentSuccessScreen(booking: booking);
      },
    ),
    GoRoute(
      path: AppRoutes.receipt,
      builder: (context, state) {
        final booking = state.extra as BookingModel;
        return ReceiptScreen(booking: booking);
      },
    ),
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: AppRoutes.explore,
          builder: (context, state) => const ExploreScreen(),
        ),
        GoRoute(
          path: AppRoutes.feed,
          builder: (context, state) => const PlayScreen(),
        ),
        GoRoute(
          path: AppRoutes.sports,
          builder: (context, state) => const FeedTabScreen(),
        ),
        GoRoute(
          path: AppRoutes.teams,
          builder: (context, state) => const TeamsScreen(),
        ),
        GoRoute(
          path: AppRoutes.profile,
          builder: (context, state) => const ProfileScreen(),
        ),
      ],
    ),
  ],
);
