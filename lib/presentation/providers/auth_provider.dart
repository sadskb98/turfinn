import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../data/sources/remote/auth_remote_source.dart';
import '../../data/sources/remote/dio_client.dart';

part 'auth_provider.g.dart';

// ── State ────────────────────────────────────────────────────────────────────

sealed class AuthState {}

class AuthInitial extends AuthState {}
class AuthLoading extends AuthState {}
class AuthOTPSent extends AuthState {
  AuthOTPSent({required this.phone});
  final String phone;
}
class AuthAuthenticated extends AuthState {
  AuthAuthenticated({required this.token, required this.user});
  final String token;
  final Map<String, dynamic> user;
}
class AuthError extends AuthState {
  AuthError(this.message);
  final String message;
}

// ── Notifier ─────────────────────────────────────────────────────────────────

@riverpod
class Auth extends _$Auth {
  @override
  AuthState build() => AuthInitial();

  Future<void> sendOTP(String phone) async {
    state = AuthLoading();
    try {
      await ref.read(authRemoteSourceProvider).sendOTP(phone);
      state = AuthOTPSent(phone: phone);
    } on Exception catch (e) {
      state = AuthError(_parseError(e));
    }
  }

  Future<void> verifyOTP(String phone, String otp) async {
    state = AuthLoading();
    try {
      final data = await ref.read(authRemoteSourceProvider).verifyOTP(phone, otp);
      final token = data['token'] as String;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
      state = AuthAuthenticated(token: token, user: data['user'] as Map<String, dynamic>);
      _registerFcmToken();
    } on Exception catch (e) {
      state = AuthError(_parseError(e));
    }
  }

  Future<void> signInWithGoogle() async {
    state = AuthLoading();
    try {
      final googleSignIn = GoogleSignIn(
        clientId: kIsWeb ? AppConfig.googleClientId : null,
        scopes: ['email', 'profile'],
      );
      final account = await googleSignIn.signIn();
      if (account == null) {
        state = AuthInitial();
        return;
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        state = AuthError('Google sign-in failed: no ID token.');
        return;
      }
      final data = await ref.read(authRemoteSourceProvider).googleSignIn(idToken);
      final token = data['token'] as String;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
      state = AuthAuthenticated(token: token, user: data['user'] as Map<String, dynamic>);
      _registerFcmToken();
    } on Exception catch (e) {
      state = AuthError(_parseError(e));
    }
  }

  void _registerFcmToken() {
    if (kIsWeb) return;
    FirebaseMessaging.instance.requestPermission().then((_) async {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken == null) return;
      try {
        final dio = ref.read(dioProvider);
        await dio.put('/users/me/fcm-token', data: {'token': fcmToken});
      } catch (_) {}
    });
    // Tokens rotate (Android ~30 days, iOS more often). Subscribe to refresh
    // events so we keep the server-side token current — otherwise pushes
    // start silently dropping on long-lived sessions.
    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      try {
        final dio = ref.read(dioProvider);
        await dio.put('/users/me/fcm-token', data: {'token': token});
      } catch (_) {}
    });
  }

  String _parseError(Exception e) {
    final s = e.toString();
    if (s.contains('otp expired') || s.contains('invalid otp')) return 'Invalid or expired OTP.';
    if (s.contains('Connection refused') || s.contains('SocketException')) {
      return 'Cannot reach server. Is the backend running?';
    }
    return 'Something went wrong. Please try again.';
  }
}
