import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../models/user_model.dart';
import 'dio_client.dart';

part 'user_remote_source.g.dart';

@riverpod
UserRemoteSource userRemoteSource(UserRemoteSourceRef ref) =>
    UserRemoteSource(ref.watch(dioProvider));

class UserRemoteSource {
  UserRemoteSource(this._dio);
  final Dio _dio;

  Future<UserModel> getMe() async {
    final resp = await _dio.get('/users/me');
    return UserModel.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<UserModel> updateMe({
    String? name,
    String? avatarUrl,
    String? position,
    String? skillLevel,
  }) async {
    final resp = await _dio.put('/users/me', data: {
      if (name != null) 'name': name,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (position != null) 'position': position,
      if (skillLevel != null) 'skill_level': skillLevel,
    });
    return UserModel.fromJson(resp.data['data'] as Map<String, dynamic>);
  }
}
