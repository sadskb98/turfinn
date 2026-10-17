import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/config/app_config.dart';

part 'dio_client.g.dart';

const _baseUrl = AppConfig.apiBaseUrl;

@riverpod
Dio dio(Ref ref) {
  final d = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
    },
  ));

  // Auth interceptor — attach JWT from storage on every request
  d.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (error, handler) async {
      // 401: clear stale token so the next app launch goes through login
      // again instead of silently rendering empty cards.
      if (error.response?.statusCode == 401) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('auth_token');
        } catch (_) {}
      }
      handler.next(error);
    },
  ));

  return d;
}
