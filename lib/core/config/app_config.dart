/// Centralized app configuration — all values come from --dart-define at build time.
///
/// Usage:
///   flutter run --dart-define=API_BASE_URL=https://api.turfinn.com/api/v1
///   flutter build apk --dart-define=API_BASE_URL=https://api.turfinn.com/api/v1 --dart-define=GOOGLE_CLIENT_ID=...
///
/// For Docker web builds:
///   flutter build web --dart-define=API_BASE_URL=/api/v1
abstract final class AppConfig {
  // ── API ──────────────────────────────────────────────────────────────────
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8081/api/v1',
  );

  // ── Domain ───────────────────────────────────────────────────────────────
  static const domain = String.fromEnvironment(
    'DOMAIN',
    defaultValue: 'turfinn.com',
  );

  static const deepLinkScheme = String.fromEnvironment(
    'DEEP_LINK_SCHEME',
    defaultValue: 'https',
  );

  // ── Google Sign-In ───────────────────────────────────────────────────────
  static const googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '',
  );

  // ── Firebase ─────────────────────────────────────────────────────────────
  static const firebaseWebApiKey = String.fromEnvironment(
    'FIREBASE_WEB_API_KEY',
    defaultValue: '',
  );

  static const firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: '',
  );

  // ── bKash ────────────────────────────────────────────────────────────────
  static const bkashAppKey = String.fromEnvironment(
    'BKASH_APP_KEY',
    defaultValue: '',
  );

  static const bkashIsSandbox = bool.fromEnvironment(
    'BKASH_SANDBOX',
    defaultValue: true,
  );

  // ── Feature flags ────────────────────────────────────────────────────────
  static const enablePayments = bool.fromEnvironment(
    'ENABLE_PAYMENTS',
    defaultValue: false,
  );

  static const enablePushNotifications = bool.fromEnvironment(
    'ENABLE_PUSH',
    defaultValue: false,
  );

  // ── Helpers ──────────────────────────────────────────────────────────────
  static bool get isProduction => apiBaseUrl.contains('turfinn.com');
  static bool get hasGoogleSignIn => googleClientId.isNotEmpty;
  static bool get hasFirebase => firebaseProjectId.isNotEmpty;
  static bool get hasBkash => bkashAppKey.isNotEmpty && enablePayments;

  /// Deep link base: https://turfinn.com
  static String get deepLinkBase => '$deepLinkScheme://$domain';

  /// Share URLs
  static String tournamentUrl(String id) => '$deepLinkBase/tournaments/$id';
  static String pitchUrl(String id) => '$deepLinkBase/pitches/$id';
  static String referralUrl(String code) => '$deepLinkBase/join?ref=$code';
}
