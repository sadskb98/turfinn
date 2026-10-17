import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dio_client.dart';

part 'auth_remote_source.g.dart';

class AuthRemoteSource {
  AuthRemoteSource(this._dio);
  final Dio _dio;

  Future<void> sendOTP(String phone) async {
    await _dio.post('/auth/send-otp', data: {'phone': phone});
  }

  /// Returns {token, user} map
  Future<Map<String, dynamic>> verifyOTP(String phone, String otp) async {
    final res = await _dio.post('/auth/verify-otp', data: {
      'phone': phone,
      'otp': otp,
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  /// Exchanges a Google ID token for a Turfinn JWT.
  Future<Map<String, dynamic>> googleSignIn(String idToken) async {
    final res = await _dio.post('/auth/google', data: {'id_token': idToken});
    return res.data['data'] as Map<String, dynamic>;
  }
}

@riverpod
AuthRemoteSource authRemoteSource(Ref ref) {
  return AuthRemoteSource(ref.watch(dioProvider));
}
