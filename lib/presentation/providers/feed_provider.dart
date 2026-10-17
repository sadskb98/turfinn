import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/models/match_post_model.dart';
import '../../data/sources/remote/feed_remote_source.dart';

part 'feed_provider.g.dart';

@riverpod
Future<({List<MatchPost> posts, int total})> feedList(
  Ref ref, {
  int page = 1,
  double? lat,
  double? lng,
  double radius = 10,
  String? postType,
}) =>
    ref.watch(feedRemoteSourceProvider).listFeed(
          page: page,
          lat: lat,
          lng: lng,
          radius: radius,
          postType: postType,
        );

@riverpod
Future<MatchPost> matchPost(Ref ref, String id) =>
    ref.watch(feedRemoteSourceProvider).getPost(id);

@riverpod
Future<({List<MatchPost> posts, int total})> myMatches(
  Ref ref, {
  String scope = 'upcoming',
}) =>
    ref.watch(feedRemoteSourceProvider).listMine(scope: scope);

/// Open matches grouped by pitch_id — used by the explore map to render a
/// match-indicator badge on pitches that have an active match looking for
/// players. Re-uses the same feed query to keep network round-trips minimal.
@riverpod
Future<Map<String, List<MatchPost>>> openMatchesByPitch(
  Ref ref, {
  double? lat,
  double? lng,
}) async {
  final result = await ref
      .watch(feedRemoteSourceProvider)
      .listFeed(lat: lat, lng: lng, limit: 50);
  final out = <String, List<MatchPost>>{};
  for (final p in result.posts) {
    if (p.status != 'open') continue;
    if (p.spotsFilled >= p.spotsTotal) continue;
    if (p.pitchId == null) continue;
    out.putIfAbsent(p.pitchId!, () => []).add(p);
  }
  return out;
}
