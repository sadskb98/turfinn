import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../models/team_model.dart';
import 'dio_client.dart';

part 'team_remote_source.g.dart';

@riverpod
TeamRemoteSource teamRemoteSource(TeamRemoteSourceRef ref) =>
    TeamRemoteSource(ref.watch(dioProvider));

class TeamRemoteSource {
  TeamRemoteSource(this._dio);
  final Dio _dio;

  Future<TeamModel> createTeam({
    required String name,
    required String format,
    String? formation,
  }) async {
    final resp = await _dio.post('/teams', data: {
      'name': name,
      'format': format,
      if (formation != null) 'formation': formation,
    });
    return TeamModel.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<List<TeamModel>> listMyTeams() async {
    final resp = await _dio.get('/teams/my');
    final list = resp.data['data'] as List<dynamic>;
    return list
        .map((j) => TeamModel.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<TeamModel> getTeam(String id) async {
    final resp = await _dio.get('/teams/$id');
    return TeamModel.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<TeamModel> joinTeam(String code) async {
    final resp = await _dio.post('/teams/join', data: {'code': code});
    return TeamModel.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<TeamModel> updateFormation(String teamId, String formation) async {
    final resp = await _dio.put('/teams/$teamId/formation', data: {
      'formation': formation,
    });
    return TeamModel.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<MatchModel> findMatch(
    String teamId, {
    String wantedFormat = 'open',
    String city = '',
    double latitude = 0,
    double longitude = 0,
    double radiusKM = 0,
  }) async {
    final resp = await _dio.post('/matchmaking/find', data: {
      'team_id': teamId,
      'wanted_format': wantedFormat,
      if (city.isNotEmpty) 'city': city,
      if (latitude != 0 || longitude != 0) 'latitude': latitude,
      if (latitude != 0 || longitude != 0) 'longitude': longitude,
      if (radiusKM > 0) 'radius_km': radiusKM,
    });
    return MatchModel.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<MatchModel> getMatch(String matchId) async {
    final resp = await _dio.get('/matchmaking/$matchId');
    return MatchModel.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<void> transferCaptain(String teamId, String userId) async {
    await _dio
        .post('/teams/$teamId/transfer-captain', data: {'user_id': userId});
  }

  Future<void> removeMember(String teamId, String userId) async {
    await _dio.delete('/teams/$teamId/members/$userId');
  }

  Future<MatchModel?> getActiveMatch(String teamId) async {
    try {
      final resp = await _dio.get('/matchmaking/active/$teamId');
      return MatchModel.fromJson(resp.data['data'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<MatchModel> setVenue({
    required String matchId,
    required String pitchId,
    required DateTime scheduledAt,
  }) async {
    final resp = await _dio.put('/matchmaking/$matchId/venue', data: {
      'pitch_id': pitchId,
      'scheduled_at': scheduledAt.toUtc().toIso8601String(),
    });
    return MatchModel.fromJson(resp.data['data'] as Map<String, dynamic>);
  }
}
