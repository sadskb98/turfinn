import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../models/tournament_model.dart';
import 'dio_client.dart';

part 'tournament_remote_source.g.dart';

@riverpod
TournamentRemoteSource tournamentRemoteSource(TournamentRemoteSourceRef ref) =>
    TournamentRemoteSource(ref.watch(dioProvider));

class TournamentRemoteSource {
  TournamentRemoteSource(this._dio);
  final Dio _dio;

  Future<List<TournamentModel>> list({int page = 1, int limit = 20}) async {
    final resp = await _dio.get('/tournaments',
        queryParameters: {'page': page, 'limit': limit});
    final data = resp.data['data'] as List;
    return data
        .map((e) => TournamentModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TournamentDetail> get(String id) async {
    final resp = await _dio.get('/tournaments/$id');
    return TournamentDetail.fromJson(
        resp.data['data'] as Map<String, dynamic>);
  }

  Future<TournamentModel> create({
    required String name,
    required String format,
    required int maxTeams,
    String description = '',
    int entryFee = 0,
    int minCoins = 0,
    String visibility = 'public',
    String? startsAt,
  }) async {
    final resp = await _dio.post('/tournaments', data: {
      'name': name,
      'format': format,
      'max_teams': maxTeams,
      'description': description,
      'entry_fee': entryFee,
      'min_coins': minCoins,
      'visibility': visibility,
      if (startsAt != null) 'starts_at': startsAt,
    });
    return TournamentModel.fromJson(
        resp.data['data'] as Map<String, dynamic>);
  }

  Future<void> join(String tournamentId, String teamId,
      {String? inviteCode}) async {
    await _dio.post('/tournaments/$tournamentId/join', data: {
      'team_id': teamId,
      if (inviteCode != null && inviteCode.isNotEmpty)
        'invite_code': inviteCode,
    });
  }

  Future<void> start(String tournamentId) async {
    await _dio.post('/tournaments/$tournamentId/start');
  }

  Future<void> cancel(String tournamentId) async {
    await _dio.post('/tournaments/$tournamentId/cancel');
  }

  Future<void> leave(String tournamentId, String teamId) async {
    await _dio.post('/tournaments/$tournamentId/leave', data: {'team_id': teamId});
  }

  Future<void> reportScore(
      String tournamentId, String matchId, int homeScore, int awayScore) async {
    await _dio
        .post('/tournaments/$tournamentId/matches/$matchId/report', data: {
      'home_score': homeScore,
      'away_score': awayScore,
    });
  }

  Future<void> confirmScore(String tournamentId, String matchId) async {
    await _dio.post('/tournaments/$tournamentId/matches/$matchId/confirm');
  }

  Future<void> disputeScore(
      String tournamentId, String matchId, String reason) async {
    await _dio
        .post('/tournaments/$tournamentId/matches/$matchId/dispute', data: {
      'reason': reason,
    });
  }
}
