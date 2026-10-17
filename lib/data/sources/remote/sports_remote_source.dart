import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/league_model.dart';
import '../../models/match_event_model.dart';
import '../../models/news_item_model.dart';
import '../../models/sports_feed_item_model.dart';
import '../../models/standings_model.dart';
import 'dio_client.dart';

part 'sports_remote_source.g.dart';

@riverpod
SportsRemoteSource sportsRemoteSource(Ref ref) =>
    SportsRemoteSource(ref.watch(dioProvider));

class SportsRemoteSource {
  SportsRemoteSource(this._dio);
  final Dio _dio;

  Future<List<League>> listLeagues() async {
    final resp = await _dio.get('/sports/leagues');
    final data = resp.data?['data'] as List? ?? [];
    return data
        .map((e) => League.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<StandingsResponse> getStandings({required int leagueId, int? season}) async {
    final resp = await _dio.get('/sports/standings', queryParameters: {
      'league_id': leagueId,
      if (season != null) 'season': season,
    });
    return StandingsResponse.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<({List<NewsItem> items, int total})> listNews({
    int page = 1,
    int limit = 20,
    String? category,
    String? search,
    int? leagueId,
  }) async {
    final resp = await _dio.get('/sports/news', queryParameters: {
      'page': page,
      'limit': limit,
      if (category != null && category.isNotEmpty) 'category': category,
      if (search != null && search.isNotEmpty) 'search': search,
      if (leagueId != null) 'league_id': leagueId,
    });
    final data = resp.data?['data'] as List? ?? [];
    final meta = resp.data?['meta'] as Map<String, dynamic>? ?? {};
    return (
      items: data
          .map((e) => NewsItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (meta['total'] as int?) ?? 0,
    );
  }

  Future<({List<MatchEvent> items, int total})> listMatches({
    int page = 1,
    int limit = 20,
    String? status,
    int? leagueId,
  }) async {
    final resp = await _dio.get('/sports/matches', queryParameters: {
      'page': page,
      'limit': limit,
      if (status != null && status.isNotEmpty) 'status': status,
      if (leagueId != null) 'league_id': leagueId,
    });
    final data = resp.data?['data'] as List? ?? [];
    final meta = resp.data?['meta'] as Map<String, dynamic>? ?? {};
    return (
      items: data
          .map((e) => MatchEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (meta['total'] as int?) ?? 0,
    );
  }

  Future<({List<SportsFeedItem> items, int total})> listFeed({
    int page = 1,
    int limit = 20,
    int? leagueId,
  }) async {
    final resp = await _dio.get('/sports/feed', queryParameters: {
      'page': page,
      'limit': limit,
      if (leagueId != null) 'league_id': leagueId,
    });
    final data = resp.data?['data'] as List? ?? [];
    final meta = resp.data?['meta'] as Map<String, dynamic>? ?? {};
    return (
      items: data
          .map((e) => SportsFeedItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (meta['total'] as int?) ?? 0,
    );
  }
}
