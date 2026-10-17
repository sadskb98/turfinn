import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/models/league_model.dart';
import '../../data/models/match_event_model.dart';
import '../../data/models/news_item_model.dart';
import '../../data/models/sports_feed_item_model.dart';
import '../../data/models/standings_model.dart';
import '../../data/sources/remote/sports_remote_source.dart';

part 'sports_provider.g.dart';

@riverpod
Future<List<League>> sportsLeagues(Ref ref) =>
    ref.watch(sportsRemoteSourceProvider).listLeagues();

@riverpod
Future<StandingsResponse> sportsStandings(
  Ref ref, {
  required int leagueId,
  int? season,
}) =>
    ref.watch(sportsRemoteSourceProvider).getStandings(
          leagueId: leagueId,
          season: season,
        );

@riverpod
Future<({List<SportsFeedItem> items, int total})> sportsFeed(
  Ref ref, {
  int page = 1,
  int limit = 20,
  int? leagueId,
}) =>
    ref.watch(sportsRemoteSourceProvider).listFeed(
          page: page,
          limit: limit,
          leagueId: leagueId,
        );

@riverpod
Future<({List<NewsItem> items, int total})> sportsNews(
  Ref ref, {
  int page = 1,
  int limit = 20,
  String? search,
  int? leagueId,
}) =>
    ref.watch(sportsRemoteSourceProvider).listNews(
          page: page,
          limit: limit,
          search: search,
          leagueId: leagueId,
        );

@riverpod
Future<({List<MatchEvent> items, int total})> sportsMatches(
  Ref ref, {
  int page = 1,
  int limit = 20,
  String? status,
  int? leagueId,
}) =>
    ref.watch(sportsRemoteSourceProvider).listMatches(
          page: page,
          limit: limit,
          status: status,
          leagueId: leagueId,
        );

/// Live + scheduled matches for the hero strip (filtered by league when set).
@riverpod
Future<List<MatchEvent>> heroStripMatches(Ref ref, {int? leagueId}) async {
  final remote = ref.watch(sportsRemoteSourceProvider);
  final live = await remote.listMatches(status: 'live', limit: 10, leagueId: leagueId);
  final upcoming =
      await remote.listMatches(status: 'scheduled', limit: 10, leagueId: leagueId);
  return [...live.items, ...upcoming.items];
}
